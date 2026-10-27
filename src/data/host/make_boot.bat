@echo off
rem ============================================================
rem  DVT - make_boot.bat (Windows, run on the client PC)
rem  Prepares this PC for a one-time WinPE restore boot:
rem   1) reads the IP address (and static DNS), the link speed, the
rem      network drivers and the disk ID of the Windows disk
rem   2) mounts boot.wim and adds: network drivers, ip.txt (static IP
rem      only), DVT_backup.torrent, aria2.conf and link_profile.txt
rem      for the link speed, target_disk.txt (disk ID)
rem   3) suspends BitLocker for one restart (suspend_bitlocker.bat)
rem   4) adds a one-time boot entry for boot.wim (set_bcd.bat)
rem   5) shows the IP address in large digits and restarts the PC
rem  Settings: config.cmd
rem
rem  Exit: 0 = OK (the PC restarts)
rem        1 = failed
rem       10 = elevation failed
rem ============================================================

rem ---- relaunch in 64-bit cmd when started from a 32-bit process ----
if not defined PROCESSOR_ARCHITEW6432 goto :arch_ok
if not exist "%SystemRoot%\Sysnative\cmd.exe" goto :arch_ok
"%SystemRoot%\Sysnative\cmd.exe" /c ""%~f0" %*"
exit /b
:arch_ok

rem ---- administrator check ----
reg.exe query "HKU\S-1-5-20" >nul 2>&1
if not errorlevel 1 goto :admin_ok
echo [INFO] Administrator rights are required. Requesting elevation...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to elevate to administrator.
    pause
    exit /b 10
)
exit /b 0
:admin_ok

setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
call "%~dp0config.cmd"
rem tells the helper scripts not to pause or relaunch themselves
set "DVT_PARENT=1"
set "MOUNTED=0"
set "ERRMSG="
set "HOST_IP="
set "HOST_DISK_ID="
set "BITLOCKER_STATE="

echo ==============================================
echo  DVT %DVT_VERSION% - prepare the WinPE restore boot
echo ==============================================

rem ---- [1] required files ----
for %%F in (get_host_ip.bat get_link_speed.bat get_disk_id.bat export_net_drivers.bat prepare_mount_dir.bat suspend_bitlocker.bat set_bcd.bat show_ip.bat) do (
    if not exist "%HOST_DIR%\%%F" (
        set "ERRMSG=Missing script: %HOST_DIR%\%%F"
        goto :failed
    )
)
if not exist "%BOOT_WIM%" (
    set "ERRMSG=WIM file not found: %BOOT_WIM%"
    goto :failed
)
if not exist "%TORRENT%" (
    set "ERRMSG=Torrent file not found: %TORRENT%"
    goto :failed
)
if not exist "%DISM%" (
    set "ERRMSG=DISM not found: %DISM%"
    goto :failed
)

rem ---- [2] IP address (ip.txt is kept only for a static address) ----
call "%HOST_DIR%\get_host_ip.bat"
if errorlevel 1 (
    set "ERRMSG=Could not determine the IP address of this PC."
    goto :failed
)

rem ---- [3] link speed of the same adapter ----
call "%HOST_DIR%\get_link_speed.bat" %HOST_IP%
title DVT - %LINK_SPEED%

rem ---- [3b] disk ID of the Windows disk (WinPE erases this disk) ----
call "%HOST_DIR%\get_disk_id.bat" %SystemDrive%
if errorlevel 1 (
    echo [WARN] No disk ID. WinPE finds the disk only with AUTO_DISK_FALLBACK=1
    echo        ^(the only unformatted volume or the only disk^) or FORCE_DISK.
)

rem ---- [4] network drivers ----
call "%HOST_DIR%\export_net_drivers.bat"
set "RC=%errorlevel%"
set "INJECT=0"
if "%RC%"=="0" set "INJECT=1"
if "%RC%"=="2" echo [WARN] No driver will be added. WinPE built-in drivers will be used.
if "%RC%"=="3" echo [INFO] No driver will be added. WinPE built-in drivers will be used.
if not "%RC%"=="0" if not "%RC%"=="2" if not "%RC%"=="3" (
    set "ERRMSG=Network driver export failed. Exit code: %RC%"
    goto :failed
)

rem ---- [5] mount boot.wim ----
call "%HOST_DIR%\prepare_mount_dir.bat" "%BOOT_MOUNT_DIR%"
if errorlevel 1 (
    set "ERRMSG=The mount folder is not usable: %BOOT_MOUNT_DIR%"
    goto :failed
)
attrib -r "%BOOT_WIM%" >nul 2>&1
echo [INFO] Mounting "%BOOT_WIM%"...
"%DISM%" /Mount-Image /ImageFile:"%BOOT_WIM%" /Index:1 /MountDir:"%BOOT_MOUNT_DIR%"
if errorlevel 1 (
    set "ERRMSG=Failed to mount the WIM image."
    goto :failed
)
rem from here on, a failure must discard the mounted image
set "MOUNTED=1"
set "RESTORE_DIR=%BOOT_MOUNT_DIR%\restore"
if not exist "%RESTORE_DIR%\" (
    set "ERRMSG=The image has no restore folder. Rebuild it with 01_make_pe.bat."
    goto :failed
)

rem ---- [6] network drivers ----
if "%INJECT%"=="1" (
    echo [INFO] Adding network drivers...
    "%DISM%" /Image:"%BOOT_MOUNT_DIR%" /Add-Driver /Driver:"%NETDRV_DIR%" /Recurse
    if errorlevel 1 (
        set "ERRMSG=Failed to add the network drivers."
        goto :failed
    )
)

rem ---- [7] ip.txt: copy for a static IP, remove an old one otherwise ----
if "%HOST_IP_MODE%"=="Static" (
    copy /y "%IP_FILE%" "%RESTORE_DIR%\ip.txt" >nul
    if errorlevel 1 (
        set "ERRMSG=Failed to copy ip.txt into the image."
        goto :failed
    )
) else (
    if exist "%RESTORE_DIR%\ip.txt" del /f /q "%RESTORE_DIR%\ip.txt"
    if exist "%RESTORE_DIR%\ip.txt" (
        set "ERRMSG=Failed to remove the old ip.txt from the image."
        goto :failed
    )
)

rem ---- [8] torrent ----
copy /y "%TORRENT%" "%RESTORE_DIR%\DVT_backup.torrent" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy DVT_backup.torrent into the image."
    goto :failed
)

rem ---- [9] aria2.conf for the link speed (the templates are kept) ----
if not exist "%RESTORE_DIR%\aria2.conf.%LINK_PROFILE%" (
    set "ERRMSG=aria2.conf.%LINK_PROFILE% template not found in the image."
    goto :failed
)
copy /y "%RESTORE_DIR%\aria2.conf.%LINK_PROFILE%" "%RESTORE_DIR%\aria2.conf" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to create aria2.conf."
    goto :failed
)
rem the link profile also sets the number of seeder check attempts in WinPE
> "%RESTORE_DIR%\link_profile.txt" echo %LINK_PROFILE%
if not exist "%RESTORE_DIR%\link_profile.txt" (
    set "ERRMSG=Failed to write link_profile.txt."
    goto :failed
)

rem ---- [9b] disk ID: write it, or remove an old one ----
if defined HOST_DISK_ID (
    > "%RESTORE_DIR%\%DISK_ID_NAME%" echo %HOST_DISK_ID%
    if not exist "%RESTORE_DIR%\%DISK_ID_NAME%" (
        set "ERRMSG=Failed to write %DISK_ID_NAME% into the image."
        goto :failed
    )
) else (
    if exist "%RESTORE_DIR%\%DISK_ID_NAME%" del /f /q "%RESTORE_DIR%\%DISK_ID_NAME%"
    if exist "%RESTORE_DIR%\%DISK_ID_NAME%" (
        set "ERRMSG=Failed to remove the old %DISK_ID_NAME% from the image."
        goto :failed
    )
)

rem ---- [10] save the image ----
echo [INFO] Saving the image...
"%DISM%" /Unmount-Image /MountDir:"%BOOT_MOUNT_DIR%" /Commit
if errorlevel 1 (
    set "ERRMSG=Failed to save the image."
    goto :failed
)
set "MOUNTED=0"

rem ---- [11] BitLocker: suspend for one restart ----
call "%HOST_DIR%\suspend_bitlocker.bat" %SystemDrive%
if errorlevel 1 (
    set "ERRMSG=BitLocker could not be suspended. Suspend it by hand, or set BITLOCKER_SUSPEND=0 in config.cmd."
    goto :failed
)

rem ---- [12] one-time boot entry ----
call "%HOST_DIR%\set_bcd.bat" "%BOOT_WIM%"
if errorlevel 1 (
    set "ERRMSG=Failed to add the boot entry."
    goto :failed
)

rem ---- done ----
color %LINK_COLOR%
call "%HOST_DIR%\show_ip.bat" %HOST_IP%
set "SUM_DISK=%HOST_DISK_ID%"
if not defined SUM_DISK set "SUM_DISK=none, WinPE fallback rules are used"
echo [INFO] DVT %DVT_VERSION%   Disk ID: %SUM_DISK%   BitLocker: %BITLOCKER_STATE%
echo [DONE] Ready. Link: %LINK_SPEED%. Press a key to restart into WinPE.
pause >nul
shutdown /r /f /t %REBOOT_DELAY_SEC%
exit /b 0


:failed
if "%BITLOCKER_STATE%"=="Suspended" (
    echo [INFO] Turning the BitLocker protection back on...
    "%MANAGEBDE%" -protectors -enable %SystemDrive% >nul 2>&1
)
if "%MOUNTED%"=="1" (
    echo [INFO] Discarding the changes to the mounted image...
    "%DISM%" /Unmount-Image /MountDir:"%BOOT_MOUNT_DIR%" /Discard >nul 2>&1
)
color %COLOR_FAIL%
echo.
if defined HOST_IP echo IP Address : %HOST_IP%
echo [FAILED] !ERRMSG!
echo          The messages above show the step that failed.
pause
exit /b 1
