@echo off
setlocal
chcp 65001 >nul
REM Report-only: nothing is installed or updated. Safe to run anywhere.
set "PS=powershell"
where pwsh >nul 2>nul && set "PS=pwsh"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0check-work-tools.ps1" -ReportDir "%~dp0..\reports" -ReportOnly %*
exit /b %ERRORLEVEL%
