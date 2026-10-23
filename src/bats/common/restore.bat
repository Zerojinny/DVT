@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - restore.bat (WinPE, shared)
rem  bats\common: used by the client local boot and the USB / CD media.
rem  Started in its own window by start_restore.bat when aria2c has
rem  finished the download (aria2c keeps seeding meanwhile).
rem   1) apply image WIM_INDEX of DL_NAME\WIM_NAME to T:
rem   2) add drivers from DL_NAME\drivers (if present)
rem   3) write the boot files to S: (UEFI or BIOS)
rem   4) stop aria2c, copy ip.txt and DL_NAME\files to T:\temp
rem   5) record the restore in the restored Windows
rem      (HKLM\SOFTWARE\DVT: version, image, date, ...) and register
rem      T:\temp\setpc.bat to run once after the first start
rem   6) delete the downloaded files and reboot
rem  USB / CD media (MEDIA_DRV is set by its startnet.cmd): the IP file
rem  (pc_ip.txt, written by start_media.bat) is moved instead of
rem  copied, and the operator is reminded to remove the boot media.
rem
rem  Top-level script. On failure it waits for a key before
rem  rebooting, because the disk has already been erased.
rem ============================================================

cd /d "%~dp0"
call "%~dp0config.cmd"
set "ERRMSG="
if not defined DVT_VERSION set "DVT_VERSION=unknown"
set "BOOT_MODE=Local"
if defined MEDIA_DRV set "BOOT_MODE=Media"
title DVT %DVT_VERSION% Restore
color %COLOR_RESTORE%
cls
if not defined FIRMWARE call "%~dp0get_firmware.bat"

rem ---- [1] locate the downloaded image ----
rem DL_DRIVE is inherited from start_dvt.bat through aria2c.
set "SRC_DIR="
if defined DL_DRIVE if exist "%DL_DRIVE%:\%DL_NAME%\%WIM_NAME%" set "SRC_DIR=%DL_DRIVE%:\%DL_NAME%"
if not defined SRC_DIR (
    for %%x in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
        if not defined SRC_DIR if exist "%%x:\%DL_NAME%\%WIM_NAME%" set "SRC_DIR=%%x:\%DL_NAME%"
    )
)
if not defined SRC_DIR (
    set "ERRMSG=%DL_NAME%\%WIM_NAME% was not found on any drive."
    goto :failed
)
if not exist "%TDRV%:\" (
    set "ERRMSG=Target drive %TDRV%: does not exist."
    goto :failed
)
if not exist "%SDRV%:\" (
    set "ERRMSG=System drive %SDRV%: does not exist."
    goto :failed
)
if not exist "%WIMLIB%" (
    set "ERRMSG=wimlib-imagex.exe not found."
    goto :failed
)

rem WIM_INDEX must be a whole number of 1 or more (empty = 1)
if not defined WIM_INDEX set "WIM_INDEX=1"
set "IDX_NUM="
set /a "IDX_NUM=WIM_INDEX" >nul 2>&1
if not "%IDX_NUM%"=="%WIM_INDEX%" (
    set "ERRMSG=Invalid WIM_INDEX: %WIM_INDEX%  Use a whole number of 1 or more."
    goto :failed
)
if %IDX_NUM% LSS 1 (
    set "ERRMSG=Invalid WIM_INDEX: %WIM_INDEX%  Use a whole number of 1 or more."
    goto :failed
)

rem the image must exist in the WIM; its name is recorded in the registry
set "IMG_NAME="
set "WIMINFO=%TEMP%\dvt_wiminfo.txt"
"%WIMLIB%" info "%SRC_DIR%\%WIM_NAME%" %WIM_INDEX% > "%WIMINFO%" 2>&1
if errorlevel 1 (
    type "%WIMINFO%"
    set "ERRMSG=Image %WIM_INDEX% could not be read from %WIM_NAME%. Check WIM_INDEX in config.cmd."
    goto :failed
)
for /f "usebackq tokens=1,* delims=:" %%a in ("%WIMINFO%") do (
    if /i "%%a"=="Name" if not defined IMG_NAME for /f "tokens=*" %%n in ("%%b") do set "IMG_NAME=%%n"
)
del /f /q "%WIMINFO%" >nul 2>&1
if not defined IMG_NAME set "IMG_NAME=(no name)"

echo [INFO] DVT    : %DVT_VERSION%
echo [INFO] Source : %SRC_DIR%\%WIM_NAME%
echo [INFO] Index  : %WIM_INDEX%  !IMG_NAME!
echo [INFO] Target : %TDRV%:\
echo.

rem ---- [2] apply the image ----
"%WIMLIB%" apply "%SRC_DIR%\%WIM_NAME%" %WIM_INDEX% %TDRV%:\
if errorlevel 1 (
    set "ERRMSG=Failed to apply image %WIM_INDEX% of %WIM_NAME% to %TDRV%:"
    goto :failed
)

rem ---- [3] drivers ----
if exist "%SRC_DIR%\drivers\" (
    echo [INFO] Adding drivers...
    dism /Image:%TDRV%:\ /Add-Driver /Driver:"%SRC_DIR%\drivers" /Recurse
    if errorlevel 1 echo [WARN] Some drivers could not be added. Continuing.
)

rem ---- [4] boot files ----
echo [INFO] Writing boot files to %SDRV%: for %FIRMWARE%...
bcdboot %TDRV%:\Windows /s %SDRV%: /f %FIRMWARE% /l %BCD_LOCALE%
if errorlevel 1 (
    set "ERRMSG=bcdboot failed. The PC would not be able to start Windows."
    goto :failed
)

rem ---- [5] stop seeding so the downloaded files can be deleted ----
echo [INFO] Stopping aria2c...
if exist "%NIRCMD%" (
    "%NIRCMD%" killprocess aria2c.exe
) else (
    taskkill /f /im aria2c.exe >nul 2>&1
)
call "%~dp0wait.bat" 3

rem ---- [6] extra files for the restored Windows ----
rem the media writes pc_ip.txt for this PC only, so it is moved
if exist "%IP_FILE%" (
    if not exist "%TDRV%:\temp\" mkdir "%TDRV%:\temp"
    if "%BOOT_MODE%"=="Media" (
        move /y "%IP_FILE%" "%TDRV%:\temp\ip.txt" >nul
    ) else (
        copy /y "%IP_FILE%" "%TDRV%:\temp\ip.txt" >nul
    )
    if errorlevel 1 echo [WARN] Could not copy ip.txt to %TDRV%:\temp.
)
set "MOVE_FAIL="
if exist "%SRC_DIR%\files\" call :move_files
call :write_registry

rem ---- [7] clean up the download ----
rem When some files could not be moved, only the image is deleted and
rem the files folder is kept, so nothing that was not moved is lost.
if defined MOVE_FAIL (
    del /f /q "%SRC_DIR%\%WIM_NAME%" >nul 2>&1
    echo [WARN] "%SRC_DIR%\files" was kept because some files could not be moved.
) else (
    rd /s /q "%SRC_DIR%" >nul 2>&1
    if exist "%SRC_DIR%\" echo [WARN] "%SRC_DIR%" could not be deleted completely.
)
if exist "%SRC_DIR%.aria2" del /f /q "%SRC_DIR%.aria2" >nul 2>&1

color %COLOR_OK%
echo.
echo [DONE] Restore completed. Rebooting in %DONE_REBOOT_SEC% seconds...
if "%BOOT_MODE%"=="Media" echo        Remove the USB drive or the CD now, so the PC starts Windows.
call "%~dp0wait.bat" %DONE_REBOOT_SEC%
wpeutil reboot
exit /b 0


:failed
color %COLOR_FAIL%
echo.
echo [ERROR] !ERRMSG!
echo [ERROR] The disk has already been erased.
echo         Fix the problem and run "%~f0" again,
echo         or press any key to reboot.
pause >nul
wpeutil reboot
exit /b 1


rem ============================================================
rem  :move_files
rem  Moves DL_NAME\files into T:\temp. aria2c has already been stopped,
rem  so no file is held open.
rem  On the same volume (download drive = T:) move only renames: it is
rem  instant and needs no free space. From another volume, files are
rem  copied and deleted by move; folders cannot be moved across
rem  volumes, so xcopy is used for them. A folder that already exists
rem  in T:\temp is merged with xcopy.
rem  Sets MOVE_FAIL=1 when anything could not be moved.
rem ============================================================
:move_files
echo [INFO] Moving %DL_NAME%\files to %TDRV%:\temp...
if not exist "%TDRV%:\temp\" mkdir "%TDRV%:\temp"
set "FDIR=%SRC_DIR%\files"

rem files, including hidden and system files
for /f "delims=" %%f in ('dir /b /a-d "%FDIR%" 2^>nul') do (
    move /y "%FDIR%\%%f" "%TDRV%:\temp\" >nul 2>&1
    if errorlevel 1 (
        echo [WARN] Could not move file: %%f
        set "MOVE_FAIL=1"
    )
)

rem folders
for /f "delims=" %%d in ('dir /b /ad "%FDIR%" 2^>nul') do (
    set "MOVED="
    if not exist "%TDRV%:\temp\%%d\" (
        move "%FDIR%\%%d" "%TDRV%:\temp\%%d" >nul 2>&1
        if not errorlevel 1 set "MOVED=1"
    )
    if not defined MOVED (
        xcopy "%FDIR%\%%d" "%TDRV%:\temp\%%d\" /e /i /h /y >nul
        if errorlevel 2 (
            echo [WARN] Could not move folder: %%d
            set "MOVE_FAIL=1"
        )
    )
)
exit /b 0


rem ============================================================
rem  :write_registry
rem  Writes to the offline SOFTWARE hive of the restored Windows:
rem   - HKLM\SOFTWARE\DVT : what was restored, when and by which
rem     DVT version (read it later with: reg query HKLM\SOFTWARE\DVT)
rem   - RunOnce DVT_SetPC : runs C:\temp\setpc.bat once after the
rem     first start (only when T:\temp\setpc.bat exists)
rem  A failure here is only a warning: Windows is already restored.
rem ============================================================
:write_registry
echo [INFO] Writing the restore information to the registry...
reg load HKLM\DVT_SW "%TDRV%:\Windows\System32\config\SOFTWARE" >nul
if errorlevel 1 (
    echo [WARN] Could not load the registry of the restored Windows.
    if exist "%TDRV%:\temp\setpc.bat" echo [WARN] setpc.bat was not registered.
    exit /b 1
)
set "RK=HKLM\DVT_SW\DVT"
set "REG_FAIL="
reg add "%RK%" /v Version /t REG_SZ /d "%DVT_VERSION%" /f >nul || set "REG_FAIL=1"
reg add "%RK%" /v BootMode /t REG_SZ /d "%BOOT_MODE%" /f >nul || set "REG_FAIL=1"
reg add "%RK%" /v RestoredAt /t REG_SZ /d "%DATE% %TIME:~0,8%" /f >nul || set "REG_FAIL=1"
reg add "%RK%" /v Torrent /t REG_SZ /d "%DL_NAME%" /f >nul || set "REG_FAIL=1"
reg add "%RK%" /v ImageFile /t REG_SZ /d "%WIM_NAME%" /f >nul || set "REG_FAIL=1"
reg add "%RK%" /v ImageIndex /t REG_DWORD /d %WIM_INDEX% /f >nul || set "REG_FAIL=1"
reg add "%RK%" /v ImageName /t REG_SZ /d "!IMG_NAME!" /f >nul || set "REG_FAIL=1"
reg add "%RK%" /v Firmware /t REG_SZ /d "%FIRMWARE%" /f >nul || set "REG_FAIL=1"
if defined NET_IP reg add "%RK%" /v IPAddress /t REG_SZ /d "%NET_IP%" /f >nul
if defined TARGET_DISK reg add "%RK%" /v TargetDisk /t REG_SZ /d "%TARGET_DISK%" /f >nul
if defined REG_FAIL echo [WARN] Some restore information could not be written.

if exist "%TDRV%:\temp\setpc.bat" (
    echo [INFO] Registering setpc.bat to run once...
    reg add "HKLM\DVT_SW\Microsoft\Windows\CurrentVersion\RunOnce" /v DVT_SetPC /t REG_SZ /d "C:\temp\setpc.bat" /f >nul
    if errorlevel 1 echo [WARN] Could not register setpc.bat.
)
call :unload_hive
if errorlevel 1 echo [WARN] Could not unload the registry hive.
exit /b 0


rem ============================================================
rem  :unload_hive   up to 3 tries, a handle may close a bit later
rem ============================================================
:unload_hive
for /l %%n in (1,1,3) do (
    reg unload HKLM\DVT_SW >nul 2>&1
    if not errorlevel 1 exit /b 0
    call "%~dp0wait.bat" 2
)
exit /b 1
