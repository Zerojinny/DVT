@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - start_dvt.bat (WinPE, called by startnet.cmd)
rem  Main WinPE flow:
rem   1) check the required files, initialize WinPE
rem   2) find the target disk, set up the network, check the gateway,
rem      the seeder and the disk space  (nothing is erased before these
rem      pass)
rem   3) erase the target disk and create the partitions
rem   4) download DVT_backup.torrent with aria2c
rem      -> when the download is complete, aria2c runs
rem         start_restore.bat, and restore.bat finishes the job in its
rem         own window while aria2c keeps seeding
rem
rem  Top-level script: only this script and restore.bat reboot.
rem  On failure BEFORE the disk is erased the PC reboots (back into
rem  Windows, because the WinPE boot entry was one-time only).
rem  On failure AFTER the disk is erased it waits for a key.
rem ============================================================

cd /d "%~dp0"
call "%~dp0config.cmd"
set "ERRMSG="
set "ERASED=0"
title DVT %DVT_VERSION%
color %COLOR_WORK%
echo ==============================================
echo  DVT %DVT_VERSION% - client local boot
echo ==============================================

rem ---- [1] required files ----
if not exist "%TORRENT%" (
    set "ERRMSG=Torrent file not found: %TORRENT%"
    goto :failed
)
if not exist "%ARIA2_CONF%" (
    set "ERRMSG=aria2 config not found: %ARIA2_CONF%"
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

rem ---- [2] firmware type and target disk ----
call "%~dp0get_firmware.bat"
call "%~dp0get_disk.bat"
if errorlevel 1 (
    set "ERRMSG=The target disk could not be determined."
    goto :failed
)

rem ---- [3] network: static IP from ip.txt, otherwise DHCP ----
if exist "%IP_FILE%" (
    call "%~dp0set_ip.bat" "%IP_FILE%"
) else (
    call "%~dp0get_ip.bat"
)
if errorlevel 1 (
    set "ERRMSG=Network configuration failed."
    goto :failed
)
title DVT %DVT_VERSION% - IP %NET_IP%

call "%~dp0check_gateway.bat" %NET_GW%
if errorlevel 1 (
    set "ERRMSG=The gateway is unreachable."
    goto :failed
)

rem link speed measured by make_boot.bat (1G / 100) -> seeder check attempts
set "LINK_PROFILE="
if exist "%LINK_FILE%" set /p LINK_PROFILE=<"%LINK_FILE%"
if defined LINK_PROFILE set "LINK_PROFILE=%LINK_PROFILE: =%"
call "%~dp0check_seeder.bat" "%TORRENT%"
if errorlevel 4 (
    set "ERRMSG=The seeder check file in the torrent is empty (0 bytes). Create the torrent again with a non-empty %CHECK_FILE%."
    goto :failed
)
if errorlevel 1 (
    set "ERRMSG=No seeder is reachable."
    goto :failed
)

rem ---- [3b] disk space (SPACE_CHECK in config.cmd) ----
call "%~dp0check_space.bat" "%TORRENT%"
if errorlevel 1 (
    set "ERRMSG=Disk %TARGET_DISK% is too small for this image."
    goto :failed
)

rem ---- [4] erase the target disk ----
set "ERASED=1"
call "%~dp0make_disk.bat"
if errorlevel 1 (
    set "ERRMSG=Disk preparation failed."
    goto :failed
)

rem ---- [5] download ----
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
    pause >nul
) else (
    echo [INFO] Rebooting in %FAIL_REBOOT_SEC% seconds...
    call "%~dp0wait.bat" %FAIL_REBOOT_SEC%
)
wpeutil reboot
exit /b 1
