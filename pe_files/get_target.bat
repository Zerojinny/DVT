
setlocal DisableDelayedExpansion

rem ============================================================
rem  Find the local drive with the most free space.
rem  Only local fixed drives are candidates. Removable media,
rem  CD/DVD and network drives are ignored.
rem    Normal Windows : exclude C:         fallback = c:\temp
rem    WinPE          : exclude T: S: X:   fallback = T
rem  Returns: TARGET, TARGET_PATH, TARGET_BYTES
rem  Prints nothing except error messages (to stderr).
rem ============================================================

rem --- detect WinPE ---
set "ISPE="
reg query "HKLM\SYSTEM\CurrentControlSet\Control\MiniNT" >nul 2>&1 && set "ISPE=1"
if /i "%SystemDrive%"=="X:" set "ISPE=1"

if defined ISPE (
    set "EXCLUDE=T X S"
    set "FALLBACK=T"
    set "FALLBACK_PATH=T:\"
) else (
    set "EXCLUDE=C"
    set "FALLBACK=c:\temp"
    set "FALLBACK_PATH=c:\temp"
)

rem --- administrator check on normal Windows only ---
if not defined ISPE (
    fltmc >nul 2>&1 || (
        >&2 echo [ERROR] Run this as Administrator.
        endlocal & exit /b 1
    )
)

rem --- reference drive type text: the system drive is always a fixed drive.
rem     Comparing against it keeps this independent of the Windows language.
rem     In WinPE the English word "Fixed" is checked instead.
set "REFTYPE="
if not defined ISPE (
    for /f "tokens=1,* delims=-" %%a in ('fsutil fsinfo drivetype %SystemDrive% 2^>nul') do (
        if not defined REFTYPE for /f "tokens=*" %%t in ("%%b") do set "REFTYPE=%%t"
    )
)

if not defined TEMP set "TEMP=%SystemRoot%"
set "DPS=%TEMP%\dp_in.txt"
set "DPO=%TEMP%\dp_out.txt"
set "LETTERS="
set "VOLROWS=0"

rem --- step 1: collect drive letters from diskpart output ---
> "%DPS%" echo list volume
diskpart /s "%DPS%" > "%DPO%" 2>&1

for /f "usebackq delims=" %%L in ("%DPO%") do (
    set "LINE=%%L"
    call :parseline
)
del "%DPS%" "%DPO%" >nul 2>&1

if "%VOLROWS%"=="0" (
    >&2 echo [ERROR] Could not read the volume list from diskpart.
    endlocal & exit /b 1
)

rem --- no candidate besides the excluded drives: use fallback ---
if not defined LETTERS goto :fallback

rem --- step 2: compare free space of each candidate ---
setlocal EnableDelayedExpansion
set "BEST_LTR="
set "BEST_RAW="
set "BEST="

for %%D in (%LETTERS%) do (
    call :getfree %%D
    if defined FREE (
        rem 32-bit limit: compare as 20-digit zero-padded strings
        set "PAD=00000000000000000000!FREE!"
        set "PAD=!PAD:~-20!"
        set "NEWBEST="
        if not defined BEST_LTR set "NEWBEST=1"
        if "!PAD!" gtr "!BEST!" set "NEWBEST=1"
        if defined NEWBEST (
            set "BEST=!PAD!"
            set "BEST_LTR=%%D"
            set "BEST_RAW=!FREE!"
        )
    )
)

if not defined BEST_LTR endlocal & goto :fallback

endlocal & endlocal & set "TARGET=%BEST_LTR%" & set "TARGET_PATH=%BEST_LTR%:\" & set "TARGET_BYTES=%BEST_RAW%"
exit /b 0


:fallback
endlocal & set "TARGET=%FALLBACK%" & set "TARGET_PATH=%FALLBACK_PATH%" & set "TARGET_BYTES="
exit /b 0


rem ============================================================
rem  One line of "list volume": add the drive letter to LETTERS.
rem  2nd word = number, 3rd word = single letter A-Z.
rem  Excluded letters and non-local drives are skipped.
rem ============================================================
:parseline
set "T2="
set "T3="
for /f "tokens=1,2,3" %%a in ("%LINE%") do (
    set "T2=%%b"
    set "T3=%%c"
)
if not defined T3 goto :eof

rem skip the line if the 2nd word is not a number
for /f "delims=0123456789" %%z in ("%T2%") do goto :eof

set /a VOLROWS+=1

set "OK="
for %%A in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do if /i "%%A"=="%T3%" set "OK=1"
for %%E in (%EXCLUDE%) do if /i "%%E"=="%T3%" set "OK="
if not defined OK goto :eof

call :islocal %T3%
if defined ISLOCAL set "LETTERS=%LETTERS% %T3%"
goto :eof


rem ============================================================
rem  Set ISLOCAL=1 if drive %1 is a local fixed drive.
rem  If the drive type cannot be determined, the drive is kept.
rem ============================================================
:islocal
set "ISLOCAL=1"
set "DT="
for /f "tokens=1,* delims=-" %%a in ('fsutil fsinfo drivetype %1: 2^>nul') do (
    if not defined DT for /f "tokens=*" %%t in ("%%b") do set "DT=%%t"
)
if not defined DT goto :eof

if defined ISPE (
    if /i not "%DT:~0,5%"=="Fixed" set "ISLOCAL="
) else if defined REFTYPE (
    if /i not "%DT%"=="%REFTYPE%" set "ISLOCAL="
)
goto :eof


rem ============================================================
rem  Set FREE to the free bytes of drive %1 (undefined on failure)
rem ============================================================
:getfree
set "FREE="
set "DRV=%1:"

rem method 1: fsutil (first line is the total free bytes)
for /f "tokens=1,* delims=:" %%a in ('fsutil volume diskfree %DRV% 2^>nul') do (
    if not defined FREE for /f "tokens=1" %%n in ("%%b") do set "FREE=%%n"
)
call :cleannum

rem method 2: last line of dir
if not defined FREE (
    for /f "tokens=3" %%n in ('dir /-c /a %DRV%\ 2^>nul') do set "FREE=%%n"
    call :cleannum
)
goto :eof

:cleannum
if not defined FREE goto :eof
set "FREE=!FREE:,=!"
set "FREE=!FREE:.=!"
if not defined FREE goto :eof
for /f "delims=0123456789" %%z in ("!FREE!") do set "FREE="
goto :eof
