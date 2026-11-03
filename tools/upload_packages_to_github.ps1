# PowerShell Script: Tự động tải các file cài đặt từ binaries_staging lên GitHub Releases
# và tự động cập nhật direct link vào vietlab/packages.json

param (
    [string]$Tag = "packages-v1.0",
    [string]$Repo = "nhathinh2703/VietApps-Releases"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$stagingDir = Join-Path $rootDir "binaries_staging"
$manifestPath = Join-Path $rootDir "vietlab\packages.json"

if (-not (Test-Path $stagingDir)) {
    Write-Host "Chưa tìm thấy thư mục: $stagingDir" -ForegroundColor Red
    exit 1
}

$files = Get-ChildItem -Path $stagingDir -File | Where-Object { 
    $_.Extension -in @(".exe", ".msi", ".iso", ".zip", ".rar", ".7z") 
}

if ($files.Count -eq 0) {
    Write-Host "Không có tệp cài đặt nào (.exe, .msi, .iso, .zip, .rar, .7z) trong thư mục $stagingDir" -ForegroundColor Yellow
    exit 0
}

Write-Host "Tìm thấy $($files.Count) tệp cài đặt cần đưa lên GitHub Releases ($Tag)..." -ForegroundColor Cyan

# 1. Kiểm tra xem Release đã tồn tại chưa, nếu chưa thì tạo mới
$releaseCheck = & gh release view $Tag --repo $Repo 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Đang tạo Release mới: $Tag trên $Repo..." -ForegroundColor Yellow
    & gh release create $Tag --title "VietLab Software Packages (Kho bộ cài phòng máy)" `
        --notes "Kho lưu trữ tệp cài đặt phần mềm tự động (Silent Packages) cho phòng máy VietLab." `
        --repo $Repo
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Không thể tạo Release: $releaseCheck" -ForegroundColor Red
        exit 1
    }
}

# 2. Đọc tệp manifest packages.json nếu có
$manifest = $null
if (Test-Path $manifestPath) {
    $rawJson = Get-Content $manifestPath -Raw -Encoding UTF8
    $manifest = $rawJson | ConvertFrom-Json
}

$uploadedCount = 0
$updatedPackages = @()

foreach ($file in $files) {
    Write-Host "--> Đang tải lên: $($file.Name) ($([Math]::Round($file.Length / 1MB, 2)) MB)..." -ForegroundColor Green
    & gh release upload $Tag $file.FullName --clobber --repo $Repo
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Lỗi khi tải file $($file.Name) lên GitHub Releases." -ForegroundColor Red
        continue
    }

    $uploadedCount++
    $directUrl = "https://github.com/$Repo/releases/download/$Tag/$($file.Name)"
    Write-Host "    Link tải trực tiếp: $directUrl" -ForegroundColor Gray

    # 3. Tự động ánh xạ và cập nhật vào packages.json
    if ($manifest) {
        $matched = $false
        foreach ($pkg in $manifest) {
            # Khớp theo FileName hoặc tên file
            if ($pkg.FileName -ieq $file.Name -or 
                $file.Name.StartsWith($pkg.Id, [System.StringComparison]::OrdinalIgnoreCase) -or
                ($pkg.Id -eq "basicmouse" -and $file.Name -match "mouse") -or
                ($pkg.Id -eq "kirantyping" -and $file.Name -match "kiran") -or
                ($pkg.Id -eq "mindmaple" -and $file.Name -match "mindmap") -or
                ($pkg.Id -eq "bluestacks" -and $file.Name -match "bluestack") -or
                ($pkg.Id -eq "office2016" -and ($file.Name -match "office" -or $file.Name -match "2016VLA1")) -or
                ($pkg.Id -eq "gcompris" -and $file.Name -match "gcompris") -or
                ($pkg.Id -eq "ganttproject" -and $file.Name -match "gantt") -or
                ($pkg.Id -eq "mysql" -and $file.Name -match "mysql") -or
                ($pkg.Id -eq "ultraviewer" -and $file.Name -match "ultraviewer") -or
                ($pkg.Id -eq "kidscience" -and $file.Name -match "kid")) {
                
                $pkg.DownloadUrl = $directUrl
                $pkg.FileName = $file.Name
                $matched = $true
                $updatedPackages += $pkg.Name
                Write-Host "    [Khớp danh mục] Đã gán link cho gói: $($pkg.Name)" -ForegroundColor Cyan
                break
            }
        }

        if (-not $matched) {
            Write-Host "    [Chưa có trong danh mục] File $($file.Name) sẽ được giữ link trực tiếp để giáo viên sử dụng." -ForegroundColor Yellow
        }
    }
}

# 4. Ghi lại tệp packages.json và commit lên git
if ($manifest -and $updatedPackages.Count -gt 0) {
    Write-Host "Đang cập nhật tệp manifest: $manifestPath..." -ForegroundColor Yellow
    $newJson = $manifest | ConvertTo-Json -Depth 10
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($manifestPath, $newJson, $utf8NoBom)

    Push-Location $rootDir
    try {
        & git add vietlab/packages.json
        & git commit -m "feat(vietlab): cập nhật direct link cho $($updatedPackages.Count) gói phần mềm từ GitHub Releases"
        & git push origin main
        Write-Host "Đã đồng bộ packages.json lên GitHub main thành công!" -ForegroundColor Green
    }
    catch {
        Write-Host "Lỗi khi push git: $_" -ForegroundColor Red
    }
    finally {
        Pop-Location
    }
}

Write-Host "Hoàn tất! Đã đưa thành công $uploadedCount tệp lên GitHub Releases." -ForegroundColor Green
