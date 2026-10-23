@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT media - get_input.bat (WinPE)
rem  Asks the operator for the IP address and the disk to erase.
rem  Based on Media\getvar.bat.
rem   - Static (ip.txt exists, start_media.bat) -> BASEIP_FILE (ip.txt)
rem       ip.txt : one value per line
rem                  line 1 = ip       e.g. 203.244.132.0
rem                  line 2 = subnet   e.g. 255.255.255.0
rem                  line 3 = gateway  e.g. 203.244.132.1
rem                  line 4 = DNS 1    e.g. 168.126.63.1  (optional)
rem                  line 5 = DNS 2    e.g. 168.126.63.2  (optional)
rem       ipr    = first three octets of ip
rem       input  : <last octet>.<disk number>   e.g. 150.0
rem       ip     = ipr.<last octet>
rem   - DHCP
rem       input  : <disk number>
rem   - the disk list is shown first (getdiskinfo.bat)
rem   - the disk of the boot media cannot be selected
rem   - "R" re-scans the disks
rem   - FORCE_DISK in config.cmd, if set and valid, is the disk to erase:
rem       Static : input = <last octet> only   e.g. 150
rem       DHCP   : no input (only the MEDIA_CONFIRM question)
rem     Answering N to the confirmation selects the disk by hand.
rem     An invalid FORCE_DISK (not a number, no such disk, boot media)
rem     shows a warning and the disk is selected by hand.
rem
rem  Usage  : call get_input.bat Static ^| DHCP
rem  Returns: NET_MODE (Static / DHCP), ipr, ip, ndisk,
rem           NET_MASK_IN, NET_GW_IN, NET_DNS1_IN, NET_DNS2_IN
rem           (static only; DNS empty = NET_DNS1 / NET_DNS2 of config.cmd)
rem  Exit   : 0 = OK
rem           1 = ip.txt is missing or invalid
rem ============================================================

call "%~dp0config.cmd"

set "DP_IN=%TEMP%\dvt_input_in.txt"
set "DP_OUT=%TEMP%\dvt_input_out.txt"
set "NET_MODE=DHCP"
if /i "%~1"=="Static" set "NET_MODE=Static"
set "ipr="
set "ip="
set "ndisk="
set "IN_MASK="
set "IN_GW="
set "IN_DNS1="
set "IN_DNS2="
set "MEDIA_DISK="
rem 1 = FORCE_DISK is used; cleared when the operator answers N
set "USE_FORCE=0"
if defined FORCE_DISK set "USE_FORCE=1"

rem ---- static IP base from ip.txt ----
if not "%NET_MODE%"=="Static" goto :media_disk
set "MSG=the file was not found."
if not exist "%BASEIP_FILE%" goto :bad_file
call :read_ipfile
if errorlevel 1 goto :bad_file

rem ---- disk of the boot media (none for a CD) ----
:media_disk
if defined MEDIA_DRV call :disk_of_volume %MEDIA_DRV%
if defined MEDIA_DRV set "MEDIA_DISK=%VOLDISK%"


rem ============================================================
rem  disk list and prompt
rem ============================================================
:show
cls
echo.
echo Collecting disk information...
call "%~dp0getdiskinfo.bat"
echo.
if "%NET_MODE%"=="Static" (
    echo  Network    : static IP  %ipr%.x   mask %IN_MASK%   gateway %IN_GW%
) else (
    echo  Network    : DHCP
)
if defined MEDIA_DISK (
    echo  Boot media : drive %MEDIA_DRV%:  disk %MEDIA_DISK%  ^(cannot be selected^)
) else if defined MEDIA_DRV (
    echo  Boot media : drive %MEDIA_DRV%:
)
set "FDISK="
if "!USE_FORCE!"=="1" call :check_force
if defined FDISK echo  Target disk: !FDISK!   ^(FORCE_DISK in config.cmd^)
echo.

:ask
set "var="
echo.
if defined FDISK if not "%NET_MODE%"=="Static" (
    rem DHCP and a fixed disk: nothing to enter
    set "ndisk=!FDISK!"
    goto :check_disk
)
if defined FDISK (
    echo  Enter the last octet of the IP address, e.g. 150
    echo  R = scan the disks again
    set /p "var=IP Address = "
) else if "%NET_MODE%"=="Static" (
    echo  Enter the last octet of the IP address and the disk number, e.g. 150.0
    echo  R = scan the disks again
    set /p "var=IP Address.Select Disk = "
) else (
    echo  Enter the number of the disk to erase.
    echo  R = scan the disks again
    set /p "var=Select Disk = "
)
if not defined var goto :ask
set "var=!var:"=!"
set "var=!var: =!"
if not defined var goto :ask
if /i "!var!"=="R" goto :show

if defined FDISK (
    call :parse_octet "!var!"
) else if "%NET_MODE%"=="Static" (
    call :parse_static
) else (
    call :parse_dhcp
)
if errorlevel 1 (
    echo [ERROR] !MSG!
    goto :ask
)

rem ---- the disk must exist and must not be the boot media ----
:check_disk
call :disk_exists !ndisk!
if not defined FOUND (
    echo [ERROR] Disk !ndisk! does not exist.
    call :drop_force
    goto :ask
)
if defined MEDIA_DISK if "!ndisk!"=="%MEDIA_DISK%" (
    echo [ERROR] Disk !ndisk! is the boot media.
    call :drop_force
    goto :ask
)

rem ---- confirmation ----
if not "%MEDIA_CONFIRM%"=="1" goto :done
echo.
if "%NET_MODE%"=="Static" (
    echo  IP address : !ip!   mask %IN_MASK%   gateway %IN_GW%
) else (
    echo  IP address : DHCP
)
echo  Disk !ndisk! will be ERASED. All data on it will be lost.
set "ans="
set /p "ans=Continue? (Y/N) = "
if /i "!ans!"=="Y" goto :done
call :drop_force
goto :ask

:done
del /f /q "%DP_IN%" "%DP_OUT%" >nul 2>&1
endlocal & set "NET_MODE=%NET_MODE%" & set "ipr=%ipr%" & set "ip=%ip%" & set "ndisk=%ndisk%" & set "NET_MASK_IN=%IN_MASK%" & set "NET_GW_IN=%IN_GW%" & set "NET_DNS1_IN=%IN_DNS1%" & set "NET_DNS2_IN=%IN_DNS2%" & exit /b 0

:bad_file
echo [ERROR] Static IP settings "%BASEIP_FILE%": !MSG!
echo         Expected one value per line:
echo           203.244.132.0      ip ^(only the first three octets are used^)
echo           255.255.255.0      subnet ^(may be omitted^)
echo           203.244.132.1      gateway ^(may be omitted^)
echo           168.126.63.1       DNS 1 ^(optional^)
echo           168.126.63.2       DNS 2 ^(optional^)
del /f /q "%DP_IN%" "%DP_OUT%" >nul 2>&1
endlocal & exit /b 1


rem ============================================================
rem  :check_force   FORCE_DISK -> FDISK (empty when it cannot be used)
rem ============================================================
:check_force
call :to_number "%FORCE_DISK%" || (
    echo  [WARN] FORCE_DISK in config.cmd is not a number: "%FORCE_DISK%"
    echo         Select the disk by hand.
    exit /b 0
)
set "FN=!NUM!"
call :disk_exists !FN!
if not defined FOUND (
    echo  [WARN] FORCE_DISK: disk !FN! does not exist. Select the disk by hand.
    exit /b 0
)
if defined MEDIA_DISK if "!FN!"=="%MEDIA_DISK%" (
    echo  [WARN] FORCE_DISK: disk !FN! is the boot media. Select the disk by hand.
    exit /b 0
)
set "FDISK=!FN!"
exit /b 0


rem ============================================================
rem  :drop_force   stop using FORCE_DISK: the operator selects the disk
rem ============================================================
:drop_force
if not defined FDISK exit /b 0
set "USE_FORCE=0"
set "FDISK="
echo [INFO] Select the disk by hand.
exit /b 0


rem ============================================================
rem  :parse_octet "<last octet>"   with FORCE_DISK -> ip, ndisk
rem ============================================================
:parse_octet
set "ndisk=!FDISK!"
set "ipd=%~1"
set "dsk="
for /f "delims=0123456789" %%z in ("!ipd!") do (
    set "MSG=Enter only the last octet of the IP address, e.g. 150. The disk is set in config.cmd."
    exit /b 1
)
goto :octet


rem ============================================================
rem  :parse_static   var = <last octet>.<disk>  -> ip, ndisk
rem  Exit 1 with MSG on invalid input.
rem ============================================================
:parse_static
set "ipd="
set "dsk="
for /f "tokens=1,2 delims=." %%a in ("!var!") do (
    set "ipd=%%a"
    set "dsk=%%b"
)
if not "!ipd!.!dsk!"=="!var!" (
    set "MSG=Enter the last octet and the disk number separated by a dot, e.g. 150.0"
    exit /b 1
)
:octet
call :to_number "!ipd!" || (
    set "MSG=The last octet must be a number: !ipd!"
    exit /b 1
)
if !NUM! LSS %OCTET_MIN% (
    set "MSG=The last octet must be between %OCTET_MIN% and %OCTET_MAX%: !ipd!"
    exit /b 1
)
if !NUM! GTR %OCTET_MAX% (
    set "MSG=The last octet must be between %OCTET_MIN% and %OCTET_MAX%: !ipd!"
    exit /b 1
)
set "ip=!ipr!.!NUM!"
if "!ip!"=="!IN_GW!" (
    set "MSG=!ip! is the gateway address."
    exit /b 1
)
if defined FDISK exit /b 0
call :to_number "!dsk!" || (
    set "MSG=The disk number must be a number: !dsk!"
    exit /b 1
)
set "ndisk=!NUM!"
exit /b 0


rem ============================================================
rem  :parse_dhcp   var = <disk>  -> ndisk
rem ============================================================
:parse_dhcp
call :to_number "!var!" || (
    set "MSG=The disk number must be a number: !var!"
    exit /b 1
)
set "ndisk=!NUM!"
exit /b 0


rem ============================================================
rem  :read_ipfile   reads ip, subnet, gateway and DNS from BASEIP_FILE
rem  One value per line, in this order. Empty lines and lines starting
rem  with # are ignored. An ip.txt of the normal DVT flow (address
rem  only) also works: subnet = NET_MASK, gateway = ipr.1
rem  Sets ipr, IN_MASK, IN_GW, IN_DNS1, IN_DNS2. Exit 1 with MSG on error.
rem ============================================================
:read_ipfile
set "VN=0"
set "V1="
set "V2="
set "V3="
set "V4="
set "V5="
for /f "usebackq eol=# tokens=1" %%a in ("%BASEIP_FILE%") do call :collect %%a
if not defined V1 (
    set "MSG=the file is empty."
    exit /b 1
)
call :check_ip "!V1!" || (
    set "MSG=ip (line 1) !V1!"
    exit /b 1
)
for /f "tokens=1-3 delims=." %%a in ("!IPN!") do set "ipr=%%a.%%b.%%c"
if not defined V2 set "V2=%NET_MASK%"
call :check_ip "!V2!" || (
    set "MSG=subnet (line 2) !V2!"
    exit /b 1
)
set "IN_MASK=!IPN!"
if not defined V3 set "V3=!ipr!.1"
call :check_ip "!V3!" || (
    set "MSG=gateway (line 3) !V3!"
    exit /b 1
)
set "IN_GW=!IPN!"
if defined V4 (
    call :check_ip "!V4!" || (
        set "MSG=DNS 1 (line 4) !V4!"
        exit /b 1
    )
    set "IN_DNS1=!IPN!"
)
if defined V5 (
    call :check_ip "!V5!" || (
        set "MSG=DNS 2 (line 5) !V5!"
        exit /b 1
    )
    set "IN_DNS2=!IPN!"
)
exit /b 0

:collect
if "%~1"=="" exit /b 0
if !VN! GEQ 5 exit /b 0
set /a VN+=1
set "V!VN!=%~1"
shift
goto :collect


rem ============================================================
rem  :check_ip "<a.b.c.d>"   exit 0 = valid; IPN = normalized address
rem ============================================================
:check_ip
set "IPN="
set "CI=%~1"
if not defined CI exit /b 1
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
if not "!O1!.!O2!.!O3!.!O4!"=="%CI%" exit /b 1
for %%o in (1 2 3 4) do (
    call :to_number "!O%%o!" || exit /b 1
    if !NUM! GTR 255 exit /b 1
    set "O%%o=!NUM!"
)
set "IPN=!O1!.!O2!.!O3!.!O4!"
exit /b 0


rem ============================================================
rem  :to_number "<value>"   1-3 digits -> NUM (leading zeros removed)
rem  Exit 1 = not a number or longer than 3 digits.
rem ============================================================
:to_number
set "NUM="
set "TN=%~1"
if not defined TN exit /b 1
for /f "delims=0123456789" %%z in ("!TN!") do exit /b 1
if not "!TN:~3!"=="" exit /b 1
rem pad to 3 digits and prefix with 1, so leading zeros are not read as octal
set "TN=000!TN!"
set /a NUM=1!TN:~-3!-1000
exit /b 0


rem ============================================================
rem  :disk_exists <number>   FOUND=1 when "list disk" shows the disk
rem  with a size (same test as getdiskinfo.bat: 2nd word = number,
rem  5th word = KB/MB/GB/TB). A card reader without media has no size.
rem ============================================================
:disk_exists
set "FOUND="
> "%DP_IN%" echo list disk
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
for /f "usebackq tokens=2,5" %%a in ("%DP_OUT%") do (
    if "%%a"=="%~1" for %%u in (KB MB GB TB) do if /i "%%b"=="%%u" set "FOUND=1"
)
exit /b 0


rem ============================================================
rem  :disk_of_volume <letter>
rem  Sets VOLDISK to the disk number of the volume (empty on error,
rem  and for a CD). "detail volume" prints "* Disk 1   Online ...".
rem ============================================================
:disk_of_volume
set "VOLDISK="
> "%DP_IN%" (
    echo select volume %~1
    echo detail volume
)
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
for /f "usebackq tokens=1-3" %%a in ("%DP_OUT%") do (
    if /i "%%b"=="Disk" if not defined VOLDISK call :to_number "%%c" && set "VOLDISK=!NUM!"
)
exit /b 0
