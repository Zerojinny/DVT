setlocal enableextensions enabledelayedexpansion
rem ============================================================
rem  DVT - check_seeder.bat
rem  Checks that a seeder is reachable BEFORE the disk is wiped.
rem  It downloads only one small file (CHECKFILE) from the torrent.
rem
rem  Usage : call check_seeder.bat [path\to\DVT_backup.torrent]
rem  Return: 0 = OK (seeder reachable, check file downloaded)
rem          1 = download failed / timed out (no seeder?)
rem          2 = aria2c.exe or torrent file not found
rem          3 = check file is not contained in the torrent
rem
rem  Prerequisite:
rem   - A small file named dvt_check.txt (a few KB) must be placed
rem     inside the backup folder BEFORE creating DVT_backup.torrent,
rem     and the seeder must seed it as part of the torrent.
rem ============================================================

rem ---------- settings ----------
set "CHECKFILE=dvt_check.txt"
set "TIMEOUT_SEC=60"
set "TRIES=2"
rem Extra aria2c options (e.g. --enable-dht=false --bt-tracker=http://...)
set "EXTRA_OPTS="
rem ------------------------------

set "ARIA2=%~dp0aria2c.exe"
set "TORRENT=%~1"
if "%TORRENT%"=="" set "TORRENT=%~dp0DVT_backup.torrent"

if not exist "%ARIA2%" (
    echo [DVT] aria2c.exe not found: %ARIA2%
    set "RC=2"
    goto :done
)
if not exist "%TORRENT%" (
    echo [DVT] torrent file not found: %TORRENT%
    set "RC=2"
    goto :done
)

if defined TEMP (set "CHKDIR=%TEMP%\dvt_check") else (set "CHKDIR=%SystemDrive%\dvt_check")
if exist "%CHKDIR%" rd /s /q "%CHKDIR%" >nul 2>&1
md "%CHKDIR%\dl" >nul 2>&1

rem ---------- find file index of CHECKFILE in the torrent ----------
"%ARIA2%" --show-files "%TORRENT%" > "%CHKDIR%\files.txt" 2>nul
set "IDX="
rem (findstr is not available in WinPE, so parse with built-in commands only)
for /f "usebackq tokens=1,* delims=|" %%a in ("%CHKDIR%\files.txt") do (
    set "LINE=%%b"
    if defined LINE (
        if not "!LINE:%CHECKFILE%=!"=="!LINE!" (
            if not defined IDX set /a IDX=%%a
        )
    )
)
if not defined IDX (
    echo [DVT] %CHECKFILE% is not included in the torrent.
    set "RC=3"
    goto :cleanup
)
echo [DVT] Check file index: %IDX%

rem ---------- try to download only the check file ----------
set /a N=0
:try
set /a N+=1
echo [DVT] Checking seeder... attempt %N% of %TRIES% (timeout %TIMEOUT_SEC%s)
"%ARIA2%" --dir="%CHKDIR%\dl" --select-file=%IDX% --enable-dht=false --seed-time=0 --bt-stop-timeout=%TIMEOUT_SEC% --file-allocation=none --allow-overwrite=true --auto-file-renaming=false --console-log-level=warn --summary-interval=0 %EXTRA_OPTS% "%TORRENT%"
if not errorlevel 1 goto :verify
if %N% LSS %TRIES% goto :try
set "RC=1"
goto :cleanup

:verify
set "RC=1"
for /r "%CHKDIR%\dl" %%f in (%CHECKFILE%) do (
    if exist "%%f" if not exist "%%f.aria2" set "RC=0"
)

:cleanup
if "%RC%"=="0" (
    echo [DVT] Seeder check OK.
) else if "%RC%"=="1" (
    echo [DVT] Seeder check FAILED. Could not download from the seeder.
)
rd /s /q "%CHKDIR%" >nul 2>&1

:done
exit /b %RC%
