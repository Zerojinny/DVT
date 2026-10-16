@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - prepare_mount_dir.bat (Windows)
rem  Makes sure a DISM mount folder exists and is empty.
rem  An image still mounted there by an interrupted run is
rem  discarded first.
rem
rem  Usage : call prepare_mount_dir.bat <folder>
rem  Exit  : 0 = folder ready
rem          1 = folder could not be emptied or created
rem          2 = no folder given
rem ============================================================

call "%~dp0config.cmd"

set "MDIR=%~1"
if not defined MDIR exit /b 2

rem ---- 1) discard an image that is still mounted on this folder ----
set "STILL_MOUNTED="
for /f "delims=" %%L in ('%DISM% /English /Get-MountedImageInfo 2^>nul') do (
    set "L=%%L"
    if not "!L:%MDIR%=!"=="!L!" set "STILL_MOUNTED=1"
)
if defined STILL_MOUNTED (
    echo [WARN] An image is still mounted on "%MDIR%". Discarding it...
    "%DISM%" /Unmount-Image /MountDir:"%MDIR%" /Discard >nul 2>&1
    "%DISM%" /Cleanup-Mountpoints >nul 2>&1
)

rem ---- 2) the folder must exist and be empty ----
if not exist "%MDIR%\" mkdir "%MDIR%" 2>nul
if not exist "%MDIR%\" (
    echo [ERROR] Could not create the mount folder: "%MDIR%"
    exit /b 1
)
set "HAS_FILES="
for /f "delims=" %%x in ('dir /b /a "%MDIR%" 2^>nul') do set "HAS_FILES=1"
if defined HAS_FILES (
    echo [ERROR] The mount folder is not empty: "%MDIR%"
    echo         Empty it, or run: dism /Cleanup-Mountpoints
    exit /b 1
)
exit /b 0
