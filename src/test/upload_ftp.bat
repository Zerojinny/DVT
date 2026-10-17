@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT TEST - upload_ftp.bat (WinPE)
rem  Uploads one file to the FTP server set in test_config.cmd.
rem   - curl.exe is used first (passive mode by default, creates
rem     FTP_DIR when it does not exist)
rem   - ftp.exe is the fallback (active mode only, FTP_DIR must exist)
rem   - FTP_CLIENT in test_config.cmd can force one of them
rem   - up to FTP_RETRIES attempts, FTP_RETRY_SEC seconds apart
rem
rem  Usage : call upload_ftp.bat <local file> [remote name]
rem          call upload_ftp.bat /check
rem             checks the settings and the FTP client only
rem  Exit  : 0 = uploaded (or /check passed)
rem          1 = upload failed
rem          2 = no FTP client, or the local file not found
rem          3 = FTP_HOST or FTP_USER is empty
rem ============================================================

call "%~dp0config.cmd"
call "%~dp0test_config.cmd"

rem ---- settings ----
if not defined FTP_HOST (
    echo [ERROR] FTP_HOST is empty in test_config.cmd.
    exit /b 3
)
if not defined FTP_USER (
    echo [ERROR] FTP_USER is empty in test_config.cmd.
    exit /b 3
)
if not defined FTP_PORT set "FTP_PORT=21"
if not defined FTP_RETRIES set "FTP_RETRIES=3"
if not defined FTP_RETRY_SEC set "FTP_RETRY_SEC=5"
if not defined FTP_TIMEOUT_SEC set "FTP_TIMEOUT_SEC=15"
if not defined FTP_MAX_TIME_SEC set "FTP_MAX_TIME_SEC=60"

rem ---- FTP client: this folder first, then System32 ----
set "CURL=%PE_DIR%\curl.exe"
if not exist "%CURL%" set "CURL=%SystemRoot%\System32\curl.exe"
set "FTPEXE=%PE_DIR%\ftp.exe"
if not exist "%FTPEXE%" set "FTPEXE=%SystemRoot%\System32\ftp.exe"
set "CLIENT="
if /i not "%FTP_CLIENT%"=="ftp" if exist "%CURL%" set "CLIENT=curl"
if not defined CLIENT if /i not "%FTP_CLIENT%"=="curl" if exist "%FTPEXE%" set "CLIENT=ftp"
if not defined CLIENT (
    echo [ERROR] No FTP client found. FTP_CLIENT=%FTP_CLIENT%
    echo         Put curl.exe or ftp.exe in the image (make_test_pe.bat^).
    exit /b 2
)
if /i "%~1"=="/check" (
    echo [INFO] FTP client: %CLIENT%   Server: %FTP_HOST%:%FTP_PORT%
    exit /b 0
)

rem ---- local file and remote name ----
set "FILE=%~f1"
if not defined FILE (
    echo [ERROR] No file given.
    exit /b 2
)
if not exist "%FILE%" (
    echo [ERROR] File not found: "%FILE%"
    exit /b 2
)
set "NAME=%~2"
if not defined NAME set "NAME=%~nx1"

rem ---- remote folder: forward slashes, no leading or trailing slash ----
set "RDIR=%FTP_DIR%"
if defined RDIR set "RDIR=!RDIR:\=/!"
:strip_lead
if defined RDIR if "!RDIR:~0,1!"=="/" (
    set "RDIR=!RDIR:~1!"
    goto :strip_lead
)
:strip_trail
if defined RDIR if "!RDIR:~-1!"=="/" (
    set "RDIR=!RDIR:~0,-1!"
    goto :strip_trail
)
if defined RDIR (
    set "URL=ftp://%FTP_HOST%:%FTP_PORT%/!RDIR!/!NAME!"
) else (
    set "URL=ftp://%FTP_HOST%:%FTP_PORT%/!NAME!"
)

rem ---- upload with retries ----
set /a N=0
:try
set /a N+=1
echo [INFO] FTP upload attempt %N% of %FTP_RETRIES% (%CLIENT%): !NAME! -^> %FTP_HOST%
if "%CLIENT%"=="curl" (
    call :by_curl
) else (
    call :by_ftp
)
if not errorlevel 1 (
    echo [INFO] FTP upload OK: !NAME!
    exit /b 0
)
if %N% GEQ %FTP_RETRIES% (
    echo [ERROR] FTP upload failed after %N% attempts.
    exit /b 1
)
echo [WARN] Attempt %N% failed. Retrying in %FTP_RETRY_SEC% seconds...
call "%~dp0wait.bat" %FTP_RETRY_SEC%
goto :try


rem ============================================================
rem  :by_curl   exit 0 = uploaded
rem ============================================================
:by_curl
set "CURL_OPTS=--ftp-create-dirs"
if "%FTP_PASSIVE%"=="0" set "CURL_OPTS=!CURL_OPTS! -P -"
"%CURL%" -sS --connect-timeout %FTP_TIMEOUT_SEC% --max-time %FTP_MAX_TIME_SEC% !CURL_OPTS! --user "!FTP_USER!:!FTP_PASS!" -T "!FILE!" "!URL!"
set "RC=%errorlevel%"
if not "%RC%"=="0" echo [WARN] curl exit code: %RC%
exit /b %RC%


rem ============================================================
rem  :by_ftp   exit 0 = the server answered 226 (transfer complete)
rem  ftp.exe always ends with exit code 0, so the server replies
rem  in its output decide. The script holds the password and is
rem  deleted right after use.
rem ============================================================
:by_ftp
set "FTPS=%TEMP%\dvt_ftp_%RANDOM%.txt"
set "FTPL=%TEMP%\dvt_ftp_log.txt"
> "!FTPS!" (
    echo open %FTP_HOST% %FTP_PORT%
    echo user !FTP_USER! !FTP_PASS!
    echo binary
    if defined RDIR echo cd !RDIR!
    echo put "!FILE!" "!NAME!"
    echo quit
)
"%FTPEXE%" -n -i -s:"!FTPS!" > "!FTPL!" 2>&1
del /f /q "!FTPS!" >nul 2>&1
set "FTP_OK="
for /f "usebackq tokens=1,*" %%a in ("!FTPL!") do (
    set "CODE=%%a"
    if "!CODE:~0,3!"=="226" set "FTP_OK=1"
    rem show the error replies of the server (4xx / 5xx)
    if "!CODE:~3!"=="" (
        if "!CODE:~0,1!"=="4" echo [WARN] FTP: %%a %%b
        if "!CODE:~0,1!"=="5" echo [WARN] FTP: %%a %%b
    )
)
del /f /q "!FTPL!" >nul 2>&1
if defined FTP_OK exit /b 0
exit /b 1
