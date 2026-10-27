@echo off
rem ============================================================
rem  DVT media - getdiskinfo.bat (WinPE)
rem  Shows every disk with its volumes, file systems, type and model,
rem  so the operator can choose the disk to erase.
rem  Copy of Media\getdiskinfo.bat (diskpart only).
rem
rem  Usage : call getdiskinfo.bat
rem  Exit  : 0
rem ============================================================
setlocal EnableExtensions EnableDelayedExpansion

rem ===== If DEBUG=1, show the raw diskpart output and parsing state on screen =====
set "DEBUG=0"

set "TMPD=%TEMP%"
if not defined TMPD set "TMPD=%SystemDrive%\Windows\Temp"
if not exist "%TMPD%" md "%TMPD%"
set "DPS=%TMPD%\dp_cmd.txt"
set "DPL=%TMPD%\dp_list.txt"
set "DPD=%TMPD%\dp_detail.txt"

echo.
echo Scanning disks...

rem ---- 1) disk list ----
echo list disk> "%DPS%"
diskpart /s "%DPS%" > "%DPL%" 2>&1

rem ---- 2) header ----
echo.
set "o1=Disk" & set "o2=Ltr" & set "o3=Label" & set "o4=FS" & set "o5=Size"
set "o6=Info" & set "o7=Type" & set "o8=Model"
call :OUT
echo ---------------------------------------------------------------------------------------------

rem ---- 3) per-disk detail ----
set "cnt=0"
for /f "usebackq tokens=2,5" %%A in ("%DPL%") do call :CHKDISK "%%A" "%%B"

if "%cnt%"=="0" (
    echo No disk found.
    echo diskpart may have failed. Make sure you are running as Administrator.
)
echo.

if "%DEBUG%"=="1" (
    echo Temp file location: %TMPD%
) else (
    del "%DPS%" "%DPL%" "%DPD%" >nul 2>&1
)
endlocal
exit /b 0


rem =====================================================
:CHKDISK
set "ok=0"
if /i "%~2"=="KB" set "ok=1"
if /i "%~2"=="MB" set "ok=1"
if /i "%~2"=="GB" set "ok=1"
if /i "%~2"=="TB" set "ok=1"
if "!ok!"=="0" exit /b
set /a cnt+=1
(echo select disk %~1& echo detail disk)> "%DPS%"
diskpart /s "%DPS%" > "%DPD%" 2>&1
call :PARSE %~1
exit /b


rem =====================================================
:PARSE
set "DN=%~1"
set "MODEL=" & set "DTYPE=" & set "n=0" & set "hdr=0" & set "vc=0"
for /f "usebackq delims=" %%L in ("%DPD%") do (
    set "line=%%L"
    call :LINE
)
if "%DEBUG%"=="1" echo [DEBUG] disk !DN!: n=!n! hdr=!hdr! vc=!vc! MODEL=[!MODEL!] TYPE=[!DTYPE!]
if "!vc!"=="0" (
    set "f2=" & set "f3=" & set "f4=" & set "f6=" & set "f8="
    call :ROW
)
exit /b

rem =====================================================
:LINE
rem -- Empty lines are skipped by for /f. Counting non-empty lines only:
rem    1-3 banner, 4 "Disk N is now the selected disk", 5 model, 6 Disk ID, 7 Type
set /a n+=1
if !n! LEQ 7 (
    if !n!==5 (
        set "MODEL=!line!"
        call :TRIM MODEL
    )
    if !n!==7 (
        for /f "tokens=1,* delims=:" %%a in ("!line!") do set "DTYPE=%%b"
        call :TRIM DTYPE
    )
    exit /b
)
rem -- Find the separator line (---) of the volume table and compute column positions
if "!hdr!"=="0" (
    if "!line:~0,4!"=="  --" call :COLS
    exit /b
)
rem -- Volume rows start with two spaces
if not "!line:~0,2!"=="  " exit /b

call set "f2=%%line:~!st2!,!ln2!%%"
call set "f3=%%line:~!st3!,!ln3!%%"
call set "f4=%%line:~!st4!,!ln4!%%"
call set "f6=%%line:~!st6!,!ln6!%%"
call set "f8=%%line:~!st8!%%"
for %%i in (2 3 4 6 8) do call :TRIM f%%i
set /a vc+=1
call :ROW
exit /b

rem =====================================================
:COLS
set "hdr=1"
set "rest=!line:~2!"
set "c=0" & set "pos=2"
for %%D in (!rest!) do (
    set /a c+=1
    set "st!c!=!pos!"
    call :STRLEN "%%D"
    set "ln!c!=!SL!"
    set /a pos+=SL+2
)
exit /b

:STRLEN
set "_s=%~1"
set "SL=0"
:STRLEN_L
if defined _s (
    set "_s=!_s:~1!"
    set /a SL+=1
    goto :STRLEN_L
)
exit /b

rem =====================================================
:ROW
rem f2=Ltr f3=Label f4=FS f6=Size f8=Info
set "o1=!DN!" & set "o2=!f2!" & set "o3=!f3!" & set "o4=!f4!"
set "o5=!f6!" & set "o6=!f8!" & set "o7=!DTYPE!" & set "o8=!MODEL!"
call :OUT
exit /b

:OUT
for %%i in (1 2 3 4 5 6 7 8) do if not defined o%%i set "o%%i=-"
call :PAD o1 4
call :PAD o2 3
call :PAD o3 24
call :PAD o4 6
call :PAD o5 10
call :PAD o6 10
call :PAD o7 8
echo !o1!  !o2!  !o3!  !o4!  !o5!  !o6!  !o7!  !o8!
exit /b

:PAD
set "_p=!%1!                                        "
call set "%1=%%_p:~0,%2%%"
exit /b

:TRIM
set "_v=!%1!"
set "%1="
for /f "tokens=* delims= " %%a in ("!_v!") do set "%1=%%a"
:TRIM_R
if not defined %1 exit /b
if "!%1:~-1!"==" " (
    set "%1=!%1:~0,-1!"
    goto :TRIM_R
)
exit /b
