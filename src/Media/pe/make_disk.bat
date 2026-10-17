@echo off
setlocal EnableExtensions
rem ============================================================
rem  DVT media - make_disk.bat (WinPE)
rem  ERASES the target disk and creates the Windows partitions.
rem   UEFI : GPT -> EFI (FAT32, S:) + MSR + Windows (NTFS, T:)
rem   BIOS : MBR -> System (NTFS, active, S:) + Windows (NTFS, T:)
rem  Drive letters S: and T: are first removed from any other volume.
rem
rem  Needs : TARGET_DISK (get_disk.bat), FIRMWARE (get_firmware.bat)
rem  Exit  : 0 = OK
rem          1 = diskpart failed or the new drives are missing
rem          2 = TARGET_DISK is not set
rem ============================================================

call "%~dp0config.cmd"

if not defined TARGET_DISK (
    echo [ERROR] TARGET_DISK is not set.
    exit /b 2
)
if not defined FIRMWARE set "FIRMWARE=UEFI"

set "DP_IN=%TEMP%\dvt_make_disk.txt"
set "DP_LOG=%TEMP%\dvt_make_disk.log"
set "DP_PREP_LOG=%TEMP%\dvt_make_disk_prep.log"

echo [INFO] Erasing disk %TARGET_DISK% and creating %FIRMWARE% partitions...

rem ---- 1) preparation: free S: / T:, bring the disk online ----
rem These steps fail normally (no volume S: yet, disk already online).
rem "noerr" lets diskpart continue, but its exit code still reports the
rem failure, so this run is separate and its exit code is ignored.
> "%DP_IN%" (
    echo select volume %SDRV% noerr
    echo remove letter=%SDRV% noerr
    echo select volume %TDRV% noerr
    echo remove letter=%TDRV% noerr
    echo select disk %TARGET_DISK% noerr
    echo online disk noerr
    echo attributes disk clear readonly noerr
    echo exit
)
diskpart /s "%DP_IN%" > "%DP_PREP_LOG%" 2>&1

rem ---- 2) partitioning: no "noerr", so the exit code is reliable ----
> "%DP_IN%" (
    echo select disk %TARGET_DISK%
    echo clean
)
if /i "%FIRMWARE%"=="BIOS" goto :layout_bios

:layout_uefi
>> "%DP_IN%" (
    echo convert gpt
    echo create partition efi size=%EFI_SIZE_MB%
    echo format quick fs=fat32 label="System"
    echo assign letter=%SDRV%
    echo create partition msr size=%MSR_SIZE_MB%
    echo create partition primary
    echo format quick fs=ntfs label="Windows"
    echo assign letter=%TDRV%
    echo exit
)
goto :run

:layout_bios
>> "%DP_IN%" (
    echo convert mbr
    echo create partition primary size=%BIOS_SYS_SIZE_MB%
    echo format quick fs=ntfs label="System"
    echo assign letter=%SDRV%
    echo active
    echo create partition primary
    echo format quick fs=ntfs label="Windows"
    echo assign letter=%TDRV%
    echo exit
)

:run
diskpart /s "%DP_IN%" > "%DP_LOG%" 2>&1
set "RC=%errorlevel%"
del /f /q "%DP_IN%" >nul 2>&1

if not "%RC%"=="0" (
    echo [ERROR] diskpart failed with exit code %RC%.
    goto :show_log
)
if not exist "%TDRV%:\" (
    echo [ERROR] Drive %TDRV%: was not created.
    goto :show_log
)
if not exist "%SDRV%:\" (
    echo [ERROR] Drive %SDRV%: was not created.
    goto :show_log
)

echo [INFO] Partitions created: %SDRV%: system, %TDRV%: Windows
exit /b 0


:show_log
echo ---- diskpart output: "%DP_LOG%" ----
type "%DP_LOG%"
echo ---- end of diskpart output ----
echo         Preparation log: "%DP_PREP_LOG%"
exit /b 1
