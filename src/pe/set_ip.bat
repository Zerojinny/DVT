@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - set_ip.bat (WinPE)
rem  Applies the static IPv4 settings stored in ip.txt.
rem   - ip.txt holds one value per line (written by get_host_ip.bat):
rem       line 1 = ip       e.g. 203.244.132.150
rem       line 2 = subnet   e.g. 255.255.255.0
rem       line 3 = gateway  e.g. 203.244.132.1
rem   - an older ip.txt with the address only still works:
rem       subnet = NET_MASK, gateway = first three octets + ".1"
rem   - DNS comes from config.cmd
rem   - every connected adapter is tried; the first one that reaches
rem     the gateway (and NET_TEST_HOST, if set) is kept, the others
rem     are switched back to DHCP
rem   - when no adapter works, all adapters are tried again after
rem     SET_IP_RETRY_SEC seconds, up to SET_IP_RETRIES times (config.cmd)
rem
rem  Usage  : call set_ip.bat [path\to\ip.txt]   (default: IP_FILE)
rem  Returns: NET_IP, NET_MASK_USED, NET_GW, NET_ADAPTER
rem  Exit   : 0 = OK
rem           1 = ip.txt missing or invalid
rem           2 = no connected adapter reaches the network
rem ============================================================

call "%~dp0config.cmd"

set "SRC=%~1"
if not defined SRC set "SRC=%IP_FILE%"
if not exist "%SRC%" (
    echo [ERROR] IP file not found: "%SRC%"
    exit /b 1
)

set "IP="
set "MASK="
set "GW="
set "DONE="
set "OKNAME="
set "BADIP="
set "BADWHAT="

rem ---- read ip.txt: line 1 = ip, line 2 = subnet, line 3 = gateway ----
rem empty lines and lines starting with # are skipped
set "VN=0"
for /f "usebackq eol=# tokens=1" %%a in ("%SRC%") do call :collect "%%a"

rem ---- validate: 4 numeric octets, 0-255 ----
set "BADWHAT=ip (line 1)"
call :check_ip "%IP%"
if defined BADIP goto :bad_ip
for /f "tokens=1-3 delims=." %%a in ("%IP%") do set "NETPFX=%%a.%%b.%%c"

if not defined MASK set "MASK=%NET_MASK%"
set "BADWHAT=subnet (line 2)"
call :check_ip "%MASK%"
if defined BADIP goto :bad_ip

rem an ip.txt without a gateway line: x.x.x.1
if not defined GW set "GW=%NETPFX%.1"
set "BADWHAT=gateway (line 3)"
call :check_ip "%GW%"
if defined BADIP goto :bad_ip

if "%GW%"=="%IP%" (
    echo [ERROR] The IP address is the same as the gateway: %IP%
    exit /b 1
)

echo [INFO] Static IP: %IP%  Mask: %MASK%  Gateway: %GW%  DNS: %NET_DNS1% %NET_DNS2%

rem ---- try every connected adapter ----
rem When no adapter reaches the network, every adapter is tried again
rem after SET_IP_RETRY_SEC seconds, up to SET_IP_RETRIES more times
rem (a link or switch port can need some time after WinPE starts).
set "RETRIES=%SET_IP_RETRIES%"
if not defined RETRIES set "RETRIES=3"
for /f "delims=0123456789" %%z in ("%RETRIES%") do set "RETRIES=3"
set "RETRY_SEC=%SET_IP_RETRY_SEC%"
if not defined RETRY_SEC set "RETRY_SEC=10"
set /a ROUNDS=RETRIES+1
set /a ROUND=0

:try_round
set /a ROUND+=1
if %ROUND% GTR 1 echo.
echo [INFO] Adapter round %ROUND% of %ROUNDS%
rem netsh columns: Admin-State  State  Type  Interface-Name
for /f "tokens=1,2,3*" %%a in ('netsh interface show interface') do (
    if not defined DONE call :check "%%b" "%%c" "%%d"
)
if defined DONE goto :round_ok
if %ROUND% GEQ %ROUNDS% goto :round_failed
echo [WARN] No connected adapter reached the network. Retrying in %RETRY_SEC% seconds...
call "%~dp0wait.bat" %RETRY_SEC%
goto :try_round

:round_failed
echo [ERROR] No connected adapter reaches the network with %IP% after %ROUNDS% rounds.
exit /b 2

:round_ok

echo [INFO] Static IP applied to adapter: %OKNAME%
netsh interface ip show config name="%OKNAME%"
endlocal & set "NET_IP=%IP%" & set "NET_MASK_USED=%MASK%" & set "NET_GW=%GW%" & set "NET_ADAPTER=%OKNAME%" & exit /b 0


:bad_ip
echo [ERROR] Invalid or missing %BADWHAT% in "%SRC%"
echo         Expected one value per line:
echo           203.244.132.150    ip
echo           255.255.255.0      subnet
echo           203.244.132.1      gateway
exit /b 1


rem ============================================================
rem  :collect "<value>"   1st value -> IP, 2nd -> MASK, 3rd -> GW
rem ============================================================
:collect
set "CV=%~1"
if not defined CV exit /b 0
set /a VN+=1
if %VN%==1 set "IP=%CV%"
if %VN%==2 set "MASK=%CV%"
if %VN%==3 set "GW=%CV%"
exit /b 0


rem ============================================================
rem  :check_ip "<a.b.c.d>"   sets BADIP=1 unless it is a valid address
rem ============================================================
:check_ip
set "CI=%~1"
if not defined CI (
    set "BADIP=1"
    exit /b 0
)
set "O1="
set "O2="
set "O3="
set "O4="
for /f "tokens=1-4 delims=." %%a in ("%CI%") do (
    set "O1=%%a"
    set "O2=%%b"
    set "O3=%%c"
    set "O4=%%d"
)
rem the rebuilt string must equal the original (rejects missing or extra parts)
if not "!O1!.!O2!.!O3!.!O4!"=="%CI%" (
    set "BADIP=1"
    exit /b 0
)
call :octet "!O1!"
call :octet "!O2!"
call :octet "!O3!"
call :octet "!O4!"
exit /b 0


rem ============================================================
rem  :octet "<value>"   sets BADIP=1 unless the value is 0-255
rem ============================================================
:octet
set "X=%~1"
if not defined X goto :octet_bad
for /f "delims=0123456789" %%z in ("%X%") do goto :octet_bad
rem prefix with 1 so leading zeros are not read as octal; 1255 = 255
set /a V=1%X%
if %V% GTR 1255 goto :octet_bad
exit /b 0
:octet_bad
set "BADIP=1"
exit /b 0


rem ============================================================
rem  :check "<state>" "<type>" "<name>"
rem ============================================================
:check
if /i not "%~1"=="Connected" exit /b 0
if /i "%~2"=="Loopback" exit /b 0
if "%~3"=="" exit /b 0
call :try "%~3"
exit /b 0


rem ============================================================
rem  :try "<adapter name>"
rem ============================================================
:try
set "IFNAME=%~1"
echo.
echo [INFO] Trying adapter: %IFNAME%

netsh interface ip set address name="%IFNAME%" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1 >nul
if defined NET_DNS1 netsh interface ip set dns name="%IFNAME%" source=static addr=%NET_DNS1% >nul
if defined NET_DNS2 netsh interface ip add dns name="%IFNAME%" addr=%NET_DNS2% index=2 >nul

rem give the adapter time to apply the address
call "%~dp0wait.bat" 3

call "%~dp0ping_host.bat" %GW% 3
if errorlevel 1 goto :try_fail
if not defined NET_TEST_HOST goto :try_ok
call "%~dp0ping_host.bat" %NET_TEST_HOST% 2
if errorlevel 1 goto :try_fail

:try_ok
set "DONE=1"
set "OKNAME=%IFNAME%"
echo [INFO] Network reachable through: %IFNAME%
exit /b 0

:try_fail
echo [WARN] No response through "%IFNAME%". Switching it back to DHCP.
netsh interface ip set address name="%IFNAME%" source=dhcp >nul
netsh interface ip set dns name="%IFNAME%" source=dhcp >nul
exit /b 1
