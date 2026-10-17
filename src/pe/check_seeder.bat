@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - check_seeder.bat (WinPE)
rem  Checks that a seeder is reachable BEFORE the disk is erased,
rem  by downloading only one small file (CHECK_FILE) from the torrent.
rem
rem  Prerequisite:
rem    A small file named dvt_check.txt (a few KB) must be placed in
rem    the DVT_backup folder (DL_NAME) BEFORE DVT_backup.torrent is created, and the
rem    seeder must seed it as part of the torrent.
rem    It must NOT be empty: a 0-byte file has nothing to download and
rem    would pass without any seeder, so it is rejected (exit 4).
rem
rem  Attempts depend on the link speed (LINK_PROFILE, set by the caller):
rem    1G  (1 Gbps or faster)            : SEEDER_TRIES_1G
rem    100 (100 Mbps or slower, unknown) : SEEDER_TRIES_100
rem
rem  Usage : call check_seeder.bat [path\to\DVT_backup.torrent]
rem  Exit  : 0 = seeder reachable, check file downloaded
rem          1 = download failed or timed out (no seeder?)
rem          2 = aria2c.exe or the torrent file not found
rem          3 = the check file is not part of the torrent
rem          4 = the check file in the torrent is empty (0 bytes)
rem ============================================================

call "%~dp0config.cmd"

set "TOR=%~1"
if not defined TOR set "TOR=%TORRENT%"

rem ---- number of attempts by link speed ----
if /i "%LINK_PROFILE%"=="1G" (
    set "SEEDER_TRIES=%SEEDER_TRIES_1G%"
    echo [INFO] Link 1 Gbps or faster: up to %SEEDER_TRIES_1G% seeder check attempts.
) else (
    set "SEEDER_TRIES=%SEEDER_TRIES_100%"
    echo [INFO] Link 100 Mbps or slower: up to %SEEDER_TRIES_100% seeder check attempts.
)

if not exist "%ARIA2%" (
    echo [ERROR] aria2c.exe not found: "%ARIA2%"
    exit /b 2
)
if not exist "%TOR%" (
    echo [ERROR] Torrent file not found: "%TOR%"
    exit /b 2
)

set "CHKDIR=%TEMP%\dvt_check"
if exist "%CHKDIR%\" rd /s /q "%CHKDIR%" >nul 2>&1
mkdir "%CHKDIR%\dl" >nul 2>&1

rem ---- index and size of CHECK_FILE in the torrent ----
rem "--show-files" lists each file as two lines:
rem     "  <index>|./DVT_backup/dvt_check.txt"
rem     "         |4.0KiB (4,096)"
"%ARIA2%" --show-files "%TOR%" > "%CHKDIR%\files.txt" 2>nul
set "IDX="
set "EXPECT="
set "GRAB="
for /f "usebackq tokens=1,* delims=|" %%a in ("%CHKDIR%\files.txt") do (
    set "LINE=%%b"
    if defined GRAB (
        set "GRAB="
        for /f "tokens=2 delims=()" %%s in ("%%b") do set "EXPECT=%%s"
    )
    if defined LINE if not defined IDX (
        if not "!LINE:%CHECK_FILE%=!"=="!LINE!" (
            set /a IDX=%%a
            set "GRAB=1"
        )
    )
)
if not defined IDX (
    echo [ERROR] %CHECK_FILE% is not included in the torrent.
    set "RC=3"
    goto :cleanup
)
if defined EXPECT set "EXPECT=!EXPECT:,=!"
if defined EXPECT for /f "delims=0123456789" %%z in ("!EXPECT!") do set "EXPECT="
rem an empty check file proves nothing: aria2c "completes" it without a peer
if "!EXPECT!"=="0" (
    echo [ERROR] %CHECK_FILE% in the torrent is empty ^(0 bytes^).
    echo         An empty file passes the check even without a seeder.
    echo         Put a file with content ^(a few KB^) in %DL_NAME% and
    echo         create the torrent again.
    set "RC=4"
    goto :cleanup
)

rem ---- download only the check file ----
rem The control file (DL_NAME.aria2) is NOT used to judge the result:
rem with --select-file aria2c keeps it, because the torrent as a whole
rem is not complete. The file size is compared instead.
if exist "%SEEDER_LOG%" del /f /q "%SEEDER_LOG%" >nul 2>&1
set /a N=0
:try
set /a N+=1
echo [INFO] Checking seeder: attempt %N% of %SEEDER_TRIES%, timeout %SEEDER_TIMEOUT_SEC%s...
"%ARIA2%" --dir="%CHKDIR%\dl" --select-file=%IDX% --enable-dht=false --seed-time=0 --bt-stop-timeout=%SEEDER_TIMEOUT_SEC% --file-allocation=none --allow-overwrite=true --auto-file-renaming=false --console-log-level=warn --summary-interval=0 --log="%SEEDER_LOG%" --log-level=notice %SEEDER_EXTRA_OPTS% "%TOR%"
set "ARIA_RC=%errorlevel%"
call :verify
if "%RC%"=="0" goto :cleanup
echo [WARN] Attempt %N% failed. aria2c exit code: %ARIA_RC%
if %N% LSS %SEEDER_TRIES% goto :try
set "RC=1"

:cleanup
if "%RC%"=="0" echo [INFO] Seeder check OK.
if "%RC%"=="1" (
    echo [ERROR] Seeder check failed. The check file could not be downloaded.
    echo         aria2c log: "%SEEDER_LOG%"
)
rd /s /q "%CHKDIR%" >nul 2>&1
exit /b %RC%


rem ============================================================
rem  :verify   RC=0 when the check file exists, is not empty and has
rem            the size listed in the torrent (existence and a size
rem            above 0 only, when the size could not be read from the
rem            torrent)
rem ============================================================
:verify
set "RC=1"
set "GOT="
for /r "%CHKDIR%\dl" %%f in (%CHECK_FILE%) do if exist "%%f" set "GOT=%%~zf"
if not defined GOT (
    echo [WARN] %CHECK_FILE% was not downloaded.
    exit /b 0
)
if "%GOT%"=="0" (
    echo [WARN] %CHECK_FILE% is empty ^(0 bytes^).
    exit /b 0
)
if defined EXPECT if not "%GOT%"=="%EXPECT%" (
    echo [WARN] %CHECK_FILE% is incomplete: %GOT% of %EXPECT% bytes.
    exit /b 0
)
set "RC=0"
exit /b 0
