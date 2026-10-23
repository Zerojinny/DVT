@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - get_target.bat (WinPE, shared)
rem  bats\common: used by the client local boot and the USB / CD media.
rem  Chooses the drive that receives the torrent download.
rem   - candidates: local fixed volumes ("Partition" in diskpart)
rem     with a drive letter, except X:, the boot media (MEDIA_DRV,
rem     set by the startnet.cmd of the media) and the new S: / T:
rem     drives
rem   - with <exclude disk>: volumes on that disk are skipped too.
rem     check_space.bat uses this BEFORE the disk is erased, so a
rem     volume of the disk that will be erased is never chosen.
rem   - a candidate must have at least the torrent size free
rem   - the candidate with the most free space wins
rem   - no candidate: T: (the new Windows partition) is used
rem
rem  Usage  : call get_target.bat [path\to\DVT_backup.torrent] [exclude disk]
rem  Returns: DL_DRIVE (drive letter only, e.g. D)
rem  Exit   : 0 (always; T: is the fallback)
rem ============================================================

call "%~dp0config.cmd"

set "TOR=%~1"
if not defined TOR set "TOR=%TORRENT%"
set "DP_IN=%TEMP%\dvt_target_in.txt"
set "DP_OUT=%TEMP%\dvt_target_out.txt"
set "DP_IN2=%TEMP%\dvt_target_in2.txt"
set "DP_OUT2=%TEMP%\dvt_target_out2.txt"
set "EXCL_DISK=%~2"
if defined EXCL_DISK call :is_number "%EXCL_DISK%" || set "EXCL_DISK="

rem ---- torrent size in bytes ("Total Length: 4.0GiB (4,294,967,296)") ----
set "NEED="
set "NEED_PAD="
if exist "%ARIA2%" if exist "%TOR%" (
    "%ARIA2%" --show-files "%TOR%" > "%DP_OUT%" 2>nul
    for /f "usebackq tokens=1,* delims=:" %%a in ("%DP_OUT%") do (
        if /i "%%a"=="Total Length" for /f "tokens=2 delims=()" %%s in ("%%b") do set "NEED=%%s"
    )
)
if defined NEED (
    set "NEED=!NEED:,=!"
    call :is_number "!NEED!" || set "NEED="
)
if defined NEED (
    set "NEED_PAD=00000000000000000000!NEED!"
    set "NEED_PAD=!NEED_PAD:~-20!"
    echo [INFO] Download size: !NEED! bytes
)

rem ---- list the volumes ----
> "%DP_IN%" echo list volume
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1

set "BEST_LTR="
set "BEST_PAD="
set "BEST_FREE="
for /f "usebackq delims=" %%L in ("%DP_OUT%") do call :volume_line "%%L"
del /f /q "%DP_IN%" "%DP_OUT%" "%DP_IN2%" "%DP_OUT2%" >nul 2>&1

if defined BEST_LTR (
    echo [INFO] Download drive: %BEST_LTR%:  free %BEST_FREE% bytes
    endlocal & set "DL_DRIVE=%BEST_LTR%" & exit /b 0
)
echo [INFO] No other suitable drive. Downloading to %TDRV%:
endlocal & set "DL_DRIVE=%TDRV%" & exit /b 0


rem ============================================================
rem  :volume_line "<one line of list volume>"
rem  Line example: "  Volume 2     D   DATA    NTFS   Partition    931 GB  Healthy"
rem ============================================================
:volume_line
set "LINE= %~1 "
set "T1="
set "T2="
set "T3="
for /f "tokens=1,2,3" %%a in ("%~1") do (
    set "T1=%%a"
    set "T2=%%b"
    set "T3=%%c"
)
if /i not "%T1%"=="Volume" exit /b 0
call :is_number "%T2%" || exit /b 0

rem 3rd word must be a single drive letter
set "OK="
for %%A in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do if /i "%%A"=="%T3%" set "OK=1"
if not defined OK exit /b 0
if /i "%T3%"=="X" exit /b 0
if /i "%T3%"=="%SDRV%" exit /b 0
if /i "%T3%"=="%TDRV%" exit /b 0
if defined MEDIA_DRV if /i "%T3%"=="%MEDIA_DRV%" exit /b 0

rem only local fixed volumes (not Removable, CD-ROM, DVD-ROM)
if "!LINE: Partition =!"=="!LINE!" exit /b 0

rem never a volume of the excluded disk (the disk that will be erased)
if defined EXCL_DISK (
    call :disk_of_volume %T3%
    if not defined VOLDISK exit /b 0
    if "!VOLDISK!"=="%EXCL_DISK%" exit /b 0
)

call :free_bytes %T3%
if not defined FREE exit /b 0
set "PAD=00000000000000000000%FREE%"
set "PAD=%PAD:~-20%"

if defined NEED_PAD if "%PAD%" LSS "%NEED_PAD%" (
    echo [INFO] Drive %T3%: has not enough free space, skipped.
    exit /b 0
)
if defined BEST_PAD if not "%PAD%" GTR "%BEST_PAD%" exit /b 0
set "BEST_LTR=%T3%"
set "BEST_PAD=%PAD%"
set "BEST_FREE=%FREE%"
exit /b 0


rem ============================================================
rem  :free_bytes <letter>   sets FREE (empty when unknown)
rem  Reads the "... Dir(s)  <bytes> bytes free" line of dir.
rem ============================================================
:free_bytes
set "FREE="
for /f "usebackq delims=" %%F in (`dir /-c /a "%~1:\" 2^>nul`) do (
    set "FL=%%F"
    if not "!FL:bytes free=!"=="!FL!" for /f "tokens=3" %%n in ("%%F") do set "FREE=%%n"
)
if not defined FREE exit /b 0
call :is_number "%FREE%" || set "FREE="
exit /b 0


rem ============================================================
rem  :disk_of_volume <letter>
rem  Sets VOLDISK to the disk number of the volume (empty on error).
rem  "detail volume" prints a line like "* Disk 0   Online ...".
rem ============================================================
:disk_of_volume
set "VOLDISK="
> "%DP_IN2%" (
    echo select volume %~1
    echo detail volume
)
diskpart /s "%DP_IN2%" > "%DP_OUT2%" 2>&1
for /f "usebackq tokens=1-3" %%a in ("%DP_OUT2%") do (
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
