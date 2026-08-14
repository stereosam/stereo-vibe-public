@echo off
setlocal
chcp 65001 >nul
REM Repair mode: installs missing and updates outdated tools.
REM NOTE: keep this file ASCII-only. cmd.exe parses .cmd in the OEM codepage,
REM so Cyrillic text here breaks parsing. All Russian UX lives in the .ps1.

REM --- Admin rights ----------------------------------------------------------
REM Without them winget installs die halfway: the student sees "it started
REM installing and gave up". So we ask for elevation up front via UAC.
REM If the student declines, we continue unelevated with a warning.
net session >nul 2>nul
if %errorlevel% equ 0 goto :admin_ok

echo.
echo   Requesting administrator rights (needed to install programs)...
echo   Click "Yes" if Windows asks.
echo.
if "%~1"=="" (
  %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
) else (
  %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command "try { Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
)
if %errorlevel% equ 0 exit /b 0

echo.
echo   Rights not granted - continuing WITHOUT them.
echo   Installing and updating programs may fail.
echo.

:admin_ok
set "PS=powershell"
where pwsh >nul 2>nul && set "PS=pwsh"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0core\check-work-tools.ps1" -ReportDir "%~dp0reports" -InstallMissing -Update %*
exit /b %ERRORLEVEL%
