@echo off

REM ---- WOW64 fix: relaunch in 64-bit cmd when started from 32-bit cmd ----
REM A 32-bit cmd on 64-bit Windows redirects System32 to SysWOW64, where
REM pnputil.exe does not exist. PROCESSOR_ARCHITEW6432 is defined only in a
REM 32-bit process on 64-bit Windows, so the 64-bit child will not loop.
if defined PROCESSOR_ARCHITEW6432 (
    if exist "%SystemRoot%\Sysnative\cmd.exe" (
        "%SystemRoot%\Sysnative\cmd.exe" /c ""%~f0" %*"
        exit /b %errorlevel%
    )
)


setlocal

REM ==========================================================
REM  Backup drivers of physical network adapters that are
REM  actually connected to a network (Realtek adapters excluded).
REM
REM  Exit codes:
REM    0 = success
REM    1 = unexpected error
REM    2 = no connected physical adapter found
REM    3 = no matching driver found
REM    4 = one or more drivers failed to export
REM   10 = failed to elevate to administrator
REM   11 = failed to create backup folder
REM   12 = pnputil.exe not found
REM   13 = PowerShell not found
REM ==========================================================

REM ---- Configuration ----
set "BACKUP=%~dp0netdrv"

REM ---- Check administrator rights; relaunch elevated if needed ----
reg.exe query "HKU\S-1-5-20" >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator rights required. Requesting elevation...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Failed to elevate to administrator.
        pause
        exit /b 10
    )
    exit /b 0
)

REM ---- Check required tools ----
where pnputil.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] pnputil.exe was not found.
    pause
    exit /b 12
)
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] powershell.exe was not found.
    pause
    exit /b 13
)

REM ---- Recreate the backup folder (remove drivers left from previous runs) ----
if exist "%BACKUP%" rd /s /q "%BACKUP%" >nul 2>&1
mkdir "%BACKUP%" >nul 2>&1
if not exist "%BACKUP%" (
    echo [ERROR] Failed to create backup folder: %BACKUP%
    pause
    exit /b 11
)

REM ---- Run the embedded PowerShell script below the marker ----
REM (LastIndexOf is used because the marker text also appears in this line)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=Get-Content -LiteralPath '%~f0' -Raw; $m='###PS_BEGIN###'; $i=$f.LastIndexOf($m); & ([scriptblock]::Create($f.Substring($i+$m.Length))) -BackupPath '%BACKUP%'"
set "RC=%errorlevel%"

REM Exit code 3 (no matching driver): the error message was already printed
REM by the PowerShell script, so just exit without extra output or pause
if %RC% equ 3 exit /b 3

if %RC% neq 0 (
    echo [ERROR] Backup finished with errors. Exit code: %RC%
    echo See log: %BACKUP%\backup.log
    pause
    exit /b %RC%
)

echo Backup completed successfully: %BACKUP%
exit /b 0

###PS_BEGIN###
param([string]$BackupPath)

# Stop on any unhandled error so the catch block can report it
$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $BackupPath 'backup.log'

# Write a message to both the console and the log file
function Write-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    try { Add-Content -LiteralPath $LogFile -Value $line } catch { }
}

try {
    Write-Log '--- Network driver backup started ---'

    # 1) Find physical adapters that are Up AND have a default route
    #    (i.e. adapters actually connected to a network)
    $adapters = @(
        Get-NetAdapter -Physical |
            Where-Object { $_.Status -eq 'Up' } |
            Where-Object {
                Get-NetRoute -InterfaceIndex $_.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
            }
    )

    if ($adapters.Count -eq 0) {
        Write-Log '[ERROR] No connected physical network adapter was found.'
        exit 2
    }

    foreach ($a in $adapters) {
        Write-Log ('Connected adapter: {0} ({1})' -f $a.Name, $a.InterfaceDescription)
    }

    # PnP device IDs of the connected adapters
    $ids = @($adapters | ForEach-Object { $_.PnPDeviceID } | Where-Object { $_ })

    # 2) Match the adapters to installed drivers (case-insensitive),
    #    skipping Realtek devices and drivers without an INF name
    $drivers = @(
        Get-CimInstance Win32_PnPSignedDriver |
            Where-Object {
                $_.DeviceClass -eq 'NET' -and
                $ids -contains $_.DeviceID -and
                $_.Manufacturer -notmatch 'Realtek' -and
                $_.DeviceName   -notmatch 'Realtek' -and
                $_.InfName
            }
    )

    if ($drivers.Count -eq 0) {
        Write-Log '[ERROR] No matching driver found (or all matches were excluded).'
        exit 3
    }

    # 3) Export each unique driver package with pnputil
    $failed = 0
    foreach ($inf in ($drivers | Select-Object -ExpandProperty InfName -Unique)) {
        Write-Log "Exporting driver: $inf"
        $out = & pnputil.exe /export-driver $inf $BackupPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            $failed++
            Write-Log ('[ERROR] pnputil failed for {0} (exit code {1}): {2}' -f $inf, $LASTEXITCODE, ($out -join ' '))
        } else {
            Write-Log "[OK] $inf exported."
        }
    }

    # 4) Final result
    if ($failed -gt 0) {
        Write-Log "[ERROR] $failed driver(s) failed to export."
        exit 4
    }

    Write-Log '--- Backup completed successfully ---'
    exit 0
}
catch {
    # Any unexpected exception ends up here
    Write-Log ('[ERROR] Unexpected error: {0}' -f $_.Exception.Message)
    exit 1
}
