@echo off
rem ============================================================
rem  DVT - export_net_drivers.bat (Windows)
rem  Exports the drivers of the physical network adapters that are
rem  connected (status Up and a default route) into NETDRV_DIR, so
rem  make_boot.bat can add them to boot.wim.
rem  Drivers whose manufacturer or device name matches NETDRV_EXCLUDE
rem  are skipped. NETDRV_DIR is emptied first, so drivers exported on
rem  an earlier run are never added by mistake.
rem
rem  Exit codes:
rem     0 = drivers exported
rem     1 = unexpected error
rem     2 = no connected physical adapter found
rem     3 = no driver to export (all excluded or none found)
rem     4 = one or more drivers failed to export
rem    10 = not running as administrator
rem    11 = NETDRV_DIR could not be created
rem    12 = pnputil.exe not found
rem    13 = powershell.exe not found
rem ============================================================

rem ---- relaunch in 64-bit cmd when started from a 32-bit process ----
if not defined PROCESSOR_ARCHITEW6432 goto :arch_ok
if not exist "%SystemRoot%\Sysnative\cmd.exe" goto :arch_ok
"%SystemRoot%\Sysnative\cmd.exe" /c ""%~f0" %*"
exit /b
:arch_ok

rem ---- administrator check (relaunch only when run on its own) ----
reg.exe query "HKU\S-1-5-20" >nul 2>&1
if not errorlevel 1 goto :admin_ok
if defined DVT_PARENT (
    echo [ERROR] Administrator rights are required.
    exit /b 10
)
echo [INFO] Administrator rights are required. Requesting elevation...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to elevate to administrator.
    pause
    exit /b 10
)
exit /b 0
:admin_ok

setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0config.cmd"

if not exist "%PNPUTIL%" (
    echo [ERROR] pnputil.exe not found: "%PNPUTIL%"
    set "RC=12"
    goto :end
)
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] powershell.exe not found.
    set "RC=13"
    goto :end
)

rem ---- start with an empty folder ----
if exist "%NETDRV_DIR%\" rd /s /q "%NETDRV_DIR%" >nul 2>&1
mkdir "%NETDRV_DIR%" >nul 2>&1
if not exist "%NETDRV_DIR%\" (
    echo [ERROR] Could not create the driver folder: "%NETDRV_DIR%"
    set "RC=11"
    goto :end
)

rem ---- run the PowerShell part below the marker ----
rem LastIndexOf is used because the marker text also appears in this line.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=Get-Content -LiteralPath '%~f0' -Raw; $m='###PS_BEGIN###'; $i=$f.LastIndexOf($m); & ([scriptblock]::Create($f.Substring($i+$m.Length))) -BackupPath '%NETDRV_DIR%' -Exclude '%NETDRV_EXCLUDE%'"
set "RC=%errorlevel%"

if "%RC%"=="0" echo [INFO] Network drivers exported to "%NETDRV_DIR%"
if "%RC%"=="2" echo [WARN] No connected physical network adapter was found.
if "%RC%"=="3" echo [INFO] No network driver needs to be exported.
if not "%RC%"=="0" if not "%RC%"=="2" if not "%RC%"=="3" echo [ERROR] Driver export failed. Exit code: %RC%. Log: "%NETDRV_DIR%\backup.log"

:end
if not defined DVT_PARENT pause
exit /b %RC%

###PS_BEGIN###
param([string]$BackupPath, [string]$Exclude)

# Stop on any unhandled error so the catch block can report it
$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $BackupPath 'backup.log'

# Write a message to both the console and the log file
function Write-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    try { Add-Content -LiteralPath $LogFile -Value $line } catch { }
}

# True when a driver must be skipped
function Test-Excluded($Driver) {
    if ([string]::IsNullOrEmpty($Exclude)) { return $false }
    return ($Driver.Manufacturer -match $Exclude) -or ($Driver.DeviceName -match $Exclude)
}

try {
    Write-Log '--- Network driver export started ---'

    # 1) Physical adapters that are Up AND have a default route
    $adapters = @(
        Get-NetAdapter -Physical |
            Where-Object { $_.Status -eq 'Up' } |
            Where-Object {
                Get-NetRoute -InterfaceIndex $_.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
            }
    )

    if ($adapters.Count -eq 0) {
        Write-Log '[WARN] No connected physical network adapter was found.'
        exit 2
    }

    foreach ($a in $adapters) {
        Write-Log ('Connected adapter: {0} ({1})' -f $a.Name, $a.InterfaceDescription)
    }

    # PnP device IDs of the connected adapters
    $ids = @($adapters | ForEach-Object { $_.PnPDeviceID } | Where-Object { $_ })

    # 2) Installed drivers of those adapters, minus the excluded ones
    $drivers = @(
        Get-CimInstance Win32_PnPSignedDriver |
            Where-Object {
                $_.DeviceClass -eq 'NET' -and
                $ids -contains $_.DeviceID -and
                $_.InfName -and
                -not (Test-Excluded $_)
            }
    )

    if ($drivers.Count -eq 0) {
        Write-Log '[INFO] No driver to export (none found, or all excluded).'
        exit 3
    }

    # 3) Export each driver package once
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

    if ($failed -gt 0) {
        Write-Log "[ERROR] $failed driver(s) failed to export."
        exit 4
    }

    Write-Log '--- Network driver export completed ---'
    exit 0
}
catch {
    Write-Log ('[ERROR] Unexpected error: {0}' -f $_.Exception.Message)
    exit 1
}
