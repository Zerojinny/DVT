@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - check_gateway.bat (WinPE, shared)
rem  bats\common: used by the client local boot and the USB / CD media.
rem  Checks that the default gateway answers ping.
rem
rem  Usage : call check_gateway.bat [gateway]
rem          Without an argument the gateway of the default route
rem          with the lowest metric is used.
rem  Exit  : 0 = gateway answered
rem          1 = no answer
rem          2 = no default gateway found
rem ============================================================

call "%~dp0config.cmd"

set "GW=%~1"
if defined GW goto :ping

set "BEST=999999"
for /f "tokens=1-5" %%a in ('route print -4 2^>nul') do (
    if "%%a"=="0.0.0.0" if "%%b"=="0.0.0.0" if not "%%e"=="" call :consider "%%c" "%%e"
)
if not defined GW (
    echo [ERROR] No default gateway was found.
    exit /b 2
)

:ping
echo [INFO] Checking gateway %GW%...
call "%~dp0ping_host.bat" %GW% 3
if errorlevel 1 (
    echo [ERROR] The gateway %GW% does not answer. Check the cable and the switch.
    exit /b 1
)
echo [INFO] Gateway OK.
exit /b 0


rem ============================================================
rem  :consider "<gateway>" "<metric>"
rem  Keeps the gateway of the default route with the lowest metric.
rem ============================================================
:consider
if /i "%~1"=="On-link" exit /b 0
set "M=%~2"
for /f "delims=0123456789" %%z in ("%M%") do exit /b 0
if %M% LSS %BEST% (
    set "BEST=%M%"
    set "GW=%~1"
)
exit /b 0
