@echo off
title VietApps - Cap nhat khoa Gemini AI
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update_ai_keys.ps1"
echo.
echo Nhan phim bat ky de thoat...
pause >nul
