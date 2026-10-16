@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - show_ip.bat (Windows)
rem  Shows the IP address, and its last octet in large digits, so
rem  the PC can be identified from across the room.
rem
rem  Usage : call show_ip.bat [ip-address]
rem          Without an argument the address is read from IP_FILE.
rem  Exit  : 0 = shown
rem          2 = no IP address available
rem  Note  : the console is resized to 120x30, which clears it.
rem ============================================================

call "%~dp0config.cmd"

rem ---- 1) the address ----
set "LOCALIP=%~1"
if not defined LOCALIP if exist "%IP_FILE%" set /p LOCALIP=<"%IP_FILE%"
if not defined LOCALIP (
    echo [WARN] No IP address to show.
    exit /b 2
)

rem ---- 2) last octet: 1 to 3 digits, otherwise text only ----
set "LAST="
for /f "tokens=4 delims=." %%d in ("%LOCALIP%") do set "LAST=%%d"
set "DIGITS=1"
if not defined LAST set "DIGITS="
if defined LAST for /f "delims=0123456789" %%z in ("%LAST%") do set "DIGITS="
if defined LAST if not "%LAST:~3,1%"=="" set "DIGITS="

mode con: cols=120 lines=30
cls
echo IP Address : %LOCALIP%
echo.
if not defined DIGITS exit /b 0

rem ---- 3) number of digits (N) ----
set "N=1"
if not "%LAST:~1,1%"=="" set "N=2"
if not "%LAST:~2,1%"=="" set "N=3"

rem ---- 4) 5x7 bitmap font ----
call :set_bitmap 0 01110 10001 10001 10001 10001 10001 01110
call :set_bitmap 1 00100 01100 00100 00100 00100 00100 01110
call :set_bitmap 2 01110 10001 00001 00010 00100 01000 11111
call :set_bitmap 3 11111 00010 00100 00010 00001 10001 01110
call :set_bitmap 4 00010 00110 01010 10010 11111 00010 00010
call :set_bitmap 5 11111 10000 11110 00001 00001 10001 01110
call :set_bitmap 6 00110 01000 10000 11110 10001 10001 01110
call :set_bitmap 7 11111 00001 00010 00100 01000 01000 01000
call :set_bitmap 8 01110 10001 10001 01110 10001 10001 01110
call :set_bitmap 9 01110 10001 10001 01111 00001 00010 01100

rem ---- 5) scale to the window ----
set /a WINDOW_W=120
set /a WINDOW_H=30
set /a HEADER_ROWS=7
set /a HEIGHT_BUDGET=WINDOW_H-HEADER_ROWS
set /a HS=HEIGHT_BUDGET/7
if %HS% LSS 1 set "HS=1"

set /a BASE_WIDTH=(6*N)-1
set /a WS=WINDOW_W/BASE_WIDTH
if %WS% LSS 1 set "WS=1"

rem keep the digits from getting too wide (width : height at most 2 : 1)
set /a WS_MAX=HS*2
if %WS% GTR %WS_MAX% set "WS=%WS_MAX%"

rem ---- 6) cell strings ----
set "HASHCELL="
set "SPACECELL="
for /l %%i in (1,1,%WS%) do (
    set "HASHCELL=!HASHCELL!#"
    set "SPACECELL=!SPACECELL! "
)
set "GAP=%SPACECELL%"

rem left padding to center the digits
set /a USED_WIDTH=BASE_WIDTH*WS
set /a PAD=(WINDOW_W-USED_WIDTH)/2
if %PAD% LSS 0 set "PAD=0"
set "PADSTR="
for /l %%i in (1,1,%PAD%) do set "PADSTR=!PADSTR! "

rem ---- 7) draw ----
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


rem ============================================================
rem  :set_bitmap <digit> <row1> ... <row7>
rem ============================================================
:set_bitmap
set "D_%1_1=%2"
set "D_%1_2=%3"
set "D_%1_3=%4"
set "D_%1_4=%5"
set "D_%1_5=%6"
set "D_%1_6=%7"
set "D_%1_7=%8"
exit /b 0
