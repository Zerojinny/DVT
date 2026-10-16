@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT TEST - start_test.bat (WinPE, called by startnet.cmd)
rem  Test flow of the test image. It runs the same checks as
rem  start_dvt.bat, but NEVER erases or writes any disk:
rem   1) check the required files, initialize WinPE
rem   2) firmware type and target disk detection (report only)
rem   3) network (static IP from ip.txt, otherwise DHCP), gateway
rem   4) seeder check (downloads dvt_check.txt only, into X:)
rem   5) writes <ip>.txt and uploads it to the FTP server
rem      (test_config.cmd), then reboots
rem
rem  On failure the screen turns red. TEST_FAIL_REBOOT decides
rem  whether it reboots by itself (default) or waits for a key, and
rem  TEST_UPLOAD_FAIL whether a <ip>_FAIL.txt report is uploaded.
rem ============================================================

cd /d "%~dp0"
call "%~dp0config.cmd"
call "%~dp0test_config.cmd"
set "ERRMSG="
set "NET_IP="
set "NET_GW="
set "NET_ADAPTER="
set "IP_MODE=DHCP"
set "LINK_PROFILE="
set "FIRMWARE="
set "TARGET_DISK="
set "GATEWAY_RESULT=not checked"
set "SEEDER_RESULT=not checked"
set "UPLOAD_TRIED=0"
set "TEST_START=%DATE% %TIME:~0,8%"
title DVT TEST
color %COLOR_WORK%

echo ==============================================
echo  DVT TEST - network and seeder check
echo  This test image does not touch any disk.
echo ==============================================

rem ---- [1] required files ----
if not exist "%TORRENT%" (
    set "ERRMSG=Torrent file not found: %TORRENT%"
    goto :failed
)
if not exist "%ARIA2%" (
    set "ERRMSG=aria2c.exe not found."
    goto :failed
)
call "%~dp0upload_ftp.bat" /check
if errorlevel 3 (
    set "ERRMSG=FTP_HOST or FTP_USER is empty in test_config.cmd."
    goto :failed
)
if errorlevel 1 (
    set "ERRMSG=No FTP client found: curl.exe or ftp.exe."
    goto :failed
)

echo [INFO] Initializing WinPE...
wpeinit
wpeutil DisableFirewall >nul 2>&1
rem High Performance power plan
powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
rem Extra minimized console for troubleshooting
start "DVT Console" /min cmd.exe

rem ---- [2] firmware type and target disk (report only) ----
call "%~dp0get_firmware.bat"
call "%~dp0get_disk.bat"
if errorlevel 1 (
    set "TARGET_DISK=NOT FOUND"
    echo [WARN] The target disk could not be determined. The test continues.
)

rem ---- [3] network: static IP from ip.txt, otherwise DHCP ----
if exist "%IP_FILE%" (
    set "IP_MODE=Static"
    call "%~dp0set_ip.bat" "%IP_FILE%"
) else (
    call "%~dp0get_ip.bat"
)
if errorlevel 1 (
    set "ERRMSG=Network configuration failed."
    goto :failed
)
title DVT TEST - IP %NET_IP%

call "%~dp0check_gateway.bat" %NET_GW%
if errorlevel 1 (
    set "GATEWAY_RESULT=FAILED"
    set "ERRMSG=The gateway is unreachable."
    goto :failed
)
set "GATEWAY_RESULT=OK"

rem ---- [4] seeder ----
rem link speed measured by make_boot.bat (1G / 100) -> seeder check attempts
if exist "%LINK_FILE%" set /p LINK_PROFILE=<"%LINK_FILE%"
if defined LINK_PROFILE set "LINK_PROFILE=%LINK_PROFILE: =%"
call "%~dp0check_seeder.bat" "%TORRENT%"
if errorlevel 4 (
    set "SEEDER_RESULT=FAILED (empty %CHECK_FILE%)"
    set "ERRMSG=The seeder check file in the torrent is empty (0 bytes). Create the torrent again with a non-empty %CHECK_FILE%."
    goto :failed
)
if errorlevel 1 (
    set "SEEDER_RESULT=FAILED"
    set "ERRMSG=No seeder is reachable."
    goto :failed
)
set "SEEDER_RESULT=OK"

rem ---- [5] report and upload ----
set "REPORT=%TEMP%\%NET_IP%.txt"
call :write_report OK
echo [INFO] Uploading %NET_IP%.txt to %FTP_HOST%...
set "UPLOAD_TRIED=1"
call "%~dp0upload_ftp.bat" "%REPORT%" "%NET_IP%.txt"
if errorlevel 1 (
    set "ERRMSG=FTP upload of %NET_IP%.txt failed."
    goto :failed
)

call :show_pass
call "%~dp0wait.bat" %TEST_DONE_REBOOT_SEC%
wpeutil reboot
exit /b 0


:failed
color %COLOR_FAIL%
title DVT TEST - FAILED
echo.
echo [ERROR] !ERRMSG!
if "%TEST_UPLOAD_FAIL%"=="1" if defined NET_IP if "%UPLOAD_TRIED%"=="0" call :upload_fail_report
echo.
echo  ======================================================================
echo    [TEST FAILED] !ERRMSG!
if defined NET_IP echo    IP address : %NET_IP%
echo  ======================================================================
rem only TEST_FAIL_REBOOT=0 waits for a key; anything else reboots
if "%TEST_FAIL_REBOOT%"=="0" (
    echo    Press any key to reboot.
    pause >nul
) else (
    echo [INFO] Rebooting in %FAIL_REBOOT_SEC% seconds...
    call "%~dp0wait.bat" %FAIL_REBOOT_SEC%
)
wpeutil reboot
exit /b 1


rem ============================================================
rem  :upload_fail_report   uploads <ip>_FAIL.txt (TEST_UPLOAD_FAIL=1)
rem ============================================================
:upload_fail_report
set "FAILNAME=%NET_IP%%TEST_FAIL_SUFFIX%.txt"
set "REPORT=%TEMP%\%FAILNAME%"
call :write_report FAILED
echo [INFO] Uploading %FAILNAME% to %FTP_HOST%...
call "%~dp0upload_ftp.bat" "%REPORT%" "%FAILNAME%"
if errorlevel 1 echo [WARN] The failure report could not be uploaded.
exit /b 0


rem ============================================================
rem  :write_report <result>   writes REPORT
rem  Delayed expansion is used inside the block, so values with
rem  parentheses (adapter names, messages) cannot break it.
rem ============================================================
:write_report
call :read_bios
set "RPT_ADAPTER=%NET_ADAPTER%"
if not defined RPT_ADAPTER set "RPT_ADAPTER=n/a"
set "RPT_LINK=%LINK_PROFILE%"
if not defined RPT_LINK set "RPT_LINK=unknown"
set "RPT_DISK=%TARGET_DISK%"
if not defined RPT_DISK set "RPT_DISK=unknown"
> "%REPORT%" (
    echo DVT test report
    echo ==============================================
    echo Result       : %~1
    if defined ERRMSG echo Error        : !ERRMSG!
    echo IP address   : !NET_IP!
    echo IP mode      : !IP_MODE!
    echo Gateway      : !NET_GW!  [!GATEWAY_RESULT!]
    echo Adapter      : !RPT_ADAPTER!
    echo Link profile : !RPT_LINK!
    echo Seeder check : !SEEDER_RESULT!
    echo Firmware     : !FIRMWARE!
    echo Target disk  : !RPT_DISK!
    echo Manufacturer : !BIOS_MAKER!
    echo Model        : !BIOS_MODEL!
    echo BIOS version : !BIOS_VER!
    echo Started      : !TEST_START!
    echo Finished     : !DATE! !TIME:~0,8!
)
set "DP_IN=%TEMP%\dvt_test_dp.txt"
>> "%REPORT%" echo.
>> "%REPORT%" echo ---- diskpart: list disk ----
> "%DP_IN%" echo list disk
diskpart /s "%DP_IN%" >> "%REPORT%" 2>&1
rem details of the detected target disk (only when it is a number)
set "DISK_OK=1"
if not defined TARGET_DISK set "DISK_OK=0"
if defined TARGET_DISK for /f "delims=0123456789" %%z in ("%TARGET_DISK%") do set "DISK_OK=0"
>> "%REPORT%" echo.
if "%DISK_OK%"=="1" (
    >> "%REPORT%" echo ---- diskpart: detail disk %TARGET_DISK% ^(target disk^) ----
    > "%DP_IN%" (
        echo select disk %TARGET_DISK%
        echo detail disk
    )
    diskpart /s "%DP_IN%" >> "%REPORT%" 2>&1
) else (
    >> "%REPORT%" echo ---- diskpart: detail disk ----
    >> "%REPORT%" echo The target disk was not determined.
)
del /f /q "%DP_IN%" >nul 2>&1
>> "%REPORT%" echo.
>> "%REPORT%" echo ---- ipconfig /all ----
ipconfig /all >> "%REPORT%" 2>&1
exit /b 0


rem ============================================================
rem  :read_bios   BIOS_MAKER, BIOS_MODEL, BIOS_VER from the registry
rem  (wmic is not available in WinPE)
rem ============================================================
:read_bios
set "BIOS_KEY=HKLM\HARDWARE\DESCRIPTION\System\BIOS"
set "BIOS_MAKER="
set "BIOS_MODEL="
set "BIOS_VER="
for /f "tokens=2,*" %%a in ('reg query "%BIOS_KEY%" /v SystemManufacturer 2^>nul') do set "BIOS_MAKER=%%b"
for /f "tokens=2,*" %%a in ('reg query "%BIOS_KEY%" /v SystemProductName 2^>nul') do set "BIOS_MODEL=%%b"
for /f "tokens=2,*" %%a in ('reg query "%BIOS_KEY%" /v BIOSVersion 2^>nul') do set "BIOS_VER=%%b"
exit /b 0


rem ============================================================
rem  :show_pass   large green banner
rem ============================================================
:show_pass
color %COLOR_OK%
title DVT TEST - PASSED - IP %NET_IP%
cls
echo.
echo.
echo  ======================================================================
echo.
echo        #####      ###      #####    #####
echo        ##  ##    ## ##    ##       ##
echo        #####    ##   ##    ####     ####
echo        ##       #######       ##       ##
echo        ##       ##   ##   #####    #####
echo.
echo  ======================================================================
echo.
echo    IP address : %NET_IP%
echo    Gateway    : %NET_GW%
echo    Seeder     : OK
echo    Uploaded   : %NET_IP%.txt to %FTP_HOST%
echo.
echo    Started    : %TEST_START%
echo    Finished   : %DATE% %TIME:~0,8%
echo.
echo  ======================================================================
echo.
echo    Rebooting in %TEST_DONE_REBOOT_SEC% seconds...
exit /b 0
