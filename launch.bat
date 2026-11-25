@echo off
rem Launch Slotbound with Slotbound Tweaks (Windows). See launch.ps1.
rem Steam runs as a 32-bit process, so cmd.exe started from it is 32-bit too;
rem Sysnative reaches the 64-bit PowerShell, which is needed to debug the 64-bit game.
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch.ps1" %*
