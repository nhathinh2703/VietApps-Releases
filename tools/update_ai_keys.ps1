<#
.SYNOPSIS
    Tool to encrypt and update Gemini API keys for VietApps-Releases
.DESCRIPTION
    Encrypts API keys with AES-256 before publishing to GitHub
    to prevent secret scanning and protect ecosystem quota.
#>

$Host.UI.RawUI.WindowTitle = "VietApps - Manage Gemini AI Keys"

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "   VIETAPPS ECOSYSTEM - UPDATE GEMINI AI KEYS TO GITHUB           " -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$outputJsonPath = Join-Path $repoRoot "updates\ai_config.json"

# Ensure updates directory exists
$updatesDir = Split-Path $outputJsonPath
if (-not (Test-Path $updatesDir)) {
    New-Item -ItemType Directory -Path $updatesDir -Force | Out-Null
}

Write-Host "Enter or paste Gemini API keys (one per line, or separated by commas):" -ForegroundColor White
Write-Host "(Press Enter twice on empty line or type 'END' to finish input)" -ForegroundColor DarkGray
Write-Host ""

$inputLines = @()
while ($true) {
    $line = Read-Host
    if ($null -eq $line) {
        if ($inputLines.Count -gt 0) {
            break
        } else {
            exit 0
        }
    }

    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.ToUpper() -eq "END") {
        if ($inputLines.Count -gt 0) {
            break
        }
        else {
            Write-Host "No keys entered yet. Do you want to exit? (Y/N): " -NoNewline -ForegroundColor Yellow
            $quitChoice = Read-Host
            if ($null -eq $quitChoice -or $quitChoice.Trim().ToUpper() -ne "N") {
                exit 0
            }
            continue
        }
    }
    $inputLines += $trimmed
}

$rawCombined = ($inputLines -join "`n")
$keys = @()
$rawCombined -split "[,;\r\n]" | ForEach-Object {
    if ($null -ne $_) {
        $k = $_.Trim()
        if ($k.Length -ge 10) {
            $keys += $k
        }
    }
}
$keys = $keys | Select-Object -Unique

if ($keys.Count -eq 0) {
    Write-Host "[!] No valid keys found (minimum length is 10 characters)." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[OK] Recognized $($keys.Count) valid Gemini API key(s):" -ForegroundColor Green
for ($i = 0; $i -lt $keys.Count; $i++) {
    $k = $keys[$i]
    $masked = if ($k.Length -gt 8) { $k.Substring(0, 4) + "..." + $k.Substring($k.Length - 4) } else { "***" }
    Write-Host "    $($i + 1). $masked" -ForegroundColor Cyan
}

# AES-256 Encryption
$saltKey = "VietApps_Ecosystem_AI_Security_2026_@SecretKey#999"
$saltIv  = "VietApps_Ecosystem_AI_Security_2026_@SecretIV#999"

$sha = [System.Security.Cryptography.SHA256]::Create()
$md5 = [System.Security.Cryptography.MD5]::Create()

$keyBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($saltKey))
$ivBytes  = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($saltIv))

$aes = [System.Security.Cryptography.Aes]::Create()
$aes.Key = $keyBytes
$aes.IV  = $ivBytes

# Convert keys array to clean JSON array string: ["key1", "key2"]
$quotedKeys = $keys | ForEach-Object {
    $escaped = $_.Replace('\', '\\').Replace('"', '\"')
    "`"$escaped`""
}
$keysJson = "[" + ($quotedKeys -join ",") + "]"
$plainBytes = [System.Text.Encoding]::UTF8.GetBytes($keysJson)

$encryptor = $aes.CreateEncryptor()
$cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
$cipherBase64 = [Convert]::ToBase64String($cipherBytes)

# Create output JSON structure
$payload = [ordered]@{
    updatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    provider  = "google-gemini"
    cipher    = $cipherBase64
    keyCount  = $keys.Count
    note      = "Encrypted Gemini AI keys distributed automatically for VietApps ecosystem"
}

$outputJson = ConvertTo-Json -InputObject $payload -Depth 4
[System.IO.File]::WriteAllText($outputJsonPath, $outputJson, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "[OK] Encrypted configuration saved successfully to: updates\ai_config.json" -ForegroundColor Green
Write-Host ""

# Optional Git Commit & Push
Write-Host "Do you want to commit and push to GitHub now? (Y/N): " -NoNewline -ForegroundColor Yellow
$pushChoice = Read-Host
if ($null -ne $pushChoice -and $pushChoice.Trim().ToUpper() -eq "Y") {
    Push-Location $repoRoot
    try {
        git add updates/ai_config.json
        git commit -m "chore(ai): update encrypted Gemini AI keys ($($keys.Count) keys)"
        Write-Host "Pushing to GitHub..." -ForegroundColor Cyan
        git push origin main
        Write-Host ""
        Write-Host "[OK] Success! All VietApps applications will automatically sync $($keys.Count) new key(s) on startup." -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to push to GitHub: $_" -ForegroundColor Red
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Host "[INFO] File ai_config.json has been saved locally. You can commit and push later." -ForegroundColor Cyan
}

Write-Host ""
