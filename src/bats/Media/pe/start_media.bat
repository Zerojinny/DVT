@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT media - start_media.bat (WinPE, called by startnet.cmd)
rem  Main WinPE flow for a USB / CD boot (no make_boot.bat on the
rem  client PC, so the operator enters the IP address and the disk):
rem   1) check the files copied from <media>\config (DVT_backup.torrent,
rem      aria2.conf.1G, aria2.conf.100, ip.txt), initialize WinPE
rem   2) network order (DHCP_ENABLE in config.cmd):
rem      0 / empty : ip.txt exists -> static IP first, otherwise DHCP
rem      1         : DHCP first; when DHCP or its gateway test fails and
rem                  ip.txt exists -> static IP
rem      no DHCP address and no ip.txt = error
rem   3) show the disks, ask for the last IP octet and the disk number
rem      (static) or the disk number only (DHCP)
rem   4) static: apply the IP and check the gateway. Static first: on
rem      failure switch to DHCP and check the gateway again; when DHCP
rem      works, continue with DHCP (same disk), after a Y/N question
rem      when DHCP_FALLBACK_CONFIRM=1.
rem      DHCP first: DHCP has already failed, so this is an error.
rem   5) run link.exe: aria2.conf for the link speed, then check the
rem      seeder (2 attempts at 1 Gbps or faster, 5 at 100 Mbps or slower)
rem      and the disk space (check_space.bat)
rem      Nothing is erased before steps 2-5 pass.
rem   6) erase the selected disk and create the partitions
rem   7) choose the download drive and download DVT_backup.torrent
rem      -> when the download is complete, aria2c runs
rem         start_restore.bat, and restore.bat applies the image with
rem         wimlib-imagex, moves the extra files and reboots
rem
rem  Top-level script: only this script and restore.bat reboot.
rem  Every failure waits for a key, because an operator is present.
rem  Needs: MEDIA_DRV from startnet.cmd
rem ============================================================

cd /d "%~dp0"
call "%~dp0config.cmd"
set "ERRMSG="
set "ERASED=0"
title DVT %DVT_VERSION% Media
color %COLOR_WORK%
echo ==============================================
echo  DVT %DVT_VERSION% - USB / CD media
echo ==============================================

rem ---- [1] boot media and required files ----
if not defined MEDIA_DRV (
    set "ERRMSG=No boot media with a \config folder was found."
    goto :failed
)
if defined DVT_CONFIG_ERR (
    set "ERRMSG=Failed to copy %MEDIA_DRV%:\config to %PE_DIR%."
    goto :failed
)
if not exist "%TORRENT%" (
    set "ERRMSG=Torrent file not found: %TORRENT%  (put DVT_backup.torrent in %MEDIA_DRV%:\config)"
    goto :failed
)
if not exist "%ARIA2%" (
    set "ERRMSG=aria2c.exe not found."
    goto :failed
)
if not exist "%WIMLIB%" (
    set "ERRMSG=wimlib-imagex.exe not found."
    goto :failed
)
rem WIM_INDEX is checked here too, so a typo stops before the disk is erased
if not defined WIM_INDEX set "WIM_INDEX=1"
set "IDX_NUM="
set /a "IDX_NUM=WIM_INDEX" >nul 2>&1
if not "%IDX_NUM%"=="%WIM_INDEX%" (
    set "ERRMSG=Invalid WIM_INDEX in config.cmd: %WIM_INDEX%  Use a whole number of 1 or more."
    goto :failed
)
if %IDX_NUM% LSS 1 (
    set "ERRMSG=Invalid WIM_INDEX in config.cmd: %WIM_INDEX%  Use a whole number of 1 or more."
    goto :failed
)
if not exist "%PE_DIR%\aria2.conf.1G" if not exist "%PE_DIR%\aria2.conf.100" (
    set "ERRMSG=No aria2 settings found. Put aria2.conf.1G and aria2.conf.100 in %MEDIA_DRV%:\config"
    goto :failed
)

echo [INFO] Initializing WinPE...
rem wpeinit normally waits for a DHCP lease before it returns, which
rem takes a long time on a static IP network (no DHCP server answers).
rem wpe_nonet.xml makes wpeinit skip the network, then the network is
rem started without that wait. get_ip.bat (DHCP) and set_ip.bat (static)
rem wait for the address themselves.
if exist "%~dp0wpe_nonet.xml" (
    wpeinit -unattend="%~dp0wpe_nonet.xml"
    wpeutil InitializeNetwork /NoWait
) else (
    echo [WARN] wpe_nonet.xml not found. wpeinit waits for DHCP.
    wpeinit
)
wpeutil DisableFirewall >nul 2>&1
rem High Performance power plan
powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
rem Extra minimized console for troubleshooting
start "DVT Console" /min cmd.exe

call "%~dp0get_firmware.bat"

rem ---- [2] network type (DHCP_ENABLE: 1 = DHCP first, else static first) ----
set "NET_MODE=DHCP"
rem DHCP_TRIED=1: DHCP was tried first and failed (no DHCP fallback later)
set "DHCP_TRIED=0"
rem DHCP_GW_OK=1: the DHCP gateway was already tested
set "DHCP_GW_OK=0"
if "%DHCP_ENABLE%"=="1" goto :dhcp_first

rem -- static IP first --
if exist "%BASEIP_FILE%" set "NET_MODE=Static"
if "%NET_MODE%"=="Static" (
    echo [INFO] ip.txt found. Static IP first, DHCP if the gateway test fails.
    goto :input
)
echo [INFO] ip.txt not found. Waiting for a DHCP address...
call "%~dp0get_ip.bat"
if errorlevel 1 goto :no_network
goto :input

rem -- DHCP first --
:dhcp_first
if not exist "%BASEIP_FILE%" (
    echo [INFO] DHCP first. ip.txt not found, so there is no static IP fallback.
    call "%~dp0get_ip.bat"
    if errorlevel 1 goto :no_network
    goto :input
)
echo [INFO] DHCP first, static IP from ip.txt if DHCP fails.
call "%~dp0get_ip.bat" %DHCP_FIRST_TRIES%
if errorlevel 1 goto :dhcp_first_failed
call "%~dp0check_gateway.bat" %NET_GW%
if errorlevel 1 goto :dhcp_first_failed
set "DHCP_GW_OK=1"
goto :input

:dhcp_first_failed
echo [WARN] DHCP failed. Using the static IP from ip.txt.
set "DHCP_TRIED=1"
set "NET_MODE=Static"
goto :input

:no_network
set "ERRMSG=No DHCP address was received and ip.txt for a static IP was not found in %MEDIA_DRV%:\config."
goto :failed

:input

rem ---- [3] IP address and target disk ----
call "%~dp0get_input.bat" %NET_MODE%
if errorlevel 1 (
    set "ERRMSG=The IP settings in %MEDIA_DRV%:\config\ip.txt are invalid."
    goto :failed
)
set "TARGET_DISK=%ndisk%"
cls
if /i "%NET_MODE%"=="Static" (
    title DVT %DVT_VERSION% - %ip% , disk %ndisk%
    echo [INFO] IP address: %ip%   Disk: %ndisk%
) else (
    title DVT %DVT_VERSION% - DHCP , disk %ndisk%
    echo [INFO] IP address: DHCP   Disk: %ndisk%
)

rem ---- [4] network ----
if exist "%IP_FILE%" del /f /q "%IP_FILE%" >nul 2>&1
if /i not "%NET_MODE%"=="Static" goto :dhcp_gateway

rem -- static IP; set_ip.bat already tests the gateway on each adapter --
set "NET_ADAPTER="
call "%~dp0set_ip.bat" %ip% %NET_MASK_IN% %NET_GW_IN% %NET_DNS1_IN% %NET_DNS2_IN%
if errorlevel 1 goto :static_failed
call "%~dp0check_gateway.bat" %NET_GW%
if errorlevel 1 goto :static_failed
rem a new ip.txt for the restored Windows, same format as config\ip.txt:
rem line 1 = ip, line 2 = subnet, line 3 = gateway, lines 4-5 = the DNS
rem servers used (restore.bat moves it to T:\temp\ip.txt)
> "%IP_FILE%" (
    echo %NET_IP%
    echo %NET_MASK_IN%
    echo %NET_GW%
    if defined NET_DNS1_USED echo %NET_DNS1_USED%
    if defined NET_DNS2_USED echo %NET_DNS2_USED%
)
if not exist "%IP_FILE%" (
    set "ERRMSG=Could not write %IP_FILE%"
    goto :failed
)
goto :net_ok

rem -- static IP failed: switch to DHCP and test the gateway again --
:static_failed
echo.
if "%DHCP_TRIED%"=="1" (
    set "ERRMSG=DHCP failed, and the static IP %ip% failed the gateway test too."
    goto :failed
)
echo [WARN] The gateway test with the static IP %ip% failed. Trying DHCP...
call :to_dhcp
call "%~dp0get_ip.bat"
if errorlevel 1 (
    set "ERRMSG=The static IP %ip% failed the gateway test, and no DHCP address was received."
    goto :failed
)
call "%~dp0check_gateway.bat" %NET_GW%
if errorlevel 1 (
    set "ERRMSG=The static IP %ip% failed the gateway test, and the DHCP gateway %NET_GW% is unreachable too."
    goto :failed
)
color %COLOR_FAIL%
echo.
echo ==============================================================
echo  [WARN] The static IP test failed, but DHCP succeeded.
echo    Static IP : %ip%   gateway %NET_GW_IN%   - FAILED
echo    DHCP IP   : %NET_IP%   gateway %NET_GW%   - OK
echo    Disk      : %TARGET_DISK%   ^(selected before, will be ERASED^)
echo ==============================================================
if not "%DHCP_FALLBACK_CONFIRM%"=="1" (
    echo [INFO] Continuing with DHCP in 5 seconds...
    call "%~dp0wait.bat" 5
    color %COLOR_WORK%
    goto :use_dhcp
)
set "ans="
set /p "ans=Continue with DHCP? (Y/N) = "
color %COLOR_WORK%
if /i not "!ans!"=="Y" (
    set "ERRMSG=Cancelled: the static IP %ip% did not work."
    goto :failed
)
:use_dhcp
set "NET_MODE=DHCP"
rem the restored Windows uses DHCP, so no ip.txt is written
if exist "%IP_FILE%" del /f /q "%IP_FILE%" >nul 2>&1
echo [INFO] Continuing with DHCP: %NET_IP%
goto :net_ok

rem -- DHCP --
:dhcp_gateway
if "%DHCP_GW_OK%"=="1" goto :net_ok
call "%~dp0check_gateway.bat" %NET_GW%
if errorlevel 1 (
    set "ERRMSG=The gateway is unreachable."
    goto :failed
)

:net_ok
title DVT %DVT_VERSION% - %NET_IP% , disk %TARGET_DISK%

rem ---- [5] aria2 settings for the link speed (also sets LINK_PROFILE,
rem          which decides the number of seeder check attempts) ----
call :select_conf
if not exist "%ARIA2_CONF%" (
    set "ERRMSG=aria2 config not found: %ARIA2_CONF%"
    goto :failed
)

call "%~dp0check_seeder.bat" "%TORRENT%"
if errorlevel 4 (
    set "ERRMSG=The seeder check file in the torrent is empty (0 bytes). Create the torrent again with a non-empty %CHECK_FILE%."
    goto :failed
)
if errorlevel 1 (
    set "ERRMSG=No seeder is reachable."
    goto :failed
)

rem ---- [5b] disk space (SPACE_CHECK in config.cmd) ----
call "%~dp0check_space.bat" "%TORRENT%"
if errorlevel 1 (
    set "ERRMSG=Disk %TARGET_DISK% is too small for this image."
    goto :failed
)

rem ---- [6] erase the target disk ----
set "ERASED=1"
call "%~dp0make_disk.bat"
if errorlevel 1 (
    set "ERRMSG=Disk preparation failed."
    goto :failed
)

rem ---- [7] download ----
call "%~dp0get_target.bat" "%TORRENT%"
if exist "%DL_DRIVE%:\%DL_NAME%\" rd /s /q "%DL_DRIVE%:\%DL_NAME%"
if exist "%DL_DRIVE%:\%DL_NAME%.aria2" del /f /q "%DL_DRIVE%:\%DL_NAME%.aria2"
if exist "%RESTORE_FLAG%" del /f /q "%RESTORE_FLAG%"

cls
echo [INFO] Downloading to %DL_DRIVE%:\ ...
"%ARIA2%" -T "%TORRENT%" --conf-path="%ARIA2_CONF%" --dir=%DL_DRIVE%:\
set "RC=%errorlevel%"

rem restore.bat stops aria2c when it is done, so aria2c may end with an
rem error code even after a complete download. The flag decides.
if exist "%RESTORE_FLAG%" (
    echo [INFO] Download complete. The restore continues in the "DVT Restore" window.
    exit /b 0
)
set "ERRMSG=Download failed. aria2c exit code: %RC%"
goto :failed


:failed
color %COLOR_FAIL%
echo.
echo [ERROR] !ERRMSG!
if "%ERASED%"=="1" (
    echo [ERROR] The disk has already been erased.
    echo         Fix the problem, then press any key to reboot.
) else (
    echo [INFO] The disk was not changed. Press any key to reboot.
)
pause >nul
wpeutil reboot
exit /b 1


rem ============================================================
rem  :to_dhcp
rem  Switches every connected adapter back to DHCP (set_ip.bat already
rem  did so for the adapters that failed; this also covers the adapter
rem  it kept when the later gateway check failed).
rem ============================================================
:to_dhcp
for /f "tokens=1,2,3*" %%a in ('netsh interface show interface') do (
    if /i "%%b"=="Connected" if /i not "%%c"=="Loopback" if not "%%d"=="" (
        netsh interface ip set address name="%%d" source=dhcp >nul 2>&1
        netsh interface ip set dns name="%%d" source=dhcp >nul 2>&1
    )
)
rem give DHCP a moment to start
call "%~dp0wait.bat" 3
exit /b 0


rem ============================================================
rem  :select_conf
rem  Runs link.exe (from bats\Media\pe). It measures the link
rem  speed of the adapter that routes to the network and renames
rem  aria2.conf.1G or aria2.conf.100 to aria2.conf.
rem  When link.exe is missing or fails, LINK_FALLBACK is used.
rem  Sets LINK_PROFILE (1G / 100): the template that link.exe renamed
rem  no longer exists.
rem ============================================================
:select_conf
set "LINK_RC="
set "LINK_PROFILE="
if exist "%LINK_EXE%" (
    echo [INFO] Selecting the aria2 settings for the link speed...
    "%LINK_EXE%"
    set "LINK_RC=!errorlevel!"
) else (
    echo [WARN] link.exe not found: "%LINK_EXE%"
)
if "%LINK_RC%"=="0" if exist "%ARIA2_CONF%" (
    if not exist "%PE_DIR%\aria2.conf.1G" (
        set "LINK_PROFILE=1G"
    ) else if not exist "%PE_DIR%\aria2.conf.100" (
        set "LINK_PROFILE=100"
    )
    goto :conf_done
)
if defined LINK_RC echo [WARN] link.exe failed with exit code %LINK_RC%. Log: "%PE_DIR%\aria2_select.log"
if exist "%PE_DIR%\aria2.conf.%LINK_FALLBACK%" (
    echo [WARN] Using aria2.conf.%LINK_FALLBACK%.
    copy /y "%PE_DIR%\aria2.conf.%LINK_FALLBACK%" "%ARIA2_CONF%" >nul
    set "LINK_PROFILE=%LINK_FALLBACK%"
) else if exist "%ARIA2_CONF%" (
    echo [WARN] Using the existing aria2.conf.
)
:conf_done
rem the first line of the template names the profile
set "CONF_TITLE="
if exist "%ARIA2_CONF%" set /p CONF_TITLE=<"%ARIA2_CONF%"
if defined CONF_TITLE echo [INFO] !CONF_TITLE!
exit /b 0
