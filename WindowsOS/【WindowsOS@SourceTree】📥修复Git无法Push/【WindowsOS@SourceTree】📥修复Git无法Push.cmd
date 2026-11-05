@echo off
setlocal DisableDelayedExpansion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run.ps1" %*
set "JOBS_EXIT=%ERRORLEVEL%"
if "%~1"=="" if not "%JOBS_EXIT%"=="0" pause
exit /b %JOBS_EXIT%
