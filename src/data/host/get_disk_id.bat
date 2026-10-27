@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - get_disk_id.bat (Windows)
rem  Reads the identity of the disk that holds a drive (default: the
rem  Windows drive). make_boot.bat writes the ID into boot.wim, and
rem  WinPE (get_disk.bat) erases the disk whose diskpart "Disk ID"
rem  matches it.
rem    GPT : disk GUID       e.g. {5B0E81C2-7F0A-4E5B-9B4C-1D2E3F405162}
rem    MBR : disk signature  e.g. 1A2B3C4D  (8 hex digits)
rem  Both are written in the same form as diskpart shows them.
rem  PowerShell is used (this runs in Windows, not in WinPE), so the
rem  result does not depend on the language of Windows.
rem
rem  Usage  : call get_disk_id.bat [drive]   (default: %SystemDrive%)
rem  Returns: HOST_DISK_NO, HOST_DISK_STYLE (GPT / MBR / RAW),
rem           HOST_DISK_ID (empty when unknown), HOST_DISK_NAME
rem  Exit   : 0 = disk ID found
rem           1 = the disk or its ID could not be read
rem ============================================================

call "%~dp0config.cmd"

set "DVT_DRV=%~1"
if not defined DVT_DRV set "DVT_DRV=%SystemDrive%"
set "DNO="
set "DSTYLE="
set "DID="
set "DNAME="

set "PS=$l=$env:DVT_DRV.Substring(0,1); $id='';"
set "PS=!PS! $p=Get-Partition -DriveLetter $l -ErrorAction Stop;"
set "PS=!PS! $d=Get-Disk -Number $p.DiskNumber -ErrorAction Stop;"
set "PS=!PS! if ([string]$d.PartitionStyle -eq 'GPT') { $id=[string]$d.Guid; if ($id -and $id -notlike '{*') { $id='{'+$id+'}' } }"
set "PS=!PS! elseif ([string]$d.PartitionStyle -eq 'MBR') { $id='{0:X8}' -f [uint32]$d.Signature };"
set "PS=!PS! Write-Output ([string]$d.Number + ';' + [string]$d.PartitionStyle + ';' + $id.ToUpper() + ';' + [string]$d.FriendlyName)"

for /f "tokens=1-3,* delims=;" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "!PS!" 2^>nul') do (
    set "DNO=%%a"
    set "DSTYLE=%%b"
    set "DID=%%c"
    set "DNAME=%%d"
)

if not defined DNO (
    echo [WARN] Could not read the disk of drive %DVT_DRV%.
    goto :fail
)
if not defined DID (
    echo [WARN] Disk %DNO% ^(%DSTYLE%^) has no disk ID.
    goto :fail
)
rem an all-zero MBR signature or GUID cannot identify a disk
set "ZTEST=!DID:0=!"
set "ZTEST=!ZTEST:-=!"
set "ZTEST=!ZTEST:{=!"
set "ZTEST=!ZTEST:}=!"
if not defined ZTEST (
    echo [WARN] Disk %DNO% has an empty disk ID: %DID%
    goto :fail
)

echo [INFO] Windows disk: %DNO%  %DSTYLE%  ID %DID%  !DNAME!
endlocal & set "HOST_DISK_NO=%DNO%" & set "HOST_DISK_STYLE=%DSTYLE%" & set "HOST_DISK_ID=%DID%" & set "HOST_DISK_NAME=%DNAME%" & exit /b 0

:fail
endlocal & set "HOST_DISK_NO=%DNO%" & set "HOST_DISK_STYLE=%DSTYLE%" & set "HOST_DISK_ID=" & set "HOST_DISK_NAME=%DNAME%" & exit /b 1
