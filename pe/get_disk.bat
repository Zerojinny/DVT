@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - get_disk.bat (WinPE)
rem  Finds the number of the disk that will be ERASED.
rem   1) FORCE_DISK in config.cmd, if set
rem   2) the disk of the volume that contains TAG_FILE (DVT.tag,
rem      written by make_boot.bat on the Windows drive)
rem   3) only when AUTO_DISK_FALLBACK=1:
rem      a) the disk of the only RAW (unformatted) volume, or
rem      b) the only disk in the PC
rem  Anything ambiguous (tag on several disks, several RAW volumes,
rem  several disks) is an error, so a wrong disk is never erased.
rem
rem  Returns: TARGET_DISK
rem  Exit   : 0 = found
rem           1 = not found or ambiguous
rem ============================================================

call "%~dp0config.cmd"

set "DP_IN=%TEMP%\dvt_disk_in.txt"
set "DP_OUT=%TEMP%\dvt_disk_out.txt"
set "DISKNO="

rem ---- 1) disk number set by hand ----
if defined FORCE_DISK (
    call :is_number "%FORCE_DISK%" || (
        echo [ERROR] FORCE_DISK in config.cmd is not a number: "%FORCE_DISK%"
        goto :not_found
    )
    set "DISKNO=%FORCE_DISK%"
    echo [INFO] Target disk is set in config.cmd.
    goto :found
)

rem ---- 2) disk of the volume that contains the tag file ----
set "TAGDRIVES="
for %%x in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%x:\%TAG_FILE%" set "TAGDRIVES=!TAGDRIVES! %%x"
)
if defined TAGDRIVES (
    for %%x in (!TAGDRIVES!) do (
        call :disk_of_volume %%x
        if not defined VOLDISK (
            echo [ERROR] Could not read the disk number of drive %%x:
            goto :not_found
        )
        if defined DISKNO if not "!DISKNO!"=="!VOLDISK!" (
            echo [ERROR] %TAG_FILE% was found on more than one disk. Remove the extra tag files.
            goto :not_found
        )
        set "DISKNO=!VOLDISK!"
    )
    echo [INFO] %TAG_FILE% found on drive:!TAGDRIVES!
    goto :found
)

if not "%AUTO_DISK_FALLBACK%"=="1" (
    echo [ERROR] %TAG_FILE% was not found on any drive.
    goto :not_found
)

rem ---- 3a) disk of the only RAW volume ----
echo [WARN] %TAG_FILE% was not found. Looking for an unformatted volume...
> "%DP_IN%" echo list volume
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
set "RAWVOL="
set "RAWCOUNT=0"
for /f "usebackq tokens=1,2,*" %%a in ("%DP_OUT%") do (
    if /i "%%a"=="Volume" (
        set "REST= %%c "
        if not "!REST: RAW =!"=="!REST!" if not "!REST: Partition =!"=="!REST!" (
            set "RAWVOL=%%b"
            set /a RAWCOUNT+=1
        )
    )
)
if %RAWCOUNT% GTR 1 (
    echo [ERROR] More than one unformatted volume was found. Set FORCE_DISK in config.cmd.
    goto :not_found
)
if %RAWCOUNT% EQU 1 (
    call :disk_of_volume %RAWVOL%
    if not defined VOLDISK (
        echo [ERROR] Could not read the disk number of volume %RAWVOL%.
        goto :not_found
    )
    set "DISKNO=!VOLDISK!"
    echo [INFO] Using the disk of unformatted volume %RAWVOL%.
    goto :found
)

rem ---- 3b) the only disk in the PC ----
echo [WARN] No unformatted volume was found. Checking the number of disks...
> "%DP_IN%" echo list disk
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
set "ONEDISK="
set "DISKCOUNT=0"
for /f "usebackq tokens=1,2" %%a in ("%DP_OUT%") do (
    if /i "%%a"=="Disk" call :is_number "%%b" && (
        set "ONEDISK=%%b"
        set /a DISKCOUNT+=1
    )
)
if %DISKCOUNT% EQU 1 (
    set "DISKNO=%ONEDISK%"
    echo [INFO] Only one disk exists in this PC.
    goto :found
)
echo [ERROR] The target disk could not be determined: %DISKCOUNT% disks found.
echo         Set FORCE_DISK in config.cmd.
goto :not_found


:found
del /f /q "%DP_IN%" "%DP_OUT%" >nul 2>&1
echo [INFO] Target disk: %DISKNO%
endlocal & set "TARGET_DISK=%DISKNO%" & exit /b 0

:not_found
del /f /q "%DP_IN%" "%DP_OUT%" >nul 2>&1
endlocal & exit /b 1


rem ============================================================
rem  :disk_of_volume <letter or volume number>
rem  Sets VOLDISK to the disk number of the volume (empty on error).
rem  "detail volume" prints a line like "* Disk 0   Online ...".
rem ============================================================
:disk_of_volume
set "VOLDISK="
> "%DP_IN%" (
    echo select volume %~1
    echo detail volume
)
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
for /f "usebackq tokens=1-3" %%a in ("%DP_OUT%") do (
    if /i "%%b"=="Disk" if not defined VOLDISK call :is_number "%%c" && set "VOLDISK=%%c"
)
exit /b 0


rem ============================================================
rem  :is_number "<value>"   exit 0 = digits only, 1 = anything else
rem ============================================================
:is_number
set "NUMTEST=%~1"
if not defined NUMTEST exit /b 1
for /f "delims=0123456789" %%z in ("%NUMTEST%") do exit /b 1
exit /b 0
