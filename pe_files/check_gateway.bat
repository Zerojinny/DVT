setlocal enabledelayedexpansion

rem ===== Get the default gateway: lowest metric (same rule as get_ip.bat) =====
set "GW="
set "BEST=999999"
for /f "tokens=1-5" %%a in ('route print -4 2^>nul') do (
    if "%%a"=="0.0.0.0" if "%%b"=="0.0.0.0" if /i not "%%c"=="On-link" if not "%%e"=="" (
        set "D=%%d"
        if not "!D:.=!"=="!D!" (
            set /a M=%%e 2>nul
            if !M! LSS !BEST! (
                set "BEST=!M!"
                set "GW=%%c"
            )
        )
    )
)

if not defined GW goto :NO_GW

rem ===== Ping the gateway, up to 3 tries =====
set /a TRY=0
:PING
set /a TRY+=1
set "OK="
for /f "delims=" %%L in ('ping -n 2 -w 1000 !GW!') do (
    set "line=%%L"
    rem a real reply contains TTL; "TTL expired in transit" does not count
    if not "!line:TTL=!"=="!line!" if "!line:expired=!"=="!line!" set "OK=1"
)
if defined OK exit /b 0
if !TRY! LSS 3 (
    ping -n 3 127.0.0.1 >nul
    goto :PING
)
exit /b 1

:NO_GW
exit /b 1
