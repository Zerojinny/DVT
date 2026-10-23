@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - suspend_bitlocker.bat (Windows)
rem  Called by make_boot.bat (as administrator) before the one-time
rem  WinPE boot entry is added.
rem  When BitLocker protects the Windows drive, a changed boot path can
rem  make Windows ask for the recovery key the next time it starts
rem  (for example when a check fails in WinPE and the PC returns to
rem  Windows). The protection is suspended for ONE restart:
rem      manage-bde -protectors -disable C: -RebootCount 1
rem  Windows turns it back on by itself after that restart. The disk
rem  is erased by the restore anyway.
rem  BITLOCKER_SUSPEND=0 in config.cmd turns this off.
rem
rem  Usage  : call suspend_bitlocker.bat [drive]   (default: %SystemDrive%)
rem  Returns: BITLOCKER_STATE = Off / Suspended / Skipped / Unknown / Failed
rem  Exit   : 0 = nothing to do, or suspended
rem           1 = BitLocker is on and could not be suspended
rem ============================================================

call "%~dp0config.cmd"

set "DVT_DRV=%~1"
if not defined DVT_DRV set "DVT_DRV=%SystemDrive%"
set "DVT_DRV=%DVT_DRV:~0,2%"
set "STATE="

rem empty status = no BitLocker WMI provider, e.g. not in this edition
call :status
if "%PSTAT%"=="" (
    set "STATE=Unknown"
    echo [INFO] BitLocker status of %DVT_DRV% is not available. Nothing to do.
    goto :ok
)
if not "%PSTAT%"=="0" if not "%PSTAT%"=="1" (
    set "STATE=Unknown"
    echo [WARN] BitLocker status of %DVT_DRV% is unknown: %PSTAT%. Nothing was changed.
    goto :ok
)
if "%PSTAT%"=="0" (
    set "STATE=Off"
    echo [INFO] BitLocker protection is off on %DVT_DRV%.
    goto :ok
)

if not "%BITLOCKER_SUSPEND%"=="1" (
    set "STATE=Skipped"
    echo [WARN] BitLocker protects %DVT_DRV%, and BITLOCKER_SUSPEND is not 1.
    echo        If WinPE returns to Windows, it may ask for the recovery key.
    goto :ok
)

echo [INFO] BitLocker protects %DVT_DRV%. Suspending it for one restart...
if exist "%MANAGEBDE%" (
    "%MANAGEBDE%" -protectors -disable %DVT_DRV% -RebootCount 1
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Suspend-BitLocker -MountPoint '%DVT_DRV%' -RebootCount 1 | Out-Null"
)
call :status
if "%PSTAT%"=="0" (
    set "STATE=Suspended"
    echo [INFO] BitLocker is suspended until the next restart of Windows.
    goto :ok
)
set "STATE=Failed"
echo [ERROR] BitLocker could not be suspended on %DVT_DRV%.
endlocal & set "BITLOCKER_STATE=Failed" & exit /b 1

:ok
endlocal & set "BITLOCKER_STATE=%STATE%" & exit /b 0


rem ============================================================
rem  :status   PSTAT = ProtectionStatus of Win32_EncryptableVolume
rem            (0 = off, 1 = on, 2 = unknown, empty = no provider)
rem ============================================================
:status
set "PSTAT="
set "PS=$v=Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -ErrorAction Stop |"
set "PS=!PS! Where-Object { $_.DriveLetter -eq $env:DVT_DRV } | Select-Object -First 1;"
set "PS=!PS! if ($v) { Write-Output ([string]$v.ProtectionStatus) } else { Write-Output '0' }"
for /f "tokens=1" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "!PS!" 2^>nul') do set "PSTAT=%%a"
exit /b 0
