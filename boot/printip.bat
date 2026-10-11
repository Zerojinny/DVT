@echo off
setlocal enabledelayedexpansion

:: ===== 0. Console size =====
mode con: cols=120 lines=30

:: ===== 1. Get the IP address =====
:: Static: first line of ip.txt.  DHCP (no ip.txt): current IP of the default-route adapter.
set "localIP="
set "ISDHCP="
set "IPFILE=c:\temp\ip.txt"
if not exist "%IPFILE%" set "IPFILE=%~dp0ip.txt"
if exist "%IPFILE%" set /p localIP=<"%IPFILE%"
if not defined localIP call :GETDHCPIP
if not defined localIP goto NOFILE

:: ===== 2. Last octet =====
set "LAST="
for /f "tokens=4 delims=." %%d in ("%localIP%") do set "LAST=%%d"
if not defined LAST goto NOFILE

:: ===== 3. Number of digits (N) =====
set "N=1"
if not "%LAST:~1,1%"=="" set "N=2"
if not "%LAST:~2,1%"=="" set "N=3"

:: ===== 4. 5x7 bitmap font =====
call :setBitmap 0 01110 10001 10001 10001 10001 10001 01110
call :setBitmap 1 00100 01100 00100 00100 00100 00100 01110
call :setBitmap 2 01110 10001 00001 00010 00100 01000 11111
call :setBitmap 3 11111 00010 00100 00010 00001 10001 01110
call :setBitmap 4 00010 00110 01010 10010 11111 00010 00010
call :setBitmap 5 11111 10000 11110 00001 00001 10001 01110
call :setBitmap 6 00110 01000 10000 11110 10001 10001 01110
call :setBitmap 7 11111 00001 00010 00100 01000 01000 01000
call :setBitmap 8 01110 10001 10001 01110 10001 10001 01110
call :setBitmap 9 01110 10001 10001 01111 00001 00010 01100

:: ===== 5. Scale to the window size =====
set /a WINDOW_W=120
set /a WINDOW_H=30
set /a HEADER_ROWS=7
set /a HEIGHT_BUDGET=WINDOW_H-HEADER_ROWS
set /a HS=HEIGHT_BUDGET/7
if %HS% LSS 1 set "HS=1"

set /a BASE_WIDTH=(6*N)-1
set /a WS=WINDOW_W/BASE_WIDTH
if %WS% LSS 1 set "WS=1"

:: Keep the aspect ratio: horizontal scale is at most 2x the vertical scale
set /a WS_MAX=HS*2
if %WS% GTR %WS_MAX% set "WS=%WS_MAX%"

:: ===== 6. Pre-build cell strings =====
set "HASHCELL="
set "SPACECELL="
for /l %%i in (1,1,%WS%) do (
    set "HASHCELL=!HASHCELL!#"
    set "SPACECELL=!SPACECELL! "
)
set "GAP=%SPACECELL%"

:: Left padding for centering
set /a USED_WIDTH=BASE_WIDTH*WS
set /a PAD=(WINDOW_W-USED_WIDTH)/2
if %PAD% LSS 0 set "PAD=0"
set "PADSTR="
for /l %%i in (1,1,%PAD%) do set "PADSTR=!PADSTR! "

:: ===== 7. Header =====
cls
if defined ISDHCP (
    echo IP Address : %localIP% ^(DHCP^)
) else (
    echo IP Address : %localIP%
)
echo.

:: ===== 8. Print the big digits =====
for /l %%r in (1,1,7) do (
    set "ROWNUM=%%r"
    set "LINE="
    for /l %%i in (0,1,2) do (
        if %%i LSS %N% (
            if %%i GTR 0 set "LINE=!LINE!!GAP!"
            set "CH=!LAST:~%%i,1!"
            call set "BROW=%%D_!CH!_!ROWNUM!%%"
            for /l %%c in (0,1,4) do (
                set "BIT=!BROW:~%%c,1!"
                if "!BIT!"=="1" (
                    set "LINE=!LINE!!HASHCELL!"
                ) else (
                    set "LINE=!LINE!!SPACECELL!"
                )
            )
        )
    )
    for /l %%h in (1,1,%HS%) do (
        echo(!PADSTR!!LINE!
    )
)

echo.
exit /b 0

:NOFILE
:: No IP address could be determined at all
cls
echo IP Address : not found ^(no static IP file and no default route^)
echo.
exit /b 0

:GETDHCPIP
:: Current IP of the adapter that owns the best (lowest metric) default route
set "ISDHCP=1"
set "BEST=999999"
for /f "tokens=1-5" %%a in ('route print -4 2^>nul') do (
    if "%%a"=="0.0.0.0" if "%%b"=="0.0.0.0" (
        set "GWX=%%c"
        set "IFX=%%d"
        if /i not "!GWX!"=="On-link" if not "!IFX:.=!"=="!IFX!" (
            if %%e LSS !BEST! (
                set "BEST=%%e"
                set "localIP=%%d"
            )
        )
    )
)
exit /b 0

:setBitmap
set "D_%1_1=%2"
set "D_%1_2=%3"
set "D_%1_3=%4"
set "D_%1_4=%5"
set "D_%1_5=%6"
set "D_%1_6=%7"
set "D_%1_7=%8"
goto :eof
