@echo off
rem ============================================================
rem  Restore script (runs in WinPE, started by aria2 hook)
rem  - Every step is checked. The backup is deleted ONLY after the
rem    OS was applied and the boot files were created successfully.
rem  - restoring.flag tells startDVT.bat that the restore is in
rem    progress, so killing aria2 does not trigger a reboot.
rem  - The script never falls through into the :setpc subroutine.
rem ============================================================
setlocal EnableExtensions

:restore
cls
color 27
set "tdrv=t"
set "sdrv=s"
set "RFLAG=%SystemDrive%\restore\restoring.flag"
echo restoring> "%RFLAG%"

rem --- find the downloaded backup ---
set "srdrv="
for %%x in (C D E F G H I J K L M N O P Q R S T U V W) do if exist %%x:\DVT_backup\backup.wim set "srdrv=%%x"
if not defined srdrv (
    echo [ERROR] backup.wim was not found on any drive.
    goto :restore_fail
)

echo Source=%srdrv%:\DVT_backup\backup.wim Target=%tdrv%:

if not exist %tdrv%:\ (
    echo [ERROR] Target drive %tdrv%: does not exist.
    goto :restore_fail
)
if not exist %sdrv%:\ (
    echo [ERROR] EFI drive %sdrv%: does not exist.
    goto :restore_fail
)

rem --- 1) apply the image ---
wimlib-imagex.exe apply "%srdrv%:\DVT_backup\backup.wim" 1 %tdrv%:
if errorlevel 1 (
    echo [ERROR] wimlib-imagex apply failed.
    goto :restore_fail
)
if not exist %tdrv%:\windows\system32\config\SYSTEM (
    echo [ERROR] Applied image looks invalid: SYSTEM hive not found.
    goto :restore_fail
)

rem --- 2) drivers (failure is not fatal) ---
if exist "%srdrv%:\DVT_backup\drivers\" (
    Dism /Image:%tdrv%:\ /Add-Driver /Driver:"%srdrv%:\DVT_backup\drivers" /Recurse
    if errorlevel 1 echo [WARNING] Driver injection failed. Continuing.
)

rem --- 3) boot files (UEFI) ---
bcdboot %tdrv%:\windows /s %sdrv%: /f UEFI /l ko-kr
if errorlevel 1 (
    echo [ERROR] bcdboot failed.
    goto :restore_fail
)
if not exist %sdrv%:\EFI\Microsoft\Boot\bootmgfw.efi (
    echo [ERROR] bootmgfw.efi was not created on %sdrv%:
    goto :restore_fail
)

rem --- everything succeeded: now it is safe to clean up ---
nircmd killprocess aria2c.exe
del %srdrv%:\DVT_backup\backup.wim /q

rem --- extra files for the restored Windows ---
if not exist %tdrv%:\temp\ mkdir %tdrv%:\temp
if exist x:\restore\ip.txt copy x:\restore\ip.txt %tdrv%:\temp\ip.txt /y
if exist %srdrv%:\DVT_backup\files\ move /y %srdrv%:\DVT_backup\files\*.* %tdrv%:\temp\
if exist %tdrv%:\temp\setpc.bat call :setpc

rd %srdrv%:\DVT_backup /s /q
Wpeutil Reboot
exit /b 0

:restore_fail
color 4F
echo.
echo [FAILED] Restore did not complete. The backup files were NOT deleted.
echo          Check the messages above. Press any key to reboot.
pause >nul
Wpeutil Reboot
exit /b 1

:setpc
rem Register setpc.bat in RunOnce so it runs at the first logon
reg load HKEY_LOCAL_MACHINE\tmp %tdrv%:\windows\system32\config\software
if errorlevel 1 (
    echo [WARNING] Could not load the software hive. setpc.bat was not registered.
    exit /b 1
)
reg add HKEY_LOCAL_MACHINE\tmp\Microsoft\Windows\CurrentVersion\RunOnce /v DVT_setpc /t REG_SZ /d "c:\temp\setpc.bat" /f
reg unload HKEY_LOCAL_MACHINE\tmp
if errorlevel 1 (
    ping -n 3 127.0.0.1 >nul
    reg unload HKEY_LOCAL_MACHINE\tmp
)
exit /b 0
