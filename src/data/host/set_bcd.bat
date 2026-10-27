@echo off
rem ============================================================
rem  DVT - set_bcd.bat (Windows)
rem  Adds boot.wim as a WinPE boot menu entry and makes it the
rem  boot entry for the NEXT boot only.
rem  The entry is removed afterwards, depending on BCD_CLEANUP_MODE
rem  in config.cmd:
rem    1 = from inside WinPE (adds a delete command to startnet.cmd
rem        inside the WIM)
rem    2 = on the next Windows boot (scheduled task, WIM unchanged)
rem    0 = not removed
rem
rem  Usage : set_bcd.bat [path\to\boot.wim]   (default: BOOT_WIM)
rem  Exit  : 0 = OK
rem          1 = failed
rem         10 = not running as administrator
rem ============================================================

rem ---- relaunch in 64-bit cmd when started from a 32-bit process ----
if not defined PROCESSOR_ARCHITEW6432 goto :arch_ok
if not exist "%SystemRoot%\Sysnative\cmd.exe" goto :arch_ok
"%SystemRoot%\Sysnative\cmd.exe" /c ""%~f0" %*"
exit /b
:arch_ok

rem ---- administrator check (relaunch only when run on its own) ----
reg.exe query "HKU\S-1-5-20" >nul 2>&1
if not errorlevel 1 goto :admin_ok
if defined DVT_PARENT (
    echo [ERROR] Administrator rights are required.
    exit /b 10
)
echo [INFO] Administrator rights are required. Requesting elevation...
if "%~1"=="" goto :elevate_noargs
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '\"%~1\"' -Verb RunAs" >nul 2>&1
goto :elevate_check
:elevate_noargs
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
:elevate_check
if errorlevel 1 (
    echo [ERROR] Failed to elevate to administrator.
    pause
    exit /b 10
)
exit /b 0
:admin_ok

setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0config.cmd"

set "WIMFILE=%~1"
if not defined WIMFILE set "WIMFILE=%BOOT_WIM%"
set "GUID="
set "ERRMSG="

rem ---- validate the WIM file and split its path ----
if not exist "%WIMFILE%" (
    set "ERRMSG=WIM file not found: %WIMFILE%"
    goto :fail
)
for %%F in ("%WIMFILE%") do (
    set "WIMDRIVE=%%~dF"
    set "WIMFOLDER=%%~pF"
    set "WIMPATH=%%~pnxF"
)
if "%WIMDRIVE:~0,2%"=="\\" (
    set "ERRMSG=Network paths are not supported. Put the WIM on a local drive."
    goto :fail
)
set "SDI_PATH=%WIMFOLDER%boot.sdi"

rem ---- boot.sdi must be next to the WIM (copied if missing) ----
if not exist "%WIMDRIVE%%SDI_PATH%" (
    for %%S in ("%HOST_DIR%\boot.sdi" "%OUT_DIR%\boot.sdi" "%SystemRoot%\Boot\DVD\PCAT\boot.sdi" "%SystemRoot%\Boot\DVD\EFI\boot.sdi") do (
        if not exist "%WIMDRIVE%%SDI_PATH%" if exist "%%~S" copy /y "%%~S" "%WIMDRIVE%%SDI_PATH%" >nul
    )
)
if not exist "%WIMDRIVE%%SDI_PATH%" (
    set "ERRMSG=boot.sdi not found. Put boot.sdi in the same folder as the WIM file."
    goto :fail
)

rem ---- remove the entry and task left by an earlier run ----
schtasks /delete /tn "%BCD_TASK_NAME%" /f >nul 2>&1
if exist "%BCD_GUID_FILE%" (
    set "OLDGUID="
    set /p OLDGUID=<"%BCD_GUID_FILE%"
    if defined OLDGUID "%BCDEDIT%" /delete !OLDGUID! /cleanup >nul 2>&1
    del /f /q "%BCD_GUID_FILE%" >nul 2>&1
)

rem ---- ramdisk options ----
"%BCDEDIT%" /create {ramdiskoptions} /d "Ramdisk Options" >nul 2>&1
"%BCDEDIT%" /set {ramdiskoptions} ramdisksdidevice partition=%WIMDRIVE% >nul || goto :fail_bcd
"%BCDEDIT%" /set {ramdiskoptions} ramdisksdipath %SDI_PATH% >nul || goto :fail_bcd

rem ---- copy the current entry to create a new one (BIOS and UEFI) ----
rem (BCDEDIT is not quoted here: cmd /c would strip the wrong quotes;
rem  the System32 path contains no spaces)
set "LINE="
for /f "delims=" %%i in ('%BCDEDIT% /copy {current} /d "%BOOT_ENTRY_NAME%" ^| findstr "{"') do set "LINE=%%i"
if not defined LINE goto :fail_bcd
set "REST=!LINE:*{=!"
for /f "delims=}" %%g in ("!REST!") do set "GUID={%%g}"
if not defined GUID goto :fail_bcd
echo [INFO] New boot entry: %GUID%

rem ---- turn the copy into a WinPE ramdisk entry ----
set "RAMDEV=ramdisk=[%WIMDRIVE%]%WIMPATH%,{ramdiskoptions}"
"%BCDEDIT%" /set %GUID% device %RAMDEV% >nul || goto :fail_bcd
"%BCDEDIT%" /set %GUID% osdevice %RAMDEV% >nul || goto :fail_bcd
"%BCDEDIT%" /set %GUID% systemroot \windows >nul || goto :fail_bcd
"%BCDEDIT%" /set %GUID% winpe yes >nul || goto :fail_bcd
"%BCDEDIT%" /set %GUID% detecthal yes >nul || goto :fail_bcd
"%BCDEDIT%" /timeout %BOOT_MENU_TIMEOUT% >nul

rem ---- automatic removal ----
if "%BCD_CLEANUP_MODE%"=="1" (
    call :inject_wim
    if errorlevel 1 goto :fail_bcd
)
if "%BCD_CLEANUP_MODE%"=="2" (
    call :make_task
    if errorlevel 1 goto :fail_bcd
)

rem ---- add to the menu and use it for the next boot only ----
"%BCDEDIT%" /displayorder %GUID% /addlast >nul || goto :fail_bcd
"%BCDEDIT%" /bootsequence %GUID% >nul || goto :fail_bcd

> "%BCD_GUID_FILE%" echo %GUID%
echo [INFO] The next boot starts "%BOOT_ENTRY_NAME%" once.
if not defined DVT_PARENT pause
endlocal
exit /b 0


:fail_bcd
set "ERRMSG=Configuring the boot entry failed. See the messages above."
:fail
echo [ERROR] !ERRMSG!
schtasks /delete /tn "%BCD_TASK_NAME%" /f >nul 2>&1
if defined GUID "%BCDEDIT%" /delete %GUID% /cleanup >nul 2>&1
if not defined DVT_PARENT pause
endlocal
exit /b 1


rem ============================================================
rem  Mode 1: mount the WIM and add a delete command to startnet.cmd
rem  The command goes right after "@echo off", before start_dvt.bat
rem  is called. Inside WinPE, bcdedit is on the PATH.
rem ============================================================
:inject_wim
set "IMOUNT=%TEMP%\dvt_bcd_mount"
call "%HOST_DIR%\prepare_mount_dir.bat" "%IMOUNT%"
if errorlevel 1 exit /b 1
attrib -r "%WIMFILE%" >nul 2>&1
echo [INFO] Mounting the WIM to add the cleanup command...
"%DISM%" /Mount-Image /ImageFile:"%WIMFILE%" /Index:1 /MountDir:"%IMOUNT%" >nul
if errorlevel 1 (
    echo [ERROR] Failed to mount the WIM.
    exit /b 1
)
set "STARTNET=%IMOUNT%\Windows\System32\startnet.cmd"
> "%STARTNET%.new" echo @echo off
>> "%STARTNET%.new" echo bcdedit /delete %GUID% /cleanup ^>nul 2^>^&1 ^& rem DVT_BCD_CLEANUP
if exist "%STARTNET%" findstr /v /i /c:"DVT_BCD_CLEANUP" /c:"@echo off" "%STARTNET%" >> "%STARTNET%.new"
move /y "%STARTNET%.new" "%STARTNET%" >nul
"%DISM%" /Unmount-Image /MountDir:"%IMOUNT%" /Commit >nul
if errorlevel 1 (
    echo [ERROR] Failed to save the WIM. Discarding changes.
    "%DISM%" /Unmount-Image /MountDir:"%IMOUNT%" /Discard >nul 2>&1
    exit /b 1
)
rd "%IMOUNT%" 2>nul
exit /b 0


rem ============================================================
rem  Mode 2: task that deletes the entry on the next Windows boot,
rem  then deletes itself
rem ============================================================
:make_task
schtasks /create /tn "%BCD_TASK_NAME%" /sc onstart /ru SYSTEM /rl HIGHEST /f /tr "cmd /c %BCDEDIT% /delete %GUID% /cleanup & schtasks /delete /tn %BCD_TASK_NAME% /f" >nul
if errorlevel 1 (
    echo [ERROR] Failed to register the scheduled task.
    exit /b 1
)
exit /b 0
