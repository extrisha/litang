@echo off
setlocal
chcp 65001 >nul

:: 纯相对路径引导：通过批处理目录定位 Node.js 打包脚本
set "SCRIPT_DIR=%~dp0"
set "NODE_SCRIPT=%SCRIPT_DIR%build_apk.mjs"

if not exist "%NODE_SCRIPT%" (
    echo [错误] 未找到构建脚本: %NODE_SCRIPT%
    pause
    exit /b 1
)

node "%NODE_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%1"=="--no-pause" (
    echo.
    echo 请按任意键继续...
    pause >nul
)

exit /b %EXIT_CODE%
