@echo off
setlocal DisableDelayedExpansion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Menu.ps1" %*
set "JOBS_EXIT=%ERRORLEVEL%"
pause
exit /b %JOBS_EXIT%
