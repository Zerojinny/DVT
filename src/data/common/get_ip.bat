@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - get_ip.bat (WinPE, shared)
rem  data\common: used by the client local boot and the USB / CD media.
rem  Waits for DHCP and returns the IPv4 address of the adapter
rem  that owns the default route with the lowest metric.
rem   1) route print  (main method)
rem   2) ipconfig     (fallback)
rem
rem  start_media.bat also uses it to detect the network type: no
rem  DHCP address within the given tries means a static network.
rem
rem  Usage  : call get_ip.bat [tries]   (2-second tries, default DHCP_WAIT_TRIES)
rem  Returns: NET_IP, NET_GW
rem  Exit   : 0 = OK
rem           1 = no adapter with a default gateway (no DHCP address)
rem ============================================================

call "%~dp0config.cmd"

set "TRIES=%DHCP_WAIT_TRIES%"
if not "%~1"=="" set "TRIES=%~1"
set /a TRY=0

:retry
set "MYIP="
set "MYGW="
set "BEST=999999"

rem ---- 1) route print ----
rem Active route columns: destination  netmask  gateway  interface  metric
rem Persistent-route lines have only 4 columns and are skipped.
for /f "tokens=1-5" %%a in ('route print -4 2^>nul') do (
    if "%%a"=="0.0.0.0" if "%%b"=="0.0.0.0" if not "%%e"=="" call :consider "%%c" "%%d" "%%e"
)
if defined MYIP goto :found

rem ---- 2) ipconfig ----
call :from_ipconfig
if defined MYIP goto :found

set /a TRY+=1
if %TRY% GEQ %TRIES% goto :not_found
if %TRY% EQU 1 echo [INFO] Waiting for DHCP...
call "%~dp0wait.bat" 2
goto :retry


:found
echo [INFO] DHCP address: %MYIP%   Gateway: %MYGW%
endlocal & set "NET_IP=%MYIP%" & set "NET_GW=%MYGW%" & exit /b 0

:not_found
echo [INFO] No DHCP address was received.
endlocal & exit /b 1


rem ============================================================
rem  :consider "<gateway>" "<interface ip>" "<metric>"
rem  Keeps the default route with the lowest metric.
rem ============================================================
:consider
if /i "%~1"=="On-link" exit /b 0
set "C_IP=%~2"
if "%C_IP:.=%"=="%C_IP%" exit /b 0
call :is_number "%~3" || exit /b 0
if %~3 LSS %BEST% (
    set "BEST=%~3"
    set "MYIP=%~2"
    set "MYGW=%~1"
)
exit /b 0


rem ============================================================
rem  :from_ipconfig
rem  Takes the first adapter that has both an IPv4 address and an
rem  IPv4 default gateway. The IPv4 gateway can be on the line after
rem  "Default Gateway" when an IPv6 gateway is listed first.
rem ============================================================
:from_ipconfig
set "CUR_IP="
set "IN_GW="
for /f "tokens=1,* delims=:" %%a in ('ipconfig 2^>nul') do (
    set "K=%%a"
    set "V=%%b"
    set "GWV="
    if not "!K:adapter=!"=="!K!" (
        set "CUR_IP="
        set "IN_GW="
    ) else if not "!K:IPv4=!"=="!K!" (
        set "IN_GW="
        set "CUR_IP="
        for /f "tokens=1" %%i in ("!V!") do set "CUR_IP=%%i"
        if defined CUR_IP set "CUR_IP=!CUR_IP:(Preferred)=!"
    ) else if not "!K:Default Gateway=!"=="!K!" (
        set "IN_GW=1"
        for /f "tokens=1" %%i in ("!V!") do set "GWV=%%i"
    ) else if defined IN_GW (
        if defined V (
            set "IN_GW="
        ) else (
            for /f "tokens=1" %%i in ("!K!") do set "GWV=%%i"
        )
    )
    if defined GWV if not "!GWV:.=!"=="!GWV!" if defined CUR_IP if not defined MYIP (
        set "MYIP=!CUR_IP!"
        set "MYGW=!GWV!"
    )
)
exit /b 0


rem ============================================================
rem  :is_number "<value>"   exit 0 = digits only, 1 = anything else
rem ============================================================
:is_number
set "NUMTEST=%~1"
if not defined NUMTEST exit /b 1
for /f "delims=0123456789" %%z in ("%NUMTEST%") do exit /b 1
exit /b 0
