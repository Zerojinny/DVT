@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT media - restore.bat (WinPE)
rem  Started in its own window by start_restore.bat when aria2c has
rem  finished the download (aria2c keeps seeding meanwhile).
rem  Same as pe\restore.bat, except that the IP file (pc_ip.txt,
rem  written by start_media.bat) is moved instead of copied, and the
rem  operator is reminded to remove the boot media before the reboot.
rem   1) apply DL_NAME\WIM_NAME to T:
rem   2) add drivers from DL_NAME\drivers (if present)
rem   3) write the boot files to S: (UEFI or BIOS)
rem   4) stop aria2c, move pc_ip.txt (as ip.txt) and DL_NAME\files to T:\temp
rem   5) register T:\temp\setpc.bat to run once after first start
rem   6) delete the downloaded files and reboot
rem
rem  Top-level script. On failure it waits for a key before
rem  rebooting, because the disk has already been erased.
rem ============================================================

cd /d "%~dp0"
call "%~dp0config.cmd"
set "ERRMSG="
title DVT Restore
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

echo [INFO] Source : %SRC_DIR%\%WIM_NAME%
echo [INFO] Target : %TDRV%:\
echo.

rem ---- [2] apply the image ----
"%WIMLIB%" apply "%SRC_DIR%\%WIM_NAME%" 1 %TDRV%:\
if errorlevel 1 (
    set "ERRMSG=Failed to apply %WIM_NAME% to %TDRV%:"
    goto :failed
)

rem the marker of the old installation must not survive
if exist "%TDRV%:\%TAG_FILE%" del /f /q "%TDRV%:\%TAG_FILE%" >nul 2>&1

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
if exist "%IP_FILE%" (
    if not exist "%TDRV%:\temp\" mkdir "%TDRV%:\temp"
    move /y "%IP_FILE%" "%TDRV%:\temp\ip.txt" >nul
    if errorlevel 1 echo [WARN] Could not move ip.txt.
)
set "MOVE_FAIL="
if exist "%SRC_DIR%\files\" call :move_files
if exist "%TDRV%:\temp\setpc.bat" call :register_setpc

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
echo        Remove the USB drive or the CD now, so the PC starts Windows.
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
rem  :register_setpc
rem  Runs C:\temp\setpc.bat once after the first start of the
rem  restored Windows (HKLM RunOnce in the offline SOFTWARE hive).
rem ============================================================
:register_setpc
echo [INFO] Registering setpc.bat to run once...
reg load HKLM\DVT_SW "%TDRV%:\Windows\System32\config\SOFTWARE" >nul
if errorlevel 1 (
    echo [WARN] Could not load the registry of the restored Windows. setpc.bat was not registered.
    exit /b 1
)
reg add "HKLM\DVT_SW\Microsoft\Windows\CurrentVersion\RunOnce" /v DVT_SetPC /t REG_SZ /d "C:\temp\setpc.bat" /f >nul
if errorlevel 1 echo [WARN] Could not register setpc.bat.
reg unload HKLM\DVT_SW >nul
if errorlevel 1 echo [WARN] Could not unload the registry hive.
exit /b 0
