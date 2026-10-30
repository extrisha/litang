@echo off
cd /d "%~dp0"
echo Starting local preview server...
python serve.py
pause
