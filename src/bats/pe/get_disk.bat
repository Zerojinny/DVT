@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - get_disk.bat (WinPE)
rem  Finds the number of the disk that will be ERASED.
rem   1) FORCE_DISK in config.cmd, if set
rem   2) the disk whose "Disk ID" (GPT disk GUID or MBR signature)
rem      matches DISK_ID_FILE (target_disk.txt, written into the image
rem      by make_boot.bat). Disk numbers can differ between Windows and
rem      WinPE, the disk ID does not, and it can be read even when the
rem      Windows drive is locked by BitLocker.
rem   3) only when AUTO_DISK_FALLBACK=1 (the disk ID is missing or
rem      matches no disk):
rem      a) the disk of the only RAW (unformatted) volume. Instant
rem         recovery programs can make the Windows partition look RAW
rem         in WinPE and can also hide the real disk ID.
rem      b) the only disk in the PC
rem  Anything ambiguous (disk ID on several disks, several RAW volumes,
rem  several disks) is an error, so a wrong disk is never erased.
rem
rem  Returns: TARGET_DISK, TARGET_METHOD (force / disk ID /
rem           unformatted volume / only disk)
rem  Exit   : 0 = found
rem           1 = not found or ambiguous
rem ============================================================

call "%~dp0config.cmd"

set "DP_IN=%TEMP%\dvt_disk_in.txt"
set "DP_OUT=%TEMP%\dvt_disk_out.txt"
set "DISKNO="
set "METHOD="

rem ---- 1) disk number set by hand ----
if defined FORCE_DISK (
    call :is_number "%FORCE_DISK%" || (
        echo [ERROR] FORCE_DISK in config.cmd is not a number: "%FORCE_DISK%"
        goto :not_found
    )
    set "DISKNO=%FORCE_DISK%"
    set "METHOD=force"
    echo [INFO] Target disk is set in config.cmd.
    goto :found
)

rem ---- 2) disk ID written by make_boot.bat ----
if not exist "%DISK_ID_FILE%" (
    echo [WARN] "%DISK_ID_FILE%" not found.
    goto :fallback
)
set "WANT_ID="
set /p WANT_ID=<"%DISK_ID_FILE%"
if defined WANT_ID set "WANT_ID=%WANT_ID: =%"
if not defined WANT_ID (
    echo [WARN] "%DISK_ID_FILE%" is empty.
    goto :fallback
)
call :find_disk_id "%WANT_ID%"
if %IDCOUNT% GTR 1 (
    echo [ERROR] Disk ID %WANT_ID% was found on more than one disk:!IDDISKS!
    echo         Set FORCE_DISK in config.cmd.
    goto :not_found
)
if %IDCOUNT% EQU 1 (
    set "DISKNO=%IDDISK%"
    set "METHOD=disk ID"
    echo [INFO] Disk ID %WANT_ID% found on disk %IDDISK%.
    goto :found
)
echo [WARN] No disk has the ID %WANT_ID%.

:fallback
if not "%AUTO_DISK_FALLBACK%"=="1" (
    echo [ERROR] The disk ID did not identify the disk, and AUTO_DISK_FALLBACK is off.
    echo         Set FORCE_DISK in config.cmd.
    goto :not_found
)

rem ---- 3a) disk of the only RAW volume ----
echo [WARN] Looking for an unformatted volume...
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
    set "METHOD=unformatted volume"
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
    set "METHOD=only disk"
    echo [INFO] Only one disk exists in this PC.
    goto :found
)
echo [ERROR] The target disk could not be determined: %DISKCOUNT% disks found.
echo         Set FORCE_DISK in config.cmd.
goto :not_found


:found
del /f /q "%DP_IN%" "%DP_OUT%" >nul 2>&1
echo [INFO] Target disk: %DISKNO%  ^(%METHOD%^)
endlocal & set "TARGET_DISK=%DISKNO%" & set "TARGET_METHOD=%METHOD%" & exit /b 0

:not_found
del /f /q "%DP_IN%" "%DP_OUT%" >nul 2>&1
endlocal & exit /b 1


rem ============================================================
rem  :find_disk_id "<id>"
rem  Runs "detail disk" for every disk in ONE diskpart session and
rem  counts the disks whose "Disk ID:" equals <id>.
rem    GPT : {5B0E81C2-7F0A-4E5B-9B4C-1D2E3F405162}
rem    MBR : 1A2B3C4D  (leading zeros are ignored when comparing)
rem  Output lines used:
rem    "Disk 1 is now the selected disk."  -> current disk number
rem    "Disk ID: {...}"                     -> its ID
rem  Sets IDCOUNT (number of matches), IDDISK (the last match) and
rem  IDDISKS (all matches).
rem ============================================================
:find_disk_id
set "IDCOUNT=0"
set "IDDISK="
set "IDDISKS="
set "CMP_WANT=%~1"
call :strip_zeros CMP_WANT
> "%DP_IN%" echo list disk
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
set "DLIST="
for /f "usebackq tokens=1,2" %%a in ("%DP_OUT%") do (
    if /i "%%a"=="Disk" call :is_number "%%b" && set "DLIST=!DLIST! %%b"
)
if not defined DLIST exit /b 0
> "%DP_IN%" (
    for %%n in (%DLIST%) do (
        echo select disk %%n
        echo detail disk
    )
)
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
set "CURDISK="
for /f "usebackq tokens=1,2,3" %%a in ("%DP_OUT%") do (
    if /i "%%a"=="Disk" if /i "%%c"=="is" call :is_number "%%b" && set "CURDISK=%%b"
    if /i "%%a"=="Disk" if /i "%%b"=="ID:" if defined CURDISK call :id_line "%%c"
)
exit /b 0

:id_line
set "CMP_GOT=%~1"
call :strip_zeros CMP_GOT
if /i not "!CMP_GOT!"=="!CMP_WANT!" exit /b 0
set /a IDCOUNT+=1
set "IDDISK=%CURDISK%"
set "IDDISKS=!IDDISKS! %CURDISK%"
rem one ID per disk: ignore further ID lines until the next disk
set "CURDISK="
exit /b 0


rem ============================================================
rem  :strip_zeros <variable>
rem  Removes leading zeros from an MBR signature (8 hex digits), so
rem  "0012ABCD" and "12ABCD" compare equal. A GPT GUID ({...}) is
rem  left as it is.
rem ============================================================
:strip_zeros
if "!%~1:~0,1!"=="{" exit /b 0
:strip_zeros_loop
if "!%~1:~0,1!"=="0" if not "!%~1:~1!"=="" (
    set "%~1=!%~1:~1!"
    goto :strip_zeros_loop
)
exit /b 0


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
