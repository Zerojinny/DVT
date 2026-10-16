@echo off
rem ============================================================
rem  DVT - make_pe.bat (Windows, run on the build PC)
rem  Location: the build folder, next to the host and pe folders.
rem  Settings come from host\config.cmd.
rem  Builds the DVT WinPE image (boot.wim) from the ADK winpe.wim:
rem   - WinPE scripts from PE_SRC_DIR       -> X:\restore
rem   - optional tools from PE_TOOLS_DIR    -> X:\restore
rem   - optional files from PE_SYS32_DIR    -> X:\Windows\System32
rem   - startnet.cmd and nircmd.exe         -> X:\Windows\System32
rem   - optional drivers from PE_DRIVERS_DIR
rem  The mount and work folders are on the local system drive, never
rem  in a folder synced by OneDrive, Dropbox, Resilio Sync etc.:
rem  sync clients can restore deleted files after the unmount.
rem  Result: OUT_DIR\boot.wim, OUT_DIR\boot.sdi and the host scripts.
rem  Copy the whole OUT_DIR folder to the client PC as C:\temp\boot.
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
    echo [ERROR] host\config.cmd not found. Run make_pe.bat from the build folder
    echo         that contains the host and pe folders.
    pause
    exit /b 1
)
call "%~dp0host\config.cmd"
rem tells the helper scripts not to pause or relaunch themselves
set "DVT_PARENT=1"
set "DVT_START=%DATE% %TIME:~0,8%"
set "MOUNTED=0"
set "HIVE_LOADED=0"
set "ERRMSG="
set "WORK_WIM=%BUILD_LOCAL%\work\winpe.wim"
set "PE_MOUNT=%BUILD_LOCAL%\mount"

echo ==============================================
echo  DVT - build the WinPE image
echo ==============================================

rem ---- [1] tools and sources ----
if not exist "%DISM%" (
    set "ERRMSG=DISM not found: %DISM%"
    goto :failed
)
for %%F in (config.cmd startnet.cmd start_dvt.bat restore.bat start_restore.bat aria2.conf.100 aria2.conf.1G) do (
    if not exist "%PE_SRC_DIR%\%%F" (
        set "ERRMSG=Missing WinPE file: %PE_SRC_DIR%\%%F"
        goto :failed
    )
)
rem the host scripts are copied to OUT_DIR at the end (step 11)
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

rem ---- [2] folders ----
for %%D in ("%SOURCE_DIR%" "%OUT_DIR%" "%BUILD_LOCAL%\work") do (
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
copy /y "%SOURCE_DIR%\boot.sdi" "%OUT_DIR%\boot.sdi" >nul
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
echo [INFO] Copying the DVT WinPE scripts...
xcopy "%PE_SRC_DIR%\*" "%PE_MOUNT%\restore\" /h /y >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy the WinPE scripts."
    goto :failed
)
copy /y "%PE_SRC_DIR%\startnet.cmd" "%PE_MOUNT%\Windows\System32\startnet.cmd" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy startnet.cmd."
    goto :failed
)
copy /y "%NIRCMD_SRC%" "%PE_MOUNT%\Windows\System32\nircmd.exe" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy nircmd.exe."
    goto :failed
)

rem the WinPE scripts need these tools in restore or System32
for %%F in (aria2c.exe wimlib-imagex.exe) do (
    if not exist "%PE_MOUNT%\restore\%%F" if not exist "%PE_MOUNT%\Windows\System32\%%F" (
        set "ERRMSG=%%F is missing. Put it in %PE_TOOLS_DIR% or %PE_SYS32_DIR%."
        goto :failed
    )
)

rem ---- [7] registry: keyboard indicators at startup ----
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

rem ---- [8] drivers for every WinPE image ----
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

rem ---- [9] save ----
echo [INFO] Saving the image...
"%DISM%" /Unmount-Image /MountDir:"%PE_MOUNT%" /Commit
if errorlevel 1 (
    set "ERRMSG=Failed to save the image."
    goto :failed
)
set "MOUNTED=0"

rem ---- [10] result ----
move /y "%WORK_WIM%" "%OUT_DIR%\boot.wim" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to move boot.wim to the output folder."
    goto :failed
)

rem ---- [11] host scripts next to boot.wim ----
rem The client PC receives the whole OUT_DIR folder as C:\temp\boot,
rem so make_boot.bat runs from the same folder as boot.wim and boot.sdi.
echo [INFO] Copying the host scripts to "%OUT_DIR%"...
xcopy "%HOST_DIR%\*" "%OUT_DIR%\" /h /r /y >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy the host scripts to the output folder."
    goto :failed
)

set "DONE_L1=WinPE image built : %OUT_DIR%\boot.wim"
set "DONE_L2=Next              : copy the folder %OUT_DIR%"
set "DONE_L3=                    to the client PC as C:\temp\boot"
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
rem  Shows DONE_L1..DONE_L3 (empty lines are skipped) and the time.
rem ============================================================
:show_done
color %COLOR_OK%
title DVT - DONE
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
title DVT - FAILED
echo.
echo.
echo  ======================================================================
echo    [FAILED] !ERRMSG!
echo  ======================================================================
echo    The messages above show the step that failed.
echo.
echo    Press any key to close this window.
exit /b 0
