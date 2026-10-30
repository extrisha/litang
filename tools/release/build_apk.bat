@echo off
setlocal
cd /d "%~dp0..\.."

echo ==================================================
echo  Project_USST Release Packaging Launcher
echo ==================================================

where node >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Node.js not found in PATH!
    echo Please make sure Node.js is installed or run: flutter build apk --release
    goto :END
)

node "%~dp0build_apk.mjs" %*

:END
echo.
pause
