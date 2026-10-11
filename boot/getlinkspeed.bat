@echo off

rem ============================================================
rem  Detect the link speed of the NIC that owns the default route
rem  and set the variables "speed" and "linkspeed".
rem   - >= 1000 Mbps  -> speed=27
rem   - 100..999 Mbps -> speed=80
rem   - 10..99 Mbps   -> speed=40
rem   - unknown       -> speed=0 (warning, exit code 0)
rem  The speed is compared as a NUMBER (Mbps), not as text.
rem  Requires: Windows 8 / Server 2012 or later (Get-NetAdapter)
rem  ASCII only (no codepage problems).
rem ============================================================

set "linkspeed="
set "speed=0"
set "mbps="
set "psfile=%temp%\getlinkspeed_%random%.ps1"
set "outfile=%temp%\getlinkspeed_%random%.txt"

rem Build a small PowerShell script: pick the first Up, non-virtual adapter
rem that has a default route (lowest route metric first).
>"%psfile%"  echo $a = $null
>>"%psfile%" echo foreach ($r in (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue ^| Sort-Object RouteMetric)) {
>>"%psfile%" echo   $n = Get-NetAdapter -InterfaceIndex $r.ifIndex -ErrorAction SilentlyContinue
>>"%psfile%" echo   if ($n -and $n.Status -eq 'Up' -and -not $n.Virtual) { $a = $n; break }
>>"%psfile%" echo }
>>"%psfile%" echo if ($a) { [int]($a.Speed / 1000000); $a.LinkSpeed }

powershell -NoProfile -ExecutionPolicy Bypass -File "%psfile%" > "%outfile%" 2>nul

rem line 1 = speed in Mbps, line 2 = text such as "1 Gbps"
for /f "usebackq delims=" %%L in ("%outfile%") do (
    if not defined mbps (set "mbps=%%L") else set "linkspeed=%%L"
)

del "%psfile%" >nul 2>&1
del "%outfile%" >nul 2>&1

if not defined mbps (
    echo [WARNING] Could not detect the active NIC link speed. Using the 100M profile.
    set "linkspeed=unknown"
    set "speed=0"
    goto :end
)

echo Detected link speed: %linkspeed% ^(%mbps% Mbps^)

set /a MB=%mbps% 2>nul
if %MB% GEQ 1000 goto :s1000
if %MB% GEQ 100 goto :s100
if %MB% GEQ 10 goto :s10

echo [WARNING] Link speed below 10 Mbps or invalid: %linkspeed%
set "speed=0"
goto :end

:s1000
set "speed=27"
goto :end
:s100
set "speed=80"
goto :end
:s10
set "speed=40"

:end
echo speed=%speed%
exit /b 0
