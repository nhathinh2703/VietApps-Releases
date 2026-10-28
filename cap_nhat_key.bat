@echo off
title VietApps - Update Gemini AI Keys
cls

echo ==================================================================
echo         VIETAPPS - UPDATE GEMINI AI KEYS TO GITHUB
echo ==================================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update_ai_keys.ps1"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Script exited with code %errorlevel%.
)

echo.
echo Press any key to exit...
pause >nul
