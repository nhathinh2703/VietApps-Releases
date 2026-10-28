<#
.SYNOPSIS
    Công cụ mã hóa và cập nhật khóa Gemini API lên VietApps-Releases
.DESCRIPTION
    Tự động mã hóa AES-256 các khóa API của tác giả trước khi đẩy lên GitHub,
    chống bot quét thu hồi key và bảo vệ quota hệ sinh thái VietApps.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "VietApps - Quản lý Khóa Gemini AI"

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "   HỆ SINH THÁI VIETAPPS - CẬP NHẬT KHÓA GEMINI AI LÊN GITHUB    " -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$outputJsonPath = Join-Path $repoRoot "updates\ai_config.json"

# Kiểm tra thư mục updates
$updatesDir = Split-Path $outputJsonPath
if (-not (Test-Path $updatesDir)) {
    New-Item -ItemType Directory -Path $updatesDir -Force | Out-Null
}

Write-Host "Nhập hoặc dán danh sách khóa Gemini API (mỗi khóa 1 dòng hoặc cách nhau bằng dấu phẩy):" -ForegroundColor White
Write-Host "(Nhấn Enter 2 lần hoặc gõ 'END' để kết thúc việc nhập)" -ForegroundColor DarkGray
Write-Host ""

$inputLines = @()
while ($true) {
    $line = Read-Host
    if ($null -eq $line -or $line.Trim() -eq "" -or $line.Trim().ToUpper() -eq "END") {
        if ($inputLines.Count -gt 0) {
            break
        }
        else {
            Write-Host "Chưa có khóa nào được nhập. Bạn có muốn thoát? (Y/N): " -NoNewline -ForegroundColor Yellow
            $quitChoice = Read-Host
            if ($quitChoice.Trim().ToUpper() -eq "Y") {
                exit
            }
            continue
        }
    }
    $inputLines += $line
}

$rawCombined = ($inputLines -join "`n")
$keys = @()
$rawCombined -split "[,;\r\n]" | ForEach-Object {
    $k = $_.Trim()
    if ($k.Length -ge 10) {
        $keys += $k
    }
}
$keys = $keys | Select-Object -Unique

if ($keys.Count -eq 0) {
    Write-Host "[!] Không tìm thấy khóa hợp lệ nào (độ dài tối thiểu 10 ký tự)." -ForegroundColor Red
    pause
    exit
}

Write-Host ""
Write-Host "[✓] Đã nhận diện được $($keys.Count) khóa Gemini API:" -ForegroundColor Green
for ($i = 0; $i -lt $keys.Count; $i++) {
    $k = $keys[$i]
    $masked = if ($k.Length -gt 8) { $k.Substring(0, 4) + "..." + $k.Substring($k.Length - 4) } else { "***" }
    Write-Host "    $($i + 1). $masked" -ForegroundColor Cyan
}

# Mã hóa AES-256
$saltKey = "VietApps_Ecosystem_AI_Security_2026_@SecretKey#999"
$saltIv  = "VietApps_Ecosystem_AI_Security_2026_@SecretIV#999"

$sha = [System.Security.Cryptography.SHA256]::Create()
$md5 = [System.Security.Cryptography.MD5]::Create()

$keyBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($saltKey))
$ivBytes  = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($saltIv))

$aes = [System.Security.Cryptography.Aes]::Create()
$aes.Key = $keyBytes
$aes.IV  = $ivBytes

# Chuyển mảng keys thành chuỗi JSON
$keysJson = ConvertTo-Json -InputObject $keys -Compress
$plainBytes = [System.Text.Encoding]::UTF8.GetBytes($keysJson)

$encryptor = $aes.CreateEncryptor()
$cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
$cipherBase64 = [Convert]::ToBase64String($cipherBytes)

# Tạo cấu trúc file JSON
$payload = [ordered]@{
    updatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    provider  = "google-gemini"
    cipher    = $cipherBase64
    keyCount  = $keys.Count
    note      = "Khóa Gemini AI phân phối tự động cho hệ sinh thái VietApps (Đã mã hóa bảo vệ)"
}

$outputJson = ConvertTo-Json -InputObject $payload -Depth 4
[System.IO.File]::WriteAllText($outputJsonPath, $outputJson, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "[✓] Đã tạo file mã hóa thành công tại: updates\ai_config.json" -ForegroundColor Green
Write-Host ""

# Tùy chọn Git Commit & Push
Write-Host "Bạn có muốn Commit và Push tự động lên GitHub ngay không? (Y/N): " -NoNewline -ForegroundColor Yellow
$pushChoice = Read-Host
if ($pushChoice.Trim().ToUpper() -eq "Y") {
    Push-Location $repoRoot
    try {
        git add updates/ai_config.json
        git commit -m "chore(ai): update encrypted Gemini AI keys ($($keys.Count) keys)"
        Write-Host "Đang đẩy lên GitHub..." -ForegroundColor Cyan
        git push origin main
        Write-Host ""
        Write-Host "[✓] Hoàn tất! Tất cả các ứng dụng VietApps sẽ tự động nhận $($keys.Count) khóa mới khi khởi động." -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Lỗi khi đẩy lên GitHub: $_" -ForegroundColor Red
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Host "[i] File ai_config.json đã được lưu tại chỗ. Bạn có thể tự commit sau." -ForegroundColor Cyan
}

Write-Host ""
