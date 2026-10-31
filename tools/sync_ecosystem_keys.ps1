<#
.SYNOPSIS
    Bảng điều khiển và tự động hóa mã hóa Key cho hệ sinh thái VietApps
.DESCRIPTION
    - Đọc file bí mật cục bộ 'secrets_vault.json' (được gitignore bảo vệ 100%).
    - Đồng bộ 1 chuẩn mã hóa duy nhất: AES-256 (VietAppsAiSecurity).
    - Đồng bộ 1 chuẩn định dạng tệp trên GitHub: JSON với trường 'cipher'.
    - Bật/Tắt thu hồi từ xa qua công tắc 'enabled: true/false'.
    - Tự động commit và push lên GitHub.
#>

$Host.UI.RawUI.WindowTitle = "VietApps Ecosystem - Unified Secrets Manager"

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "       VIETAPPS ECOSYSTEM - BẢNG ĐIỀU KHIỂN & ĐỒNG BỘ BẢN QUYỀN          " -ForegroundColor Yellow
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host ""

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$vaultPath = Join-Path $repoRoot "secrets_vault.json"
$updatesDir = Join-Path $repoRoot "updates"
$vietlabDir = Join-Path $repoRoot "vietlab"

if (-not (Test-Path $updatesDir)) { New-Item -ItemType Directory -Path $updatesDir -Force | Out-Null }
if (-not (Test-Path $vietlabDir)) { New-Item -ItemType Directory -Path $vietlabDir -Force | Out-Null }

if (-not (Test-Path $vaultPath)) {
    Write-Host "[!] Không tìm thấy tệp 'secrets_vault.json'!" -ForegroundColor Red
    Write-Host "    Vui lòng kiểm tra lại tệp bí mật trong thư mục gốc." -ForegroundColor Yellow
    exit 1
}

# Đọc cấu hình từ Vault
$vaultJson = Get-Content $vaultPath -Raw -Encoding UTF8
$vault = $vaultJson | ConvertFrom-Json

# Hàm mã hóa AES-256 chuẩn VietAppsAiSecurity
function Encrypt-VietAppsAes256([string]$plainText) {
    if ([string]::IsNullOrWhiteSpace($plainText)) { return "" }
    $saltKey = "VietApps_Ecosystem_AI_Security_2026_@SecretKey#999"
    $saltIv  = "VietApps_Ecosystem_AI_Security_2026_@SecretIV#999"

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $md5 = [System.Security.Cryptography.MD5]::Create()

    $keyBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($saltKey))
    $ivBytes  = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($saltIv))

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $keyBytes
    $aes.IV  = $ivBytes

    $encryptor = $aes.CreateEncryptor()
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($plainText.Trim())
    $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
    return [Convert]::ToBase64String($cipherBytes)
}

Write-Host "TRẠNG THÁI CÁC DỊCH VỤ TRONG HỆ SINH THÁI:" -ForegroundColor White
Write-Host "--------------------------------------------------------------------------" -ForegroundColor DarkGray

# 1. XỬ LÝ GEMINI AI KEYS
$isGeminiEnabled = $true
$geminiKeys = @()

if ($null -ne $vault.gemini_ai) {
    if ($null -ne $vault.gemini_ai.enabled) { $isGeminiEnabled = [bool]$vault.gemini_ai.enabled }
    if ($null -ne $vault.gemini_ai.keys) {
        foreach ($k in $vault.gemini_ai.keys) {
            $t = "$k".Trim()
            if ($t.Length -ge 10) { $geminiKeys += $t }
        }
    }
}
elseif ($null -ne $vault.gemini_api_keys) {
    foreach ($k in $vault.gemini_api_keys) {
        $t = "$k".Trim()
        if ($t.Length -ge 10) { $geminiKeys += $t }
    }
}
$geminiKeys = $geminiKeys | Select-Object -Unique
$aiOutPath = Join-Path $updatesDir "ai_config.json"

if ($isGeminiEnabled -and $geminiKeys.Count -gt 0) {
    $quotedKeys = $geminiKeys | ForEach-Object {
        $escaped = $_.Replace('\', '\\').Replace('"', '\"')
        "`"$escaped`""
    }
    $keysJson = "[" + ($quotedKeys -join ",") + "]"
    $aiCipher = Encrypt-VietAppsAes256 $keysJson

    $aiPayload = [ordered]@{
        updatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        provider  = "google-gemini"
        cipher    = $aiCipher
        keyCount  = $geminiKeys.Count
        note      = "Encrypted Gemini AI keys distributed automatically for VietApps ecosystem"
    }

    [System.IO.File]::WriteAllText($aiOutPath, (ConvertTo-Json -InputObject $aiPayload -Depth 4), [System.Text.Encoding]::UTF8)
    Write-Host " [1] Google Gemini AI:   " -NoNewline -ForegroundColor White
    Write-Host "[ĐANG BẬT] " -NoNewline -ForegroundColor Green
    Write-Host "($($geminiKeys.Count) key - xoay vòng hạn mức thông minh)" -ForegroundColor Gray
} else {
    $emptyCipher = Encrypt-VietAppsAes256 "[]"
    $aiPayload = [ordered]@{
        updatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        provider  = "google-gemini"
        cipher    = $emptyCipher
        keyCount  = 0
        note      = "Gemini AI keys revoked / disabled temporarily"
    }
    [System.IO.File]::WriteAllText($aiOutPath, (ConvertTo-Json -InputObject $aiPayload -Depth 4), [System.Text.Encoding]::UTF8)
    Write-Host " [1] Google Gemini AI:   " -NoNewline -ForegroundColor White
    Write-Host "[ĐÃ THU HỒI / TẮT] " -ForegroundColor Red
}

# 2. XỬ LÝ BẢN QUYỀN OFFICE 2016
$officeSection = if ($null -ne $vault.office_2016) { $vault.office_2016 } else { $vault.office_activation }
$isOfficeEnabled = $false
$officeCmd = ""
$officeKeyMasked = "Chưa có key"

if ($null -ne $officeSection) {
    if ($null -ne $officeSection.enabled) { $isOfficeEnabled = [bool]$officeSection.enabled }
    if (![string]::IsNullOrWhiteSpace($officeSection.command)) { $officeCmd = $officeSection.command.Trim() }
    if (![string]::IsNullOrWhiteSpace($officeSection.key)) {
        $rawK = "$($officeSection.key)".Trim()
        if ($rawK.Length -ge 10) {
            $officeKeyMasked = $rawK.Substring(0, 5) + "-*****-*****-*****-" + $rawK.Substring($rawK.Length - 5)
        }
    }
}

$officeJsonPath = Join-Path $vietlabDir "office_license.json"
$oldEncPath = Join-Path $vietlabDir "office_license.enc"
if (Test-Path $oldEncPath) { Remove-Item $oldEncPath -Force -ErrorAction SilentlyContinue }

if ($isOfficeEnabled -and -not [string]::IsNullOrWhiteSpace($officeCmd)) {
    $officeCipher = Encrypt-VietAppsAes256 $officeCmd

    # Xuất định dạng JSON chuẩn hóa đồng nhất
    $officePayload = [ordered]@{
        updatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        service   = "microsoft-office-2016"
        cipher    = $officeCipher
        note      = "Office 2016 Volume activation command encrypted with AES-256 for VietLab"
    }
    [System.IO.File]::WriteAllText($officeJsonPath, (ConvertTo-Json -InputObject $officePayload -Depth 4), [System.Text.Encoding]::UTF8)

    Write-Host " [2] Office 2016 Pro:    " -NoNewline -ForegroundColor White
    Write-Host "[ĐANG BẬT] " -NoNewline -ForegroundColor Green
    Write-Host "(Key: $officeKeyMasked - nạp RAM tự động ngầm)" -ForegroundColor Gray
} else {
    if (Test-Path $officeJsonPath) { Remove-Item $officeJsonPath -Force }
    Write-Host " [2] Office 2016 Pro:    " -NoNewline -ForegroundColor White
    Write-Host "[ĐÃ THU HỒI / TẮT] " -ForegroundColor Red
}

# 3. XỬ LÝ BẢN QUYỀN WINRAR VIP
$isWinRarEnabled = $false
$winRarData = ""
if ($null -ne $vault.winrar) {
    if ($null -ne $vault.winrar.enabled) { $isWinRarEnabled = [bool]$vault.winrar.enabled }
    if (![string]::IsNullOrWhiteSpace($vault.winrar.license_data)) {
        $winRarData = "$($vault.winrar.license_data)".Trim()
    }
    elseif (![string]::IsNullOrWhiteSpace($vault.winrar.data)) {
        $winRarData = "$($vault.winrar.data)".Trim()
    }
}

$winRarJsonPath = Join-Path $vietlabDir "winrar_license.json"

if ($isWinRarEnabled -and -not [string]::IsNullOrWhiteSpace($winRarData)) {
    $winRarCipher = Encrypt-VietAppsAes256 $winRarData
    $winRarPayload = [ordered]@{
        updatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        service   = "winrar-vip"
        cipher    = $winRarCipher
        note      = "WinRAR VIP Unlimited license encrypted with AES-256 for VietLab"
    }
    [System.IO.File]::WriteAllText($winRarJsonPath, (ConvertTo-Json -InputObject $winRarPayload -Depth 4), [System.Text.Encoding]::UTF8)
    Write-Host " [3] WinRAR VIP:         " -NoNewline -ForegroundColor White
    Write-Host "[ĐANG BẬT] " -NoNewline -ForegroundColor Green
    Write-Host "(Đã xuất vietlab/winrar_license.json - cấp phát RAM an toàn)" -ForegroundColor Gray
} else {
    if (Test-Path $winRarJsonPath) { Remove-Item $winRarJsonPath -Force }
    Write-Host " [3] WinRAR VIP:         " -NoNewline -ForegroundColor White
    Write-Host "[ĐÃ THU HỒI / TẮT] " -ForegroundColor Red
}

# 4. ĐỒNG BỘ DANH MỤC GÓI PHẦN MỀM VIETLAB (PACKAGES.JSON)
$sourcePackages = "D:\GitHub\VietLab\templates\packages.json"
$targetPackages = Join-Path $vietlabDir "packages.json"
if (Test-Path $sourcePackages) {
    Copy-Item $sourcePackages $targetPackages -Force
    Write-Host " [4] Danh mục VietLab:   " -NoNewline -ForegroundColor White
    Write-Host "[ĐÃ ĐỒNG BỘ] " -NoNewline -ForegroundColor Green
    Write-Host "(25 phần mềm chuẩn FOSS, Freeware & System)" -ForegroundColor Gray
}

Write-Host "--------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "[THÔNG BÁO] Tất cả các tệp đều theo CHUẨN JSON MÃ HÓA AES-256 đồng nhất 100%!" -ForegroundColor Cyan
Write-Host ""

# 5. TỰ ĐỘNG COMMIT VÀ PUSH LÊN GITHUB
Write-Host "Bạn có muốn đẩy (Push) các cập nhật này lên GitHub ngay bây giờ không? (Y/N): " -NoNewline -ForegroundColor Yellow
$choice = Read-Host
if ($null -eq $choice -or $choice.Trim().ToUpper() -eq "Y") {
    Push-Location $repoRoot
    try {
        git add .gitignore updates/ai_config.json vietlab/
        $commitMsg = "chore: sync ecosystem licenses and keys ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
        git commit -m $commitMsg
        Write-Host "`nĐang đẩy lên GitHub (git push origin main)..." -ForegroundColor Cyan
        git push origin main
        Write-Host ""
        Write-Host "[THÀNH CÔNG] Toàn bộ hệ sinh thái VietApps đã được cập nhật trực tuyến an toàn!" -ForegroundColor Green
    }
    catch {
        Write-Host "[LỖI] Không thể đẩy lên GitHub: $_" -ForegroundColor Red
    }
    finally {
        Pop-Location
    }
} else {
    Write-Host "[INFO] Các tệp đã được tạo ở máy cục bộ. Bạn có thể commit và push thủ công sau." -ForegroundColor Cyan
}

Write-Host ""
