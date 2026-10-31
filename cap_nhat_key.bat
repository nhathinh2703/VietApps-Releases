@echo off
title VietApps - Dong bo Ban quyen & AI Keys len GitHub
cls

echo ==================================================================
echo      VIETAPPS - DONG BO BAN QUYEN VA AI KEYS LEN GITHUB
echo ==================================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\sync_ecosystem_keys.ps1"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Script gap loi voi ma: %errorlevel%.
)

echo.
echo Nhan phim bat ky de thoat...
pause >nul
