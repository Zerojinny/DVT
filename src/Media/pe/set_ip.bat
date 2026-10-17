@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT media - set_ip.bat (WinPE)
rem  Applies a static IPv4 address given on the command line.
rem  Same as pe\set_ip.bat, but the address, mask and gateway come
rem  from get_input.bat (ip.txt of the media + the operator's input)
rem  instead of an ip.txt that holds only the address.
rem   - DNS comes from config.cmd
rem   - every connected adapter is tried; the first one that reaches
rem     the gateway (and NET_TEST_HOST, if set) is kept, the others
rem     are switched back to DHCP
rem   - when no adapter works, all adapters are tried again after
rem     SET_IP_RETRY_SEC seconds, up to SET_IP_RETRIES times (config.cmd)
rem
rem  Usage  : call set_ip.bat <ip> <mask> <gateway>
rem  Returns: NET_IP, NET_GW, NET_ADAPTER
rem  Exit   : 0 = OK
rem           1 = an argument is missing
rem           2 = no connected adapter reaches the network
rem ============================================================

call "%~dp0config.cmd"

set "IP=%~1"
set "MASK=%~2"
set "GW=%~3"
set "DONE="
set "OKNAME="

if not defined IP goto :usage
if not defined MASK goto :usage
if not defined GW goto :usage
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
endlocal & set "NET_IP=%IP%" & set "NET_GW=%GW%" & set "NET_ADAPTER=%OKNAME%" & exit /b 0


:usage
echo [ERROR] Usage: set_ip.bat ^<ip^> ^<mask^> ^<gateway^>
exit /b 1


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
