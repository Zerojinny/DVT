@echo off
setlocal EnableExtensions
rem ============================================================
rem  DVT - wait.bat (WinPE)
rem  Waits for the given number of seconds.
rem  timeout.exe is not part of WinPE, so ping is used instead.
rem
rem  Usage : call wait.bat <seconds>
rem  Exit  : 0
rem ============================================================

set "SEC=%~1"
if not defined SEC set "SEC=1"
set /a "SEC=SEC" 2>nul
if %SEC% LSS 1 exit /b 0
set /a "COUNT=SEC+1"
ping -n %COUNT% 127.0.0.1 >nul 2>&1
exit /b 0
