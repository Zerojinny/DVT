@echo off
cls

rem Make sure relative calls (get_disk.bat etc.) resolve to this script's folder
cd /d "%~dp0"

echo.
echo Starting WinPE...
wpeinit

echo.
echo Disabling firewall...
wpeutil DisableFirewall

rem Set power plan to High Performance
powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

rem Open an extra minimized command prompt for troubleshooting
start "" /min cmd.exe

rem Flag created by restore.bat while the restore is running
set "RFLAG=%SystemDrive%\restore\restoring.flag"
if exist "%RFLAG%" del /f /q "%RFLAG%" >nul 2>&1

rem Target disk number: set manually here if needed (e.g. set "ndisk=0")
set "ndisk="
set "TARGET="
set "IP="

rem If no disk is specified, run the disk selection batch file
if not defined ndisk call get_disk.bat
if not defined ndisk (
    echo [ERROR] Target disk was not determined.
    goto :fail
)

rem If ip.txt exists, apply a static IP (fall back to DHCP on failure)
set "IPOK="
if exist "%SystemDrive%\restore\ip.txt" (
    call set_ip.bat
    if not errorlevel 1 set "IPOK=1"
    if not defined IPOK echo [WARNING] Static IP setup failed. Falling back to DHCP.
)
if not defined IPOK call get_ip.bat
title IP : %IP%

rem Verify connectivity to the gateway; reboot if unreachable
call check_gateway.bat
if errorlevel 1 (
    echo [ERROR] Gateway is unreachable.
    goto :fail
)

rem Verify the seeder is available BEFORE the disk is wiped
call check_seeder.bat "%~dp0DVT_backup.torrent"
if errorlevel 1 (
    echo [ERROR] Seeder not found.
    goto :fail
)

rem Clean the target disk, create partitions, and mount them
call makedisk.bat
if errorlevel 1 (
    echo [ERROR] Disk preparation failed.
    goto :fail
)

rem Start the torrent download
cls
color 70

call get_target.bat
if not defined TARGET (
    echo [ERROR] Target drive letter not found.
    goto :fail
)

rem Remove folder & file from any previous download
if exist "%TARGET%:\DVT_backup\" rd /s /q "%TARGET%:\DVT_backup"
if exist "%TARGET%:\DVT_backup.aria2" del /q "%TARGET%:\DVT_backup.aria2"

aria2c -T "%~dp0DVT_backup.torrent" --conf-path="%SystemDrive%\restore\aria2.conf" --dir=%TARGET%:\
set "ARC=%errorlevel%"

rem restore.bat is started by the aria2 hook and kills aria2 when it is done.
rem If the restore is running, wait for it (it reboots the PC by itself).
if exist "%RFLAG%" goto :wait_restore

if not "%ARC%"=="0" (
    echo [ERROR] Download failed. Exit code: %ARC%
    goto :fail
)
exit /b 0

:wait_restore
echo.
echo Restore in progress. Waiting...
:wait_loop
ping -n 6 127.0.0.1 >nul
goto :wait_loop

:fail
echo Rebooting in 10 seconds...
ping -n 11 127.0.0.1 >nul
wpeutil reboot
exit /b 1
