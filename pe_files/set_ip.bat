
rem =====================================================
rem  WinPE static IP setter
rem  - no WMI / no PowerShell / no findstr / no find
rem  - ip.txt (same folder) format, one value per line:
rem        line 1 : IP address
rem        line 2 : Subnet mask
rem        line 3 : Default gateway
rem  - DNS is fixed below
rem  - tries each connected adapter and keeps the one
rem    whose gateway really responds to ping
rem    (no internet connectivity check)
rem =====================================================

rem ---------------- fixed settings (edit here) ----------------
set "DNS1=8.8.8.8"
set "DNS2=8.8.4.4"

rem ---------------- read ip.txt ----------------
set "IPFILE=%~dp0ip.txt"
if not exist "%IPFILE%" set "IPFILE=%CD%\ip.txt"
if not exist "%IPFILE%" goto :ERR_NOFILE

set "IP="
set "MASK="
set "GW="
set "DONE="
set "OKNAME="
set "BADIP="
set "BADLABEL="
set "BADVAL="
set "LN=0"

rem line 1 = IP, line 2 = MASK, line 3 = GATEWAY (empty lines are skipped)
for /f "usebackq delims=" %%a in ("%IPFILE%") do call :READLINE "%%a"

if not defined IP goto :ERR_FORMAT
if not defined MASK goto :ERR_FORMAT
if not defined GW goto :ERR_FORMAT

rem ---------------- validate IP / MASK / GATEWAY ----------------
call :VALIDATE "IP address" "%IP%"
if defined BADIP goto :ERR_BADIP
call :VALIDATE "Subnet mask" "%MASK%"
if defined BADIP goto :ERR_BADIP
call :VALIDATE "Gateway" "%GW%"
if defined BADIP goto :ERR_BADIP

if "%GW%"=="%IP%" goto :ERR_SAMEGW

echo [INFO] IP=%IP%  MASK=%MASK%  GW=%GW%  DNS1=%DNS1%  DNS2=%DNS2%

rem ---------------- try every connected adapter ----------------
rem netsh columns: Admin-State  State  Type  Interface-Name
for /f "tokens=1,2,3*" %%a in ('netsh interface show interface') do call :CHECK "%%b" "%%c" "%%d"

if not defined DONE goto :ERR_NONET

echo.
echo [DONE] Applied to adapter: %OKNAME%
netsh interface ip show config name="%OKNAME%"
exit /b 0


rem ---------------- error exits ----------------
:ERR_NOFILE
echo [ERROR] ip.txt not found: %IPFILE%
exit /b 1

:ERR_FORMAT
echo [ERROR] ip.txt must contain 3 lines:
echo         line 1 = IP address, line 2 = subnet mask, line 3 = gateway
exit /b 1

:ERR_BADIP
echo [ERROR] Invalid or empty %BADLABEL% in ip.txt: "%BADVAL%"
echo         (example: 203.244.132.150 / 255.255.255.0 / 203.244.132.1)
exit /b 1

:ERR_SAMEGW
echo [ERROR] IP address is the same as the gateway: %IP%
exit /b 1

:ERR_NONET
echo.
echo [FAIL] No connected adapter with a reachable gateway was found.
exit /b 2


rem ---------------- :READLINE "text"  (store line 1/2/3) ----------------
:READLINE
set /a LN+=1
set "LV=%~1"
set "LV=%LV: =%"
if "%LN%"=="1" set "IP=%LV%"
if "%LN%"=="2" set "MASK=%LV%"
if "%LN%"=="3" set "GW=%LV%"
exit /b 0


rem ---------------- :VALIDATE "label" "value"  (4 numeric octets, 0-255) ----------------
rem sets BADIP=1 (and BADLABEL / BADVAL) when the value is invalid
:VALIDATE
set "VLABEL=%~1"
set "VVAL=%~2"
set "O1="
set "O2="
set "O3="
set "O4="
for /f "tokens=1-4 delims=." %%a in ("%VVAL%") do call :SPLIT "%%a" "%%b" "%%c" "%%d"

rem rebuilt string must equal the original (rejects missing / extra parts)
if not "%O1%.%O2%.%O3%.%O4%"=="%VVAL%" goto :VAL_BAD

call :OCTET "%O1%"
call :OCTET "%O2%"
call :OCTET "%O3%"
call :OCTET "%O4%"
if defined BADIP goto :VAL_BAD
exit /b 0

:VAL_BAD
set "BADIP=1"
set "BADLABEL=%VLABEL%"
set "BADVAL=%VVAL%"
exit /b 0


rem ---------------- :SPLIT "o1" "o2" "o3" "o4" ----------------
:SPLIT
set "O1=%~1"
set "O2=%~2"
set "O3=%~3"
set "O4=%~4"
exit /b 0


rem ---------------- :OCTET "value"  (digits only, 0-255) ----------------
:OCTET
set "X=%~1"
if not defined X goto :OCTET_BAD
rem trailing "x" keeps Y defined while digits are stripped
set "Y=%X%x"
set "Y=%Y:0=%"
set "Y=%Y:1=%"
set "Y=%Y:2=%"
set "Y=%Y:3=%"
set "Y=%Y:4=%"
set "Y=%Y:5=%"
set "Y=%Y:6=%"
set "Y=%Y:7=%"
set "Y=%Y:8=%"
set "Y=%Y:9=%"
if not "%Y%"=="x" goto :OCTET_BAD
rem prefix with 1 so leading zeros are not treated as octal; 1255 = 255
set /a V=1%X%
if %V% GTR 1255 goto :OCTET_BAD
exit /b 0
:OCTET_BAD
set "BADIP=1"
exit /b 0


rem ---------------- :CHECK "state" "type" "name" ----------------
:CHECK
if defined DONE exit /b 0
if /i not "%~1"=="Connected" exit /b 0
if /i "%~2"=="Loopback" exit /b 0
if "%~3"=="" exit /b 0
call :TRY "%~3"
exit /b 0


rem ---------------- :TRY "adapter name" ----------------
:TRY
set "IFNAME=%~1"
echo.
echo [INFO] Trying adapter: %IFNAME%

netsh interface ip set address name="%IFNAME%" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1 >nul
if defined DNS1 netsh interface ip set dns name="%IFNAME%" source=static addr=%DNS1% >nul
if defined DNS2 netsh interface ip add dns name="%IFNAME%" addr=%DNS2% index=2 >nul

rem wait a few seconds (ping is used as a sleep)
ping -n 4 127.0.0.1 >nul

rem gateway reachability check only (no internet check)
call :PINGTEST %GW%
if not defined PINGOK goto :TRY_FAIL

set "DONE=1"
set "OKNAME=%IFNAME%"
echo [OK] Gateway reachable through: %IFNAME%
exit /b 0

:TRY_FAIL
echo [WARN] No response through "%IFNAME%" - reverting to DHCP
netsh interface ip set address name="%IFNAME%" source=dhcp >nul
netsh interface ip set dns name="%IFNAME%" source=dhcp >nul
exit /b 1


rem ---------------- :PINGTEST "host"  -> sets PINGOK=1 on real reply ----------------
:PINGTEST
set "PINGOK="
for /f "tokens=*" %%a in ('ping -n 2 -w 1500 %~1') do call :PINGLINE "%%a"
exit /b 0

rem a real reply line contains "TTL"; "TTL expired in transit" does not count
:PINGLINE
set "L=%~1"
if not defined L exit /b 0
set "L2=%L:TTL=%"
if "%L2%"=="%L%" exit /b 0
set "L3=%L:expired=%"
if not "%L3%"=="%L%" exit /b 0
set "PINGOK=1"
exit /b 0
