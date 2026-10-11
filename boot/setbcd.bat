@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  Registers winpe.wim as a boot menu entry and boots into it
rem  ONE TIME on next reboot. Optionally auto-removes the entry
rem  afterward.
rem
rem  Usage: run as Administrator
rem     winpe_boot.bat                 (uses the WIMFILE variable below)
rem     winpe_boot.bat D:\PE\winpe.wim (path passed as argument)
rem ============================================================

set "BCDEDIT=%windir%\System32\bcdedit.exe"
if exist "%windir%\Sysnative\bcdedit.exe" set "BCDEDIT=%windir%\Sysnative\bcdedit.exe"

rem ===== Settings (edit here only) =====
set "WIMFILE=%~dp0boot.wim"
set "ENTRY_NAME=WinPE"
set "BOOT_TIMEOUT=5"

rem How to auto-remove the boot entry after use:
rem   1 = Remove from inside WinPE  (adds a delete command to the WIM's
rem       startnet.cmd via DISM)
rem   2 = Remove on the next Windows boot  (uses Task Scheduler,
rem       does not modify the WIM)
rem   0 = Do not auto-remove
set "CLEANUP_MODE=2"

rem WIM image index to modify for mode 1 (usually 1 for WinPE)
set "WIM_INDEX=1"
rem ====================================

set "TASKNAME=WinPE_BCD_Cleanup"
if not "%~1"=="" set "WIMFILE=%~1"
set "GUIDFILE=%~dp0winpe_entry.guid"

rem --- Check for Administrator privileges ---
reg.exe query "HKU\S-1-5-20" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] This script must be run as Administrator.
    goto :end_fail
)

rem --- Validate WIM file and split its path ---
if not exist "%WIMFILE%" (
    echo [ERROR] WIM file not found: %WIMFILE%
    goto :end_fail
)
for %%F in ("%WIMFILE%") do (
    set "WIMDRIVE=%%~dF"
    set "WIMFOLDER=%%~pF"
    set "WIMPATH=%%~pnxF"
)
if "%WIMDRIVE:~0,2%"=="\\" (
    echo [ERROR] Network paths are not supported. Place the WIM on a local drive.
    goto :end_fail
)
set "SDI_PATH=%WIMFOLDER%boot.sdi"

rem --- Check for boot.sdi (auto-copy if missing) ---
if exist "%WIMDRIVE%%SDI_PATH%" goto :sdi_ok
if exist "%~dp0boot.sdi" (
    copy /y "%~dp0boot.sdi" "%WIMDRIVE%%SDI_PATH%" >nul
) else if exist "%SystemRoot%\Boot\DVD\PCAT\boot.sdi" (
    copy /y "%SystemRoot%\Boot\DVD\PCAT\boot.sdi" "%WIMDRIVE%%SDI_PATH%" >nul
)
if not exist "%WIMDRIVE%%SDI_PATH%" (
    echo [ERROR] boot.sdi not found. Place boot.sdi in the same folder as the WIM file.
    echo         ^(Windows ADK: ...\Windows Preinstallation Environment\amd64\Media\Boot\boot.sdi^)
    goto :end_fail
)
:sdi_ok

rem --- Remove any entry/task created by a previous run of this script ---
schtasks /delete /tn "%TASKNAME%" /f >nul 2>&1
if exist "%GUIDFILE%" (
    set /p OLDGUID=<"%GUIDFILE%"
    if defined OLDGUID %bcdedit% /delete !OLDGUID! /cleanup >nul 2>&1
    del "%GUIDFILE%" >nul 2>&1
)

rem --- Configure ramdisk options ---
%bcdedit% /create {ramdiskoptions} /d "Ramdisk Options" >nul 2>&1
%bcdedit% /set {ramdiskoptions} ramdisksdidevice partition=%WIMDRIVE% >nul || goto :fail
%bcdedit% /set {ramdiskoptions} ramdisksdipath %SDI_PATH% >nul || goto :fail

rem --- Copy the current boot entry to create a new one (works for both BIOS and UEFI) ---
set "LINE="
for /f "delims=" %%i in ('%bcdedit% /copy {current} /d "%ENTRY_NAME%" ^| findstr "{"') do set "LINE=%%i"
if not defined LINE goto :fail
set "REST=!LINE:*{=!"
set "GUID="
for /f "delims=}" %%g in ("!REST!") do set "GUID={%%g}"
if not defined GUID goto :fail
echo New boot entry GUID: %GUID%

rem --- Configure the WinPE entry ---
set "RAMDEV=ramdisk=[%WIMDRIVE%]%WIMPATH%,{ramdiskoptions}"
%bcdedit% /set %GUID% device %RAMDEV% >nul || goto :fail
%bcdedit% /set %GUID% osdevice %RAMDEV% >nul || goto :fail
%bcdedit% /set %GUID% systemroot \windows >nul || goto :fail
%bcdedit% /set %GUID% winpe yes >nul || goto :fail
%bcdedit% /set %GUID% detecthal yes >nul || goto :fail
%bcdedit% /timeout %BOOT_TIMEOUT%

rem --- Set up auto-removal ---
if "%CLEANUP_MODE%"=="1" (
    call :inject_wim
    if errorlevel 1 goto :fail
)
if "%CLEANUP_MODE%"=="2" (
    call :make_task
    if errorlevel 1 goto :fail
)

rem --- Add to boot menu + set as the next one-time boot entry ---
%bcdedit% /displayorder %GUID% /addlast >nul || goto :fail
%bcdedit% /bootsequence %GUID% >nul || goto :fail

>"%GUIDFILE%" echo %GUID%

rem echo.
rem echo [DONE] The "%ENTRY_NAME%" entry has been added. The next boot only will start WinPE.
rem echo        WIM : %WIMFILE%
rem if "%CLEANUP_MODE%"=="1" echo        Auto-remove: on WinPE startup ^(startnet.cmd^)
rem if "%CLEANUP_MODE%"=="2" echo        Auto-remove: on next Windows boot ^(Task Scheduler^)
rem if "%CLEANUP_MODE%"=="0" echo        Manual removal: %bcdedit% /delete %GUID% /cleanup
rem echo.
rem choice /c YN /m "Reboot now"
rem if errorlevel 2 goto :end_ok
rem shutdown /r /t 5 /c "Rebooting to start WinPE."
goto :end_ok

:fail
echo [ERROR] Something went wrong while configuring the boot entry. See the messages above.
schtasks /delete /tn "%TASKNAME%" /f >nul 2>&1
if defined GUID %bcdedit% /delete %GUID% /cleanup >nul 2>&1
:end_fail
pause
exit /b 1

:end_ok
endlocal
exit /b 0


rem ============================================================
rem  Mode 1: mount the WIM and add a delete command to startnet.cmd
rem ============================================================
:inject_wim
set "MOUNTDIR=%TEMP%\winpe_mount_%RANDOM%"
mkdir "%MOUNTDIR%" 2>nul
attrib -r "%WIMFILE%" >nul 2>&1
echo Mounting WIM, this may take a moment...
dism /Mount-Wim /WimFile:"%WIMFILE%" /Index:%WIM_INDEX% /MountDir:"%MOUNTDIR%" >nul
if errorlevel 1 (
    echo [ERROR] Failed to mount the WIM. Check WIM_INDEX and the WIM file state.
    dism /Cleanup-Wim >nul 2>&1
    rmdir "%MOUNTDIR%" 2>nul
    exit /b 1
)
set "STARTNET=%MOUNTDIR%\Windows\System32\startnet.cmd"
rem Remove any delete command added by a previous run
if exist "%STARTNET%" (
    findstr /v /c:"WINPE_BCD_CLEANUP" "%STARTNET%" >"%STARTNET%.new"
    move /y "%STARTNET%.new" "%STARTNET%" >nul
)
>>"%STARTNET%" echo.
>>"%STARTNET%" echo %bcdedit% /delete %GUID% /cleanup ^& rem WINPE_BCD_CLEANUP
echo Saving WIM...
dism /Unmount-Wim /MountDir:"%MOUNTDIR%" /Commit >nul
if errorlevel 1 (
    echo [ERROR] Failed to save the WIM. Discarding changes.
    dism /Unmount-Wim /MountDir:"%MOUNTDIR%" /Discard >nul
    rmdir "%MOUNTDIR%" 2>nul
    exit /b 1
)
rmdir "%MOUNTDIR%" 2>nul
exit /b 0


rem ============================================================
rem  Mode 2: register a task that deletes the entry on the next
rem  Windows boot, then deletes itself
rem ============================================================
:make_task
schtasks /create /tn "%TASKNAME%" /sc onstart /ru SYSTEM /rl HIGHEST /f /tr "cmd /c %bcdedit% /delete %GUID% /cleanup & schtasks /delete /tn %TASKNAME% /f" >nul
if errorlevel 1 (
    echo [ERROR] Failed to register the scheduled task.
    exit /b 1
)
exit /b 0
