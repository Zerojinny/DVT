@echo off

REM ---- WOW64 fix: relaunch in 64-bit cmd when started from 32-bit cmd ----
if defined PROCESSOR_ARCHITEW6432 (
    if exist "%SystemRoot%\Sysnative\cmd.exe" (
        "%SystemRoot%\Sysnative\cmd.exe" /c ""%~f0" %*"
        exit /b %errorlevel%
    )
)

setlocal EnableExtensions
rem ============================================================
rem  DU-Help Deployment Script
rem
rem  Changes in this version:
rem   - The pristine c:\temp\boot\boot.wim is NEVER modified.
rem     A working copy is mounted on a LOCAL folder, customized, and
rem     saved as c:\temp\boot\deploy\boot.wim (re-runnable any time).
rem   - Stale mounts are cleaned up before mounting.
rem   - getnetdrv.bat exit codes are handled (the old code reused a
rem     stale errorlevel when Realtek was detected).
rem   - setbcd.bat receives the WIM path explicitly.
rem   - rem is used instead of :: inside blocks.
rem ============================================================

rem ---------------------------------------------------------
rem [1] Elevate to administrator if needed
rem ---------------------------------------------------------
reg.exe query "HKU\S-1-5-20" >nul 2>&1
if errorlevel 1 (
    echo [INFO] Not running as administrator. Relaunching with elevation...
    PowerShell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

cls
cd /d "%~dp0"
if errorlevel 1 (
    echo [ERROR] Failed to change working directory: "%~dp0"
    pause
    exit /b 1
)

set "MOUNTED=0"
set "wimfile=c:\temp\boot\boot.wim"
set "outdir=c:\temp\boot\deploy"
set "deploywim=%outdir%\boot.wim"
set "localbuild=%SystemDrive%\WinPE_LocalBuild"
set "workwim=%localbuild%\boot.wim"
set "mountdir=%localbuild%\mount"
set "torrentfile=c:\temp\DVT_backup.torrent"

rem ---------------------------------------------------------
rem [2] Remove old DVT.tag markers and create a fresh one
rem ---------------------------------------------------------
for %%A in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist %%A:\DVT.tag (
        del %%A:\DVT.tag /F /Q
        if errorlevel 1 echo [WARNING] Could not delete %%A:\DVT.tag - it may be locked or read-only.
    )
)

echo DUHELP> "%SystemDrive%\DVT.tag"
if errorlevel 1 (
    echo [ERROR] Failed to create marker file: "%SystemDrive%\DVT.tag"
    pause
    exit /b 1
)

rem ---------------------------------------------------------
rem [3] Network info, link speed, NIC drivers
rem ---------------------------------------------------------
if not exist "%~dp0getip.bat" (
    echo [ERROR] getip.bat not found next to this script.
    pause
    exit /b 1
)
call getip.bat
if errorlevel 1 (
    echo [ERROR] getip.bat reported an error.
    pause
    exit /b 1
)

if not exist "%~dp0getlinkspeed.bat" (
    echo [ERROR] getlinkspeed.bat not found next to this script.
    pause
    exit /b 1
)
call getlinkspeed.bat
if errorlevel 1 (
    echo [ERROR] getlinkspeed.bat reported an error.
    pause
    exit /b 1
)

if not exist "%~dp0getnetdrv.bat" (
    echo [ERROR] getnetdrv.bat not found next to this script.
    pause
    exit /b 1
)
set "NETDRV=0"
call getnetdrv.bat
set "NETRC=%errorlevel%"
if "%NETRC%"=="0" set "NETDRV=1"
if "%NETRC%"=="3" echo [INFO] Only Realtek adapters found. Driver injection will be skipped.
if "%NETRC%"=="2" echo [WARNING] No connected physical adapter found. Driver injection will be skipped.
if not "%NETRC%"=="0" if not "%NETRC%"=="2" if not "%NETRC%"=="3" (
    echo [ERROR] getnetdrv.bat failed. Exit code: %NETRC%
    pause
    exit /b 1
)

if not defined linkspeed echo [WARNING] "linkspeed" variable was not set by getlinkspeed.bat.
if not defined speed     echo [WARNING] "speed" variable was not set by getlinkspeed.bat.

title %linkspeed%

rem ---------------------------------------------------------
rem [4] Verify source files
rem ---------------------------------------------------------
if not exist "%torrentfile%" (
    echo [ERROR] %torrentfile% not found.
    goto error1
)
if not exist "%wimfile%" (
    echo [ERROR] WIM file not found: "%wimfile%"
    goto error1
)

rem ---------------------------------------------------------
rem [5] Prepare a clean local work area and a working copy of the WIM
rem ---------------------------------------------------------
if not exist "%mountdir%\" mkdir "%mountdir%" 2>nul
if not exist "%mountdir%\" (
    echo [ERROR] Failed to create mount folder: "%mountdir%"
    goto error1
)

rem Discard leftovers of a previous failed run
dism /unmount-wim /mountdir:"%mountdir%" /discard >nul 2>&1
dism /cleanup-wim >nul 2>&1

if exist "%workwim%" del /f /q "%workwim%" >nul 2>&1
copy /y "%wimfile%" "%workwim%" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy the WIM to the local work folder.
    goto error1
)
attrib -r "%workwim%" >nul 2>&1

rem ---------------------------------------------------------
rem [6] Mount the working copy
rem ---------------------------------------------------------
echo [INFO] Mounting "%workwim%" ...
dism /mount-wim /wimfile:"%workwim%" /index:1 /mountdir:"%mountdir%"
if errorlevel 1 (
    echo [ERROR] Failed to mount the WIM image.
    goto error1
)
set "MOUNTED=1"

rem ---------------------------------------------------------
rem [7] Inject network drivers (skipped when none were exported)
rem ---------------------------------------------------------
if "%NETDRV%"=="1" (
    dism /Image:"%mountdir%" /Add-Driver /Driver:"%~dp0netdrv" /Recurse
    if errorlevel 1 (
        echo [ERROR] Failed to add drivers.
        goto error1
    )
)

rem ---------------------------------------------------------
rem [8] Copy restore-related files into the mounted image
rem ---------------------------------------------------------
if not exist "%mountdir%\restore\" mkdir "%mountdir%\restore" 2>nul

if not exist "c:\temp\ip.txt" (
    echo [INFO] c:\temp\ip.txt not found. WinPE will use DHCP.
) else (
    copy "c:\temp\ip.txt" "%mountdir%\restore\ip.txt" /y
    if errorlevel 1 (
        echo [ERROR] Failed to copy ip.txt.
        goto error1
    )
)

copy "%torrentfile%" "%mountdir%\restore\DVT_backup.torrent" /y
if errorlevel 1 (
    echo [ERROR] Failed to copy DVT_backup.torrent.
    goto error1
)

rem ---------------------------------------------------------
rem [9] Select the aria2 config template matching the link speed
rem ---------------------------------------------------------
set "ARIATPL=aria2.conf.100"
if "%speed%"=="27" set "ARIATPL=aria2.conf.1G"

if not exist "%mountdir%\restore\%ARIATPL%" (
    echo [ERROR] %ARIATPL% template not found in mounted image.
    goto error1
)
ren "%mountdir%\restore\%ARIATPL%" aria2.conf
if errorlevel 1 (
    echo [ERROR] Failed to rename %ARIATPL% to aria2.conf.
    goto error1
)

rem ---------------------------------------------------------
rem [10] Commit and unmount, then publish the result
rem ---------------------------------------------------------
echo [INFO] Committing changes and unmounting the image...
dism /unmount-wim /mountdir:"%mountdir%" /commit
if errorlevel 1 (
    echo [ERROR] Failed to unmount/commit the image.
    goto error1
)
set "MOUNTED=0"

if not exist "%outdir%\" mkdir "%outdir%" 2>nul
copy /y "%workwim%" "%deploywim%" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy the finished WIM to "%deploywim%"
    goto error1
)
del /f /q "%workwim%" >nul 2>&1
if exist "c:\temp\boot\boot.sdi" copy /y "c:\temp\boot\boot.sdi" "%outdir%\boot.sdi" >nul

rem ---------------------------------------------------------
rem [11] Update the boot configuration (BCD)
rem ---------------------------------------------------------
if not exist "%~dp0setbcd.bat" (
    echo [ERROR] setbcd.bat not found next to this script.
    goto error1
)
call setbcd.bat "%deploywim%"
if errorlevel 1 (
    echo [ERROR] setbcd.bat reported a failure.
    goto error1
)

:complete
color %speed%
call printip.bat
echo.
echo [DONE] Deployment completed successfully.
pause
shutdown /r /f /t 10
exit /b 0

:error1
call :cleanup_mount
cls
color 40
call printip.bat
echo.
echo [FAILED] Deployment did not complete. See the messages above for details.
pause
exit /b 1

rem ============================================================
rem  Subroutine: discard the mounted image if it is still mounted
rem ============================================================
:cleanup_mount
if "%MOUNTED%"=="1" (
    echo [INFO] Discarding changes to the mounted image due to failure...
    dism /unmount-wim /mountdir:"%mountdir%" /discard >nul 2>&1
    set "MOUNTED=0"
)
exit /b 0
