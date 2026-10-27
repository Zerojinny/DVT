@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - check_space.bat (WinPE, shared)
rem  data\common: used by the client local boot and the USB / CD media.
rem  Checks BEFORE the disk is erased that the target disk is large
rem  enough for the restore.
rem   - download size  = "Total Length" of the torrent
rem   - applied image  = APPLIED_SIZE_MB, or the download size x
rem                      APPLIED_SIZE_PCT / 100 when it is empty
rem   - download drive = get_target.bat with the target disk excluded:
rem       another drive : the new Windows partition needs the applied
rem                       image only
rem       none (T:)     : it needs the download AND the applied image
rem   - Windows partition = disk size - system partitions
rem                         - SPACE_MARGIN_MB
rem  SPACE_CHECK (config.cmd):
rem    1 = too small stops the restore before anything is erased
rem    2 = too small is only a warning
rem    0 = no check
rem  All sizes are in MiB (set /a is limited to 32-bit numbers).
rem
rem  Needs  : TARGET_DISK (get_disk.bat / get_input.bat),
rem           FIRMWARE (get_firmware.bat)
rem  Usage  : call check_space.bat [path\to\DVT_backup.torrent]
rem  Returns: SPACE_RESULT (text for reports)
rem  Exit   : 0 = enough space, check off, or size unknown (warning)
rem           1 = not enough space and SPACE_CHECK=1
rem ============================================================

call "%~dp0config.cmd"

set "TOR=%~1"
if not defined TOR set "TOR=%TORRENT%"
if not defined SPACE_CHECK set "SPACE_CHECK=1"
if not defined APPLIED_SIZE_PCT set "APPLIED_SIZE_PCT=200"
if not defined SPACE_MARGIN_MB set "SPACE_MARGIN_MB=2048"
set "DP_IN=%TEMP%\dvt_space_in.txt"
set "DP_OUT=%TEMP%\dvt_space_out.txt"
set "RES="

if "%SPACE_CHECK%"=="0" (
    set "RES=not checked (SPACE_CHECK=0)"
    goto :ok
)
call :is_number "%TARGET_DISK%" || (
    set "RES=unknown (no target disk)"
    goto :unknown
)

rem ---- 1) download size: "Total Length: 4.0GiB (4,294,967,296)" ----
set "NEED="
if exist "%ARIA2%" if exist "%TOR%" (
    "%ARIA2%" --show-files "%TOR%" > "%DP_OUT%" 2>nul
    for /f "usebackq tokens=1,* delims=:" %%a in ("%DP_OUT%") do (
        if /i "%%a"=="Total Length" for /f "tokens=2 delims=()" %%s in ("%%b") do set "NEED=%%s"
    )
)
if defined NEED set "NEED=!NEED:,=!"
call :is_number "!NEED!" || (
    set "RES=unknown (the torrent size could not be read)"
    goto :unknown
)
call :bytes_to_mib !NEED!
set "DL_MB=%MIB%"

rem ---- 2) applied image size ----
if defined APPLIED_SIZE_MB (
    call :is_number "%APPLIED_SIZE_MB%" || (
        set "RES=unknown (APPLIED_SIZE_MB is not a number: %APPLIED_SIZE_MB%)"
        goto :unknown
    )
    set "IMG_MB=%APPLIED_SIZE_MB%"
    set "IMG_HOW=APPLIED_SIZE_MB"
) else (
    call :is_number "%APPLIED_SIZE_PCT%" || set "APPLIED_SIZE_PCT=200"
    set /a "IMG_MB=DL_MB * APPLIED_SIZE_PCT / 100"
    set "IMG_HOW=%APPLIED_SIZE_PCT%%% of the download"
)

rem ---- 3) size of the target disk: "Disk 0  Online  238 GB  0 B  *" ----
set "DSIZE="
set "DUNIT="
> "%DP_IN%" echo list disk
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
for /f "usebackq tokens=1,2,4,5" %%a in ("%DP_OUT%") do (
    if /i "%%a"=="Disk" if "%%b"=="%TARGET_DISK%" for %%u in (KB MB GB TB) do if /i "%%d"=="%%u" (
        set "DSIZE=%%c"
        set "DUNIT=%%d"
    )
)
call :is_number "!DSIZE!" || (
    set "RES=unknown (the size of disk %TARGET_DISK% could not be read)"
    goto :unknown
)
if /i "%DUNIT%"=="KB" set /a "DISK_MB=DSIZE / 1024"
if /i "%DUNIT%"=="MB" set /a "DISK_MB=DSIZE"
if /i "%DUNIT%"=="GB" set /a "DISK_MB=DSIZE * 1024"
if /i "%DUNIT%"=="TB" set /a "DISK_MB=DSIZE * 1048576"

rem ---- 4) size of the new Windows partition ----
if /i "%FIRMWARE%"=="BIOS" (
    set /a "SYS_MB=BIOS_SYS_SIZE_MB"
) else (
    set /a "SYS_MB=EFI_SIZE_MB + MSR_SIZE_MB"
)
set /a "WIN_MB=DISK_MB - SYS_MB - SPACE_MARGIN_MB"

rem ---- 5) download drive (volumes of the target disk are skipped) ----
call "%~dp0get_target.bat" "%TOR%" %TARGET_DISK% >nul
set "PRE_DL=%DL_DRIVE%"
if /i "%PRE_DL%"=="%TDRV%" (
    set /a "REQ_MB=DL_MB + IMG_MB"
    set "WHERE=download and image on %TDRV%:"
) else (
    set /a "REQ_MB=IMG_MB"
    set "WHERE=download on %PRE_DL%:, image on %TDRV%:"
)

echo [INFO] Disk %TARGET_DISK%: %DSIZE% %DUNIT%  Windows partition about %WIN_MB% MB
echo [INFO] Download %DL_MB% MB, image about %IMG_MB% MB (%IMG_HOW%)
echo [INFO] Needed: %REQ_MB% MB (%WHERE%)

if %WIN_MB% GEQ %REQ_MB% (
    set "RES=OK: %REQ_MB% MB needed, about %WIN_MB% MB available (%WHERE%)"
    goto :ok
)
set "RES=TOO SMALL: %REQ_MB% MB needed, about %WIN_MB% MB available (%WHERE%)"
echo [ERROR] Disk %TARGET_DISK% is too small: %REQ_MB% MB needed, about %WIN_MB% MB available.
if "%SPACE_CHECK%"=="2" (
    echo [WARN] SPACE_CHECK=2: continuing anyway.
    goto :done
)
echo         Nothing has been erased. Use a larger disk, or set APPLIED_SIZE_MB
echo         ^(exact size^) or SPACE_CHECK in config.cmd.
del /f /q "%DP_IN%" "%DP_OUT%" >nul 2>&1
endlocal & set "SPACE_RESULT=%RES%" & exit /b 1

:unknown
echo [WARN] Disk space check skipped: %RES%

:ok
if "%SPACE_CHECK%"=="0" echo [INFO] Disk space check is off ^(SPACE_CHECK=0^).
if not "%SPACE_CHECK%"=="0" if "%RES:~0,2%"=="OK" echo [INFO] Disk space OK.

:done
del /f /q "%DP_IN%" "%DP_OUT%" >nul 2>&1
endlocal & set "SPACE_RESULT=%RES%" & exit /b 0


rem ============================================================
rem  :bytes_to_mib <bytes>   sets MIB (rounded up)
rem  The byte count can be larger than set /a allows, so the last
rem  three digits are dropped first (KB of 1000 bytes), then
rem  1 MiB = 1048.576 KB is approximated as 1048 KB (a little more
rem  than the real size).
rem ============================================================
:bytes_to_mib
set "B=%~1"
set "KB=0"
if not "%B:~3%"=="" set "KB=%B:~0,-3%"
rem remove leading zeros, so the number is not read as octal
for /f "tokens=* delims=0" %%z in ("%KB%") do set "KB=%%z"
if not defined KB set "KB=0"
set /a "MIB=KB / 1048 + 1"
exit /b 0


rem ============================================================
rem  :is_number "<value>"   exit 0 = digits only, 1 = anything else
rem ============================================================
:is_number
set "NUMTEST=%~1"
if not defined NUMTEST exit /b 1
for /f "delims=0123456789" %%z in ("%NUMTEST%") do exit /b 1
exit /b 0
