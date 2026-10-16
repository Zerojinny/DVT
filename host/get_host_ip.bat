@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - get_host_ip.bat (Windows)
rem  Finds the adapter that owns the IPv4 default route with the
rem  lowest metric and checks whether its address is static or
rem  assigned by DHCP.
rem   - Static          : IP_FILE gets one value per line:
rem                         line 1 = ip, line 2 = subnet, line 3 = gateway
rem   - Dynamic/Unknown : IP_FILE is deleted, so an address left by
rem                       an earlier run is never reused
rem
rem  Returns: HOST_IP, HOST_MASK, HOST_GW, HOST_ADAPTER,
rem           HOST_IP_MODE (Static / Dynamic / Unknown)
rem  Exit   : 0 = OK
rem           1 = IP_FILE could not be written or deleted
rem           2 = no adapter with a default gateway
rem ============================================================

call "%~dp0config.cmd"
if not exist "%WORK_DIR%\" mkdir "%WORK_DIR%" 2>nul

rem ---- 1) default route with the lowest metric ----
rem Columns: destination  netmask  gateway  interface  metric
rem Persistent-route lines have only 4 columns and are skipped.
set "BEST=999999"
set "IFIP="
set "GW="
for /f "tokens=1-5" %%a in ('route print -4 0.0.0.0') do (
    if "%%a"=="0.0.0.0" if "%%b"=="0.0.0.0" if not "%%e"=="" call :consider "%%c" "%%d" "%%e"
)

if not defined IFIP (
    echo [ERROR] No adapter with a default gateway was found.
    if exist "%IP_FILE%" del /f /q "%IP_FILE%" >nul 2>&1
    exit /b 2
)

rem ---- 2) find that address in the TCP/IP interface keys ----
set "MODE="
set "GUID="
set "IFMASK="
for /f "delims=" %%K in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" 2^>nul') do (
    if not defined MODE call :check_interface "%%K"
)
if not defined MODE set "MODE=Unknown"

rem ---- 3) adapter name from the interface GUID ----
set "ADNAME=(unknown)"
if defined GUID (
    for /f "tokens=1,2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Network\{4D36E972-E325-11CE-BFC1-08002BE10318}\%GUID%\Connection" /v Name 2^>nul') do (
        if /i "%%A"=="Name" set "ADNAME=%%C"
    )
)

echo ==============================================
echo  Adapter : !ADNAME!
echo  IP      : %IFIP%
if defined IFMASK echo  Subnet  : %IFMASK%
echo  Gateway : %GW%
echo  Mode    : %MODE%
echo ==============================================

rem ---- 4) keep ip.txt only for a static address ----
rem line 1 = ip, line 2 = subnet, line 3 = gateway
if "%MODE%"=="Static" (
    if not defined IFMASK (
        set "IFMASK=255.255.255.0"
        echo [WARN] The subnet mask could not be read. Using 255.255.255.0
    )
    > "%IP_FILE%" (
        echo %IFIP%
        echo !IFMASK!
        echo %GW%
    )
    if not exist "%IP_FILE%" (
        echo [ERROR] Could not write "%IP_FILE%"
        exit /b 1
    )
    echo [INFO] Static IP, subnet and gateway saved to "%IP_FILE%"
) else (
    if exist "%IP_FILE%" del /f /q "%IP_FILE%" >nul 2>&1
    if exist "%IP_FILE%" (
        echo [ERROR] Could not delete the old "%IP_FILE%"
        exit /b 1
    )
    if "%MODE%"=="Unknown" echo [WARN] The address type could not be determined. WinPE will use DHCP.
    if "%MODE%"=="Dynamic" echo [INFO] DHCP address. WinPE will use DHCP.
)

endlocal & set "HOST_IP=%IFIP%" & set "HOST_MASK=%IFMASK%" & set "HOST_GW=%GW%" & set "HOST_ADAPTER=%ADNAME%" & set "HOST_IP_MODE=%MODE%" & exit /b 0


rem ============================================================
rem  :consider "<gateway>" "<interface ip>" "<metric>"
rem ============================================================
:consider
if /i "%~1"=="On-link" exit /b 0
set "M=%~3"
for /f "delims=0123456789" %%z in ("%M%") do exit /b 0
if %M% LSS %BEST% (
    set "BEST=%M%"
    set "GW=%~1"
    set "IFIP=%~2"
)
exit /b 0


rem ============================================================
rem  :check_interface "<registry key>"
rem  Sets MODE and GUID when the key belongs to IFIP, and IFMASK
rem  (subnet mask) for a static address.
rem  Static addresses and masks are REG_MULTI_SZ, shown as "a\0b" by
rem  reg; the n-th mask belongs to the n-th address. For DHCP the
rem  mask is DhcpSubnetMask.
rem ============================================================
:check_interface
set "KEY=%~1"
set "EN="
set "DHCPIP="
set "STATICIP="
set "STATICMASK="
set "DHCPMASK="
set "MYIDX="
for /f "tokens=1,2,*" %%A in ('reg query "%KEY%" /v EnableDHCP 2^>nul') do if /i "%%A"=="EnableDHCP" set "EN=%%C"
for /f "tokens=1,2,*" %%A in ('reg query "%KEY%" /v DhcpIPAddress 2^>nul') do if /i "%%A"=="DhcpIPAddress" set "DHCPIP=%%C"
for /f "tokens=1,2,*" %%A in ('reg query "%KEY%" /v IPAddress 2^>nul') do if /i "%%A"=="IPAddress" set "STATICIP=%%C"
for /f "tokens=1,2,*" %%A in ('reg query "%KEY%" /v SubnetMask 2^>nul') do if /i "%%A"=="SubnetMask" set "STATICMASK=%%C"
for /f "tokens=1,2,*" %%A in ('reg query "%KEY%" /v DhcpSubnetMask 2^>nul') do if /i "%%A"=="DhcpSubnetMask" set "DHCPMASK=%%C"

if "%EN%"=="0x1" if /i "%DHCPIP%"=="%IFIP%" (
    set "MODE=Dynamic"
    set "IFMASK=%DHCPMASK%"
    for %%G in ("%KEY%") do set "GUID=%%~nxG"
    exit /b 0
)
if not "%EN%"=="0x0" exit /b 0
if not defined STATICIP exit /b 0
set "LIST=!STATICIP:\0= !"
set /a N=0
for %%i in (!LIST!) do (
    set /a N+=1
    if "%%i"=="%IFIP%" if not defined MYIDX (
        set "MODE=Static"
        set "MYIDX=!N!"
        for %%G in ("%KEY%") do set "GUID=%%~nxG"
    )
)
if not defined MYIDX exit /b 0
if not defined STATICMASK exit /b 0
set "MLIST=!STATICMASK:\0= !"
set /a N=0
for %%m in (!MLIST!) do (
    set /a N+=1
    if "!N!"=="!MYIDX!" set "IFMASK=%%m"
)
exit /b 0
