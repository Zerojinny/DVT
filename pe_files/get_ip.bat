
setlocal enabledelayedexpansion

set "MYIP="
set /a TRY=0

:RETRY
set "BEST=999999"

rem ---- Step 1: default route (0.0.0.0 / 0.0.0.0) from route print ----
rem Active route columns: Destination(a) Netmask(b) Gateway(c) Interface IP(d) Metric(e)
rem Persistent Routes lines have text (no ".") in column d, so they are filtered out below
for /f "tokens=1-5" %%a in ('route print -4 2^>nul') do (
    if "%%a"=="0.0.0.0" if "%%b"=="0.0.0.0" (
        set "GW=%%c"
        set "IFIP=%%d"
        if /i not "!GW!"=="On-link" if not "!IFIP:.=!"=="!IFIP!" (
            if %%e LSS !BEST! (
                set "BEST=%%e"
                set "MYIP=%%d"
            )
        )
    )
)
if defined MYIP goto FOUND

rem ---- Step 2 (fallback): ipconfig - adapter with an IPv4 address and an IPv4 gateway ----
rem The IPv4 gateway may be on the line AFTER an IPv6 gateway (no label), so it is tracked.
set "TMPIP="
set "INGW="
for /f "tokens=1,* delims=:" %%a in ('ipconfig 2^>nul') do (
    set "L=%%a"
    set "V=%%b"
    set "HANDLED="
    if not "!L:adapter=!"=="!L!" (
        set "TMPIP="
        set "INGW="
        set "HANDLED=1"
    )
    if not defined HANDLED if not "!L:IPv4=!"=="!L!" (
        for /f "tokens=1" %%i in ("!V!") do set "TMPIP=%%i"
        set "TMPIP=!TMPIP:(Preferred)=!"
        set "INGW="
        set "HANDLED=1"
    )
    if not defined HANDLED if not "!L:Default Gateway=!"=="!L!" (
        set "HANDLED=1"
        set "INGW=1"
        if not "!V:.=!"=="!V!" call :SETGW
    )
    if not defined HANDLED if defined INGW if "!V!"=="" if not "!L:.=!"=="!L!" call :SETGW
    if not defined HANDLED if not "!V!"=="" set "INGW="
)
if defined MYIP goto FOUND

rem ---- Wait for DHCP and retry (max 30 times, about 1 minute) ----
set /a TRY+=1
if %TRY% GEQ 30 goto FAIL
ping -n 3 127.0.0.1 >nul
goto RETRY

:SETGW
if defined TMPIP if not defined MYIP set "MYIP=!TMPIP!"
exit /b 0

:FOUND
echo Active IP : %MYIP%
goto END

:FAIL
echo [ERROR] No adapter with a default gateway was found. (DHCP failed?)
echo.
echo Press any key to Reboot!
pause >nul
wpeutil reboot
endlocal
exit /b 1

:END
endlocal & set "IP=%MYIP%"
exit /b 0
