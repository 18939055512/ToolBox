@echo off
chcp 65001 >nul
echo ========================================
echo   工具管理站 - 启动
echo ========================================
echo.

cd /d "%~dp0"

node server.js

pause
