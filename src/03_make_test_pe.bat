@echo off
rem ============================================================
rem  DVT TEST - make_test_pe.bat (Windows, run on the build PC)
rem  Location: the build folder, next to make_pe.bat.
rem  Settings: host\config.cmd and test\test_config.cmd.
rem
rem  Builds a TEST WinPE image from the ADK winpe.wim. On the client
rem  it checks the network, the gateway and the seeder, uploads
rem  <ip>.txt to the FTP server and reboots. It NEVER erases or
rem  writes a disk: the erase and restore scripts (make_disk.bat,
rem  restore.bat, start_restore.bat, start_dvt.bat) are not copied.
rem   - the WinPE helper scripts from PE_SRC_DIR  -> X:\restore
rem   - the test scripts from TEST_SRC_DIR        -> X:\restore
rem   - optional tools from PE_TOOLS_DIR          -> X:\restore
rem   - optional files from PE_SYS32_DIR          -> X:\Windows\System32
rem   - test\startnet.cmd and nircmd.exe          -> X:\Windows\System32
rem   - curl.exe and ftp.exe from this PC (when they are not supplied
rem     in PE_TOOLS_DIR or PE_SYS32_DIR)          -> X:\Windows\System32
rem   - optional drivers from PE_DRIVERS_DIR
rem  Result: TEST_OUT_DIR\boot.wim, boot.sdi and the host scripts.
rem  Copy the whole TEST_OUT_DIR folder to the client PC as
rem  C:\temp\boot and run make_boot.bat there, as for the normal image.
rem
rem  Exit: 0 = OK
rem        1 = failed
rem       10 = elevation failed
rem ============================================================

rem ---- relaunch in 64-bit cmd when started from a 32-bit process ----
if not defined PROCESSOR_ARCHITEW6432 goto :arch_ok
if not exist "%SystemRoot%\Sysnative\cmd.exe" goto :arch_ok
"%SystemRoot%\Sysnative\cmd.exe" /c ""%~f0" %*"
exit /b
:arch_ok

rem ---- administrator check ----
reg.exe query "HKU\S-1-5-20" >nul 2>&1
if not errorlevel 1 goto :admin_ok
echo [INFO] Administrator rights are required. Requesting elevation...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to elevate to administrator.
    pause
    exit /b 10
)
exit /b 0
:admin_ok

setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
if not exist "%~dp0host\config.cmd" (
    echo [ERROR] host\config.cmd not found. Run make_test_pe.bat from the build
    echo         folder that contains the host, pe and test folders.
    pause
    exit /b 1
)
call "%~dp0host\config.cmd"

rem ---- test image settings ----
set "TEST_SRC_DIR=%BUILD_DIR%\test"
set "TEST_OUT_DIR=%BUILD_DIR%\boot_test"
rem separate local folders, so a normal make_pe.bat run is never affected
set "WORK_WIM=%BUILD_LOCAL%\test_work\winpe.wim"
set "PE_MOUNT=%BUILD_LOCAL%\test_mount"
rem WinPE helper scripts needed by the test (nothing that erases a disk)
set "PE_FILES=config.cmd check_gateway.bat check_seeder.bat get_disk.bat get_firmware.bat get_ip.bat set_ip.bat ping_host.bat wait.bat aria2.conf.100 aria2.conf.1G"
rem test scripts copied to X:\restore (startnet.cmd goes to System32)
set "TEST_FILES=test_config.cmd start_test.bat upload_ftp.bat"

rem tells the helper scripts not to pause or relaunch themselves
set "DVT_PARENT=1"
set "DVT_START=%DATE% %TIME:~0,8%"
set "MOUNTED=0"
set "HIVE_LOADED=0"
set "ERRMSG="

echo ==============================================
echo  DVT TEST - build the test WinPE image
echo ==============================================

rem ---- [1] tools, sources and FTP settings ----
if not exist "%DISM%" (
    set "ERRMSG=DISM not found: %DISM%"
    goto :failed
)
for %%F in (%PE_FILES%) do (
    if not exist "%PE_SRC_DIR%\%%F" (
        set "ERRMSG=Missing WinPE file: %PE_SRC_DIR%\%%F"
        goto :failed
    )
)
for %%F in (%TEST_FILES% startnet.cmd) do (
    if not exist "%TEST_SRC_DIR%\%%F" (
        set "ERRMSG=Missing test file: %TEST_SRC_DIR%\%%F"
        goto :failed
    )
)
rem the host scripts are copied to TEST_OUT_DIR at the end (step 12)
for %%F in (config.cmd make_boot.bat get_host_ip.bat get_link_speed.bat export_net_drivers.bat prepare_mount_dir.bat set_bcd.bat show_ip.bat) do (
    if not exist "%HOST_DIR%\%%F" (
        set "ERRMSG=Missing host script: %HOST_DIR%\%%F"
        goto :failed
    )
)
if not exist "%NIRCMD_SRC%" (
    set "ERRMSG=nircmd.exe not found: %NIRCMD_SRC%"
    goto :failed
)
call "%TEST_SRC_DIR%\test_config.cmd"
if not defined FTP_HOST (
    set "ERRMSG=FTP_HOST is empty. Set it in %TEST_SRC_DIR%\test_config.cmd"
    goto :failed
)
if not defined FTP_USER (
    set "ERRMSG=FTP_USER is empty. Set it in %TEST_SRC_DIR%\test_config.cmd"
    goto :failed
)
echo [INFO] FTP server: %FTP_HOST%:%FTP_PORT%   User: %FTP_USER%

rem ---- [2] folders ----
for %%D in ("%SOURCE_DIR%" "%TEST_OUT_DIR%" "%BUILD_LOCAL%\test_work") do (
    if not exist "%%~D\" mkdir "%%~D" 2>nul
    if not exist "%%~D\" (
        set "ERRMSG=Failed to create folder: %%~D"
        goto :failed
    )
)

rem ---- [3] clean winpe.wim / boot.sdi from the ADK (first run only) ----
if not exist "%SOURCE_DIR%\winpe.wim" (
    if not exist "%ADK_PE_DIR%\%PE_LANG%\winpe.wim" (
        set "ERRMSG=winpe.wim not found in the ADK. Install the ADK and the WinPE add-on."
        goto :failed
    )
    copy /y "%ADK_PE_DIR%\%PE_LANG%\winpe.wim" "%SOURCE_DIR%\winpe.wim" >nul
    if errorlevel 1 (
        set "ERRMSG=Failed to copy winpe.wim from the ADK."
        goto :failed
    )
)
if not exist "%SOURCE_DIR%\boot.sdi" (
    if not exist "%ADK_PE_DIR%\Media\Boot\boot.sdi" (
        set "ERRMSG=boot.sdi not found in the ADK. Install the ADK and the WinPE add-on."
        goto :failed
    )
    copy /y "%ADK_PE_DIR%\Media\Boot\boot.sdi" "%SOURCE_DIR%\boot.sdi" >nul
    if errorlevel 1 (
        set "ERRMSG=Failed to copy boot.sdi from the ADK."
        goto :failed
    )
)

rem ---- [4] fresh work copy (after any stale mount is discarded) ----
call "%HOST_DIR%\prepare_mount_dir.bat" "%PE_MOUNT%"
if errorlevel 1 (
    set "ERRMSG=The mount folder is not usable: %PE_MOUNT%"
    goto :failed
)
copy /y "%SOURCE_DIR%\winpe.wim" "%WORK_WIM%" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy winpe.wim to the work folder."
    goto :failed
)
attrib -r "%WORK_WIM%" >nul 2>&1
copy /y "%SOURCE_DIR%\boot.sdi" "%TEST_OUT_DIR%\boot.sdi" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy boot.sdi to the output folder."
    goto :failed
)

rem ---- [5] mount ----
echo [INFO] Mounting the WinPE image...
"%DISM%" /Mount-Image /ImageFile:"%WORK_WIM%" /Index:1 /MountDir:"%PE_MOUNT%"
if errorlevel 1 (
    set "ERRMSG=Failed to mount the image."
    goto :failed
)
rem from here on, a failure must discard the mounted image
set "MOUNTED=1"

"%DISM%" /Image:"%PE_MOUNT%" /Set-ScratchSpace:%PE_SCRATCH_MB%
if errorlevel 1 (
    set "ERRMSG=Failed to set the scratch space."
    goto :failed
)

if not exist "%PE_MOUNT%\restore\" mkdir "%PE_MOUNT%\restore" 2>nul
if not exist "%PE_MOUNT%\restore\" (
    set "ERRMSG=Failed to create the restore folder in the image."
    goto :failed
)

rem ---- [6] files ----
rem order matters: optional extras first, the DVT scripts last, so an
rem old script left in an extra folder never replaces a new one
if exist "%PE_SYS32_DIR%\*" (
    echo [INFO] Copying "%PE_SYS32_DIR%" to System32...
    xcopy "%PE_SYS32_DIR%\*" "%PE_MOUNT%\Windows\System32\" /e /i /h /y >nul
    if errorlevel 1 (
        set "ERRMSG=Failed to copy the system32 files."
        goto :failed
    )
)
if exist "%PE_TOOLS_DIR%\*" (
    echo [INFO] Copying "%PE_TOOLS_DIR%" to restore...
    xcopy "%PE_TOOLS_DIR%\*" "%PE_MOUNT%\restore\" /e /i /h /y >nul
    if errorlevel 1 (
        set "ERRMSG=Failed to copy the WinPE tools."
        goto :failed
    )
)
echo [INFO] Copying the WinPE helper scripts...
for %%F in (%PE_FILES%) do (
    copy /y "%PE_SRC_DIR%\%%F" "%PE_MOUNT%\restore\%%F" >nul
    if errorlevel 1 (
        set "ERRMSG=Failed to copy %%F."
        goto :failed
    )
)
echo [INFO] Copying the test scripts...
for %%F in (%TEST_FILES%) do (
    copy /y "%TEST_SRC_DIR%\%%F" "%PE_MOUNT%\restore\%%F" >nul
    if errorlevel 1 (
        set "ERRMSG=Failed to copy %%F."
        goto :failed
    )
)
copy /y "%TEST_SRC_DIR%\startnet.cmd" "%PE_MOUNT%\Windows\System32\startnet.cmd" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy startnet.cmd."
    goto :failed
)
copy /y "%NIRCMD_SRC%" "%PE_MOUNT%\Windows\System32\nircmd.exe" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy nircmd.exe."
    goto :failed
)

rem the seeder check needs aria2c.exe in restore or System32
if not exist "%PE_MOUNT%\restore\aria2c.exe" if not exist "%PE_MOUNT%\Windows\System32\aria2c.exe" (
    set "ERRMSG=aria2c.exe is missing. Put it in %PE_TOOLS_DIR% or %PE_SYS32_DIR%."
    goto :failed
)

rem ---- [7] FTP client: curl.exe and ftp.exe ----
rem Not part of WinPE. Taken from this PC unless already supplied in
rem PE_TOOLS_DIR (-> restore) or PE_SYS32_DIR (-> System32).
call :add_tool curl.exe HAS_CURL
call :add_tool ftp.exe HAS_FTPEXE
set "HAS_FTP_MUI=0"
for %%L in (en-US %PE_LANG%) do (
    if exist "%PE_MOUNT%\Windows\System32\%%L\ftp.exe.mui" set "HAS_FTP_MUI=1"
)
if "%HAS_FTPEXE%"=="1" if "%HAS_FTP_MUI%"=="0" if exist "%SystemRoot%\System32\en-US\ftp.exe.mui" (
    if not exist "%PE_MOUNT%\Windows\System32\en-US\" mkdir "%PE_MOUNT%\Windows\System32\en-US" 2>nul
    copy /y "%SystemRoot%\System32\en-US\ftp.exe.mui" "%PE_MOUNT%\Windows\System32\en-US\ftp.exe.mui" >nul
)
if "%HAS_CURL%"=="0" if "%HAS_FTPEXE%"=="0" (
    set "ERRMSG=No FTP client: put curl.exe or ftp.exe in %PE_TOOLS_DIR%."
    goto :failed
)
if /i "%FTP_CLIENT%"=="curl" if "%HAS_CURL%"=="0" (
    set "ERRMSG=FTP_CLIENT=curl, but curl.exe is not available."
    goto :failed
)
if /i "%FTP_CLIENT%"=="ftp" if "%HAS_FTPEXE%"=="0" (
    set "ERRMSG=FTP_CLIENT=ftp, but ftp.exe is not available."
    goto :failed
)

rem ---- [8] registry: keyboard indicators at startup ----
rem InitialKeyboardIndicators = 2 turns Num Lock on.
reg load HKLM\DVT_PE_DEFAULT "%PE_MOUNT%\Windows\System32\Config\Default" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to load the registry hive of the image."
    goto :failed
)
set "HIVE_LOADED=1"
reg add "HKLM\DVT_PE_DEFAULT\Control Panel\Keyboard" /v InitialKeyboardIndicators /t REG_SZ /d 2 /f >nul
if errorlevel 1 (
    set "ERRMSG=Failed to write the registry value."
    goto :failed
)
call :unload_hive
if errorlevel 1 (
    set "ERRMSG=Failed to unload the registry hive. A handle may still be open."
    goto :failed
)

rem ---- [9] drivers for every WinPE image ----
if exist "%PE_DRIVERS_DIR%\" (
    echo [INFO] Adding drivers from "%PE_DRIVERS_DIR%"...
    "%DISM%" /Image:"%PE_MOUNT%" /Add-Driver /Driver:"%PE_DRIVERS_DIR%" /Recurse
    if errorlevel 1 (
        set "ERRMSG=Failed to add the drivers."
        goto :failed
    )
) else (
    echo [INFO] No drivers folder. Skipping driver injection.
)

rem ---- [10] save ----
echo [INFO] Saving the image...
"%DISM%" /Unmount-Image /MountDir:"%PE_MOUNT%" /Commit
if errorlevel 1 (
    set "ERRMSG=Failed to save the image."
    goto :failed
)
set "MOUNTED=0"

rem ---- [11] result ----
move /y "%WORK_WIM%" "%TEST_OUT_DIR%\boot.wim" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to move boot.wim to the output folder."
    goto :failed
)

rem ---- [12] host scripts next to boot.wim ----
rem The client PC receives the whole TEST_OUT_DIR folder as C:\temp\boot,
rem so make_boot.bat runs from the same folder as boot.wim and boot.sdi.
echo [INFO] Copying the host scripts to "%TEST_OUT_DIR%"...
xcopy "%HOST_DIR%\*" "%TEST_OUT_DIR%\" /h /r /y >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy the host scripts to the output folder."
    goto :failed
)

set "DONE_L1=Test WinPE image built : %TEST_OUT_DIR%\boot.wim"
set "DONE_L2=FTP upload to          : %FTP_HOST%:%FTP_PORT%"
set "DONE_L3=Next                   : copy %TEST_OUT_DIR% to the client PC"
set "DONE_L4=                         as C:\temp\boot and run make_boot.bat"
call :show_done
pause >nul
exit /b 0


:failed
if "%HIVE_LOADED%"=="1" reg unload HKLM\DVT_PE_DEFAULT >nul 2>&1
if "%MOUNTED%"=="1" (
    echo [INFO] Discarding the changes to the mounted image...
    "%DISM%" /Unmount-Image /MountDir:"%PE_MOUNT%" /Discard >nul 2>&1
)
call :show_failed
pause >nul
exit /b 1


rem ============================================================
rem  :add_tool <file> <result variable>
rem  Sets the result variable to 1 when the file is in the image
rem  (restore or System32), copying it from this PC's System32 when
rem  needed, and to 0 when it is not available.
rem ============================================================
:add_tool
set "%~2=0"
if exist "%PE_MOUNT%\restore\%~1" set "%~2=1"
if exist "%PE_MOUNT%\Windows\System32\%~1" set "%~2=1"
if "!%~2!"=="1" (
    echo [INFO] %~1 is already in the image.
    exit /b 0
)
if not exist "%SystemRoot%\System32\%~1" (
    echo [WARN] %~1 was not found on this PC.
    exit /b 0
)
echo [INFO] Copying %~1 from this PC...
copy /y "%SystemRoot%\System32\%~1" "%PE_MOUNT%\Windows\System32\%~1" >nul
if errorlevel 1 (
    echo [WARN] Failed to copy %~1.
    exit /b 0
)
set "%~2=1"
exit /b 0


rem ============================================================
rem  :unload_hive   up to 3 tries, a handle may close a bit later
rem ============================================================
:unload_hive
for /l %%n in (1,1,3) do (
    reg unload HKLM\DVT_PE_DEFAULT >nul 2>&1
    if not errorlevel 1 (
        set "HIVE_LOADED=0"
        exit /b 0
    )
    timeout /t 2 /nobreak >nul
)
exit /b 1


rem ============================================================
rem  :show_done   large green completion banner
rem  Shows DONE_L1..DONE_L4 (empty lines are skipped) and the time.
rem ============================================================
:show_done
color %COLOR_OK%
title DVT TEST - DONE
echo.
echo.
echo  ======================================================================
echo.
echo        #####     ####    ##    ##  ######
echo        ##  ##   ##  ##   ###   ##  ##
echo        ##  ##   ##  ##   ## ## ##  #####
echo        ##  ##   ##  ##   ##   ###  ##
echo        #####     ####    ##    ##  ######
echo.
echo  ======================================================================
echo.
if defined DONE_L1 echo    !DONE_L1!
if defined DONE_L2 echo    !DONE_L2!
if defined DONE_L3 echo    !DONE_L3!
if defined DONE_L4 echo    !DONE_L4!
echo.
echo    Started  : %DVT_START%
echo    Finished : %DATE% %TIME:~0,8%
echo.
echo  ======================================================================
echo.
echo    Press any key to close this window.
exit /b 0


rem ============================================================
rem  :show_failed   red failure banner with ERRMSG
rem ============================================================
:show_failed
color %COLOR_FAIL%
title DVT TEST - FAILED
echo.
echo.
echo  ======================================================================
echo    [FAILED] !ERRMSG!
echo  ======================================================================
echo    The messages above show the step that failed.
echo.
echo    Press any key to close this window.
exit /b 0
