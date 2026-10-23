@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - get_link_speed.bat (Windows)
rem  Reads the link speed of the adapter that owns IP address %1
rem  (without an argument: the adapter used for the default route)
rem  and chooses the aria2 profile and the console color.
rem    >= 1 Gbps    : LINK_PROFILE=1G   LINK_COLOR=COLOR_LINK_1G
rem    >= 100 Mbps  : LINK_PROFILE=100  LINK_COLOR=COLOR_LINK_100M
rem    slower/unknown: LINK_PROFILE=100 LINK_COLOR=COLOR_LINK_SLOW
rem  The speed is compared as a number (bits per second), not as
rem  text, so "10 Mbps" can never match "100 Mbps".
rem
rem  Usage  : call get_link_speed.bat [ip-address]
rem  Returns: LINK_SPEED (text), LINK_BPS, LINK_PROFILE, LINK_COLOR
rem  Exit   : 0 = speed detected
rem           2 = speed unknown (the slow defaults are returned)
rem ============================================================

call "%~dp0config.cmd"

set "DVT_IP=%~1"
set "BPS="
set "TEXT="

rem ---- PowerShell: adapter of the IP (or of the default route) ----
set "PS=$i=$env:DVT_IP; $x=$null;"
set "PS=!PS! if ($i) { $a=Get-NetIPAddress -IPAddress $i -ErrorAction SilentlyContinue | Select-Object -First 1; if ($a) { $x=$a.InterfaceIndex } };"
set "PS=!PS! if (-not $x) { $r=Find-NetRoute -RemoteIPAddress 8.8.8.8 -ErrorAction SilentlyContinue | Select-Object -First 1; if ($r) { $x=$r.InterfaceIndex } };"
set "PS=!PS! if ($x) { $n=Get-NetAdapter -InterfaceIndex $x -ErrorAction SilentlyContinue; if ($n) { Write-Output ([string]$n.ReceiveLinkSpeed + ';' + $n.LinkSpeed) } }"

for /f "tokens=1,* delims=;" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "!PS!" 2^>nul') do (
    set "BPS=%%a"
    set "TEXT=%%b"
)

set "PROFILE=100"
set "COLOR=%COLOR_LINK_SLOW%"
set "RC=2"

if defined BPS for /f "delims=0123456789" %%z in ("%BPS%") do set "BPS="
if not defined BPS (
    set "TEXT=unknown"
    echo [WARN] Could not detect the link speed. Using the 100 Mbps settings.
    goto :done
)

set "PAD=00000000000000000000%BPS%"
set "PAD=%PAD:~-20%"
set "RC=0"
if "%PAD%" GEQ "00000000001000000000" (
    set "PROFILE=1G"
    set "COLOR=%COLOR_LINK_1G%"
) else if "%PAD%" GEQ "00000000000100000000" (
    set "COLOR=%COLOR_LINK_100M%"
) else (
    echo [WARN] Slow link: %TEXT%. Using the 100 Mbps settings.
)
echo [INFO] Link speed: %TEXT%  aria2 profile: %PROFILE%

:done
endlocal & set "LINK_SPEED=%TEXT%" & set "LINK_BPS=%BPS%" & set "LINK_PROFILE=%PROFILE%" & set "LINK_COLOR=%COLOR%" & exit /b %RC%
