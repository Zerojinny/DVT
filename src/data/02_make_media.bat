@echo off
rem ============================================================
rem  DVT media - 02_make_media.bat (Windows, run on the build PC)
rem  Location: <build>\data, next to 01_make_pe.bat and the Media,
rem  host and pe folders.
rem  Settings come from data\Media\config.cmd (and data\host\config.cmd).
rem  Makes a DVT boot USB drive or CD (ISO) that works without
rem  make_boot.bat on the client PC:
rem   1) stores the ADK files once: the WinPE Media folder in
rem      source\adk_media, oscdimg / boot sectors / bootsect in
rem      source\adk_tools (later runs use only the stored copies)
rem   2) checks data\Media\pe\link.exe (64-bit, copied with data\Media\pe)
rem   3) builds the media image from the clean ADK winpe.wim:
rem        pe_tools\*, data\Media\pe\* and data\common\*  -> X:\restore
rem        data\Media\pe\startnet.cmd, nircmd -> X:\Windows\System32
rem        drivers, Num Lock
rem      (the pe folder and _output\boot\boot.wim of 01_make_pe.bat are not used)
rem      If _output\media\boot.wim already exists, asks first:
rem        Y = build a new image, N = use the existing image as it is
rem   4) assembles the media files: source\adk_media,
rem      sources\boot.wim and config\ (data\Media\config, plus
rem      data\Media\pe\config.cmd so the WinPE settings can be changed on
rem      a USB drive without rebuilding)
rem   5) writes them as:
rem        iso    : _output\media\DVT_media.iso (UEFI + BIOS)
rem        usb    : ERASES a USB drive, USB_FS (FAT32), USB_PART_MB
rem                 (empty = whole disk), bootable
rem        update : copies the files to a DVT USB drive (no format)
rem
rem  Usage: 02_make_media.bat [iso ^| usb ^| update]   (no argument = menu)
rem  Exit : 0 = OK
rem         1 = failed
rem         2 = cancelled
rem        10 = elevation failed
rem ============================================================

chcp 65001

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
if "%~1"=="" (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
) else (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs" >nul 2>&1
)
if errorlevel 1 (
    echo [ERROR] Failed to elevate to administrator.
    pause
    exit /b 10
)
exit /b 0
:admin_ok

setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
if not exist "%~dp0Media\config.cmd" (
    echo [ERROR] Media\config.cmd not found. Run 02_make_media.bat from the data
    echo         folder that contains the Media and host folders.
    pause
    exit /b 1
)
call "%~dp0Media\config.cmd"
rem tells the helper scripts not to pause or relaunch themselves
set "DVT_PARENT=1"
set "DVT_START=%DATE% %TIME:~0,8%"
set "MOUNTED=0"
set "HIVE_LOADED=0"
set "ERRMSG="
set "WORK_WIM=%MEDIA_WORK%\boot.wim"
set "DP_IN=%MEDIA_WORK%\dp_in.txt"
set "DP_OUT=%MEDIA_WORK%\dp_out.txt"

echo ==============================================
echo  DVT %DVT_VERSION% - make a boot USB drive or CD
echo ==============================================

rem ---- [0] mode ----
set "MODE=%~1"
if defined MODE goto :mode_check
echo.
echo  1 = ISO file for a CD / DVD   (_output\media\DVT_media.iso)
echo  2 = USB drive, ERASED and made bootable
echo  3 = update the files on an existing DVT USB drive
echo.
set "CH="
set /p "CH=Select 1-3 (empty = cancel) = "
if "%CH%"=="1" set "MODE=iso"
if "%CH%"=="2" set "MODE=usb"
if "%CH%"=="3" set "MODE=update"
if not defined MODE (
    echo [INFO] Cancelled.
    pause
    exit /b 2
)
:mode_check
set "OKMODE="
for %%M in (iso usb update) do if /i "%MODE%"=="%%M" set "OKMODE=%%M"
if not defined OKMODE (
    set "ERRMSG=Unknown mode: %MODE%. Use iso, usb or update."
    goto :failed
)
set "MODE=%OKMODE%"

rem ---- [0b] rebuild or reuse the existing media image ----
set "REBUILD=1"
if not exist "%MEDIA_WIM%" goto :rebuild_set
set "WIM_TIME="
set "WIM_SIZE="
for %%W in ("%MEDIA_WIM%") do (
    set "WIM_TIME=%%~tW"
    set "WIM_SIZE=%%~zW"
)
echo.
echo  An existing media image was found:
echo    File     : %MEDIA_WIM%
echo    Modified : !WIM_TIME!
echo    Size     : !WIM_SIZE! bytes
echo.
echo  Y = build a new image (changes in pe_tools, data and drivers are applied)
echo  N = use the existing image as it is (faster)
:rebuild_ask
set "ANS="
set /p "ANS=Build a new boot.wim? (Y/N) = "
if /i "!ANS!"=="Y" goto :rebuild_set
if /i "!ANS!"=="N" (
    set "REBUILD=0"
    echo [INFO] The existing "!MEDIA_WIM!" will be used.
    goto :rebuild_set
)
echo [WARN] Type Y or N.
goto :rebuild_ask
:rebuild_set

rem ---- [1] tools and sources ----
rem the build tools and image files are checked only when the image is built
if "%REBUILD%"=="0" goto :reuse_checks
if not exist "%DISM%" (
    set "ERRMSG=DISM not found: %DISM%"
    goto :failed
)
for %%F in (config.cmd startnet.cmd start_media.bat get_input.bat getdiskinfo.bat) do (
    if not exist "%MEDIA_PE_DIR%\%%F" (
        set "ERRMSG=Missing media script: %MEDIA_PE_DIR%\%%F"
        goto :failed
    )
)
for %%F in (%PE_COMMON_FILES%) do (
    if not exist "%PE_COMMON_DIR%\%%F" (
        set "ERRMSG=Missing shared WinPE file: %PE_COMMON_DIR%\%%F"
        goto :failed
    )
)
rem scripts left in data\Media\pe from before data\common existed
set "DUPDIR=%MEDIA_PE_DIR%"
for %%F in ("%PE_COMMON_DIR%\*") do (
    if exist "!DUPDIR!\%%~nxF" echo [WARN] %%~nxF is in data\common and in "!DUPDIR!". The data\common copy is used; delete the other one.
)
if not exist "%NIRCMD_SRC%" (
    set "ERRMSG=nircmd.exe not found: %NIRCMD_SRC%"
    goto :failed
)
goto :checks_common
:reuse_checks
rem the existing image is used: only the files of the media itself are needed
for %%F in (config.cmd getdiskinfo.bat) do (
    if not exist "%MEDIA_PE_DIR%\%%F" (
        set "ERRMSG=Missing media script: %MEDIA_PE_DIR%\%%F"
        goto :failed
    )
)
:checks_common
for %%F in (aria2.conf.100 aria2.conf.1G) do (
    if not exist "%MEDIA_CONFIG_DIR%\%%F" (
        set "ERRMSG=Missing file: %MEDIA_CONFIG_DIR%\%%F"
        goto :failed
    )
)
if not exist "%MEDIA_CONFIG_DIR%\DVT_backup.torrent" (
    echo [WARN] %MEDIA_CONFIG_DIR%\DVT_backup.torrent not found.
    echo        Copy it to the config folder of the media before booting a PC.
)
rem DHCP or static IP is detected by WinPE at boot, not here.
rem ip.txt is only needed on a static network.
if not exist "%MEDIA_CONFIG_DIR%\ip.txt" (
    echo [INFO] config\ip.txt not found. The media works only on DHCP networks.
)

rem ---- [2] folders ----
for %%D in ("%SOURCE_DIR%" "%MEDIA_OUT_DIR%" "%MEDIA_WORK%" "%MEDIA_TOOLS_DIR%") do (
    if not exist "%%~D\" mkdir "%%~D" 2>nul
    if not exist "%%~D\" (
        set "ERRMSG=Failed to create folder: %%~D"
        goto :failed
    )
)

rem ---- [3] stored ADK files (copied from the ADK on the first run) ----
if not exist "%MEDIA_FILES_DIR%\bootmgr" (
    if not exist "%ADK_MEDIA_DIR%\bootmgr" (
        set "ERRMSG=%MEDIA_FILES_DIR% is empty and the ADK media files were not found: %ADK_MEDIA_DIR%"
        goto :failed
    )
    echo [INFO] Storing the ADK media files in "%MEDIA_FILES_DIR%"...
    xcopy "%ADK_MEDIA_DIR%\*" "%MEDIA_FILES_DIR%\" /e /i /h /y >nul
    if errorlevel 1 (
        set "ERRMSG=Failed to copy the ADK media files."
        goto :failed
    )
)
for %%F in (oscdimg.exe etfsboot.com) do (
    if not exist "%MEDIA_TOOLS_DIR%\%%F" if exist "%ADK_OSCDIMG_DIR%\%%F" (
        echo [INFO] Storing %%F in "%MEDIA_TOOLS_DIR%"...
        copy /y "%ADK_OSCDIMG_DIR%\%%F" "%MEDIA_TOOLS_DIR%\%%F" >nul
    )
)
rem UEFI boot sector of the ISO: efisys_noprompt.bin renamed to efisys.bin
rem (no "Press any key to boot from CD or DVD"). The prompting efisys.bin
rem of the ADK is not used.
if exist "%MEDIA_TOOLS_DIR%\efisys_noprompt.bin" (
    echo [INFO] Renaming efisys_noprompt.bin to efisys.bin in "%MEDIA_TOOLS_DIR%"...
    move /y "%MEDIA_TOOLS_DIR%\efisys_noprompt.bin" "%EFISYS%" >nul
    if errorlevel 1 (
        set "ERRMSG=Failed to rename efisys_noprompt.bin to efisys.bin."
        goto :failed
    )
) else if not exist "%EFISYS%" if exist "%ADK_OSCDIMG_DIR%\efisys_noprompt.bin" (
    echo [INFO] Storing efisys_noprompt.bin as efisys.bin in "%MEDIA_TOOLS_DIR%"...
    copy /y "%ADK_OSCDIMG_DIR%\efisys_noprompt.bin" "%EFISYS%" >nul
)
if not exist "%BOOTSECT%" if exist "%ADK_BOOTSECT%" (
    echo [INFO] Storing bootsect.exe in "%MEDIA_TOOLS_DIR%"...
    copy /y "%ADK_BOOTSECT%" "%BOOTSECT%" >nul
)
if "%MODE%"=="iso" (
    for %%F in ("%OSCDIMG%" "%ETFSBOOT%" "%EFISYS%") do (
        if not exist "%%~F" (
            set "ERRMSG=Not found: %%~F  Copy it from the Oscdimg folder of the ADK Deployment Tools."
            goto :failed
        )
    )
)

rem the existing image is used: skip the image build ([4] and [5])
if "%REBUILD%"=="0" goto :media_files

rem clean winpe.wim from the ADK (shared with 01_make_pe.bat, never modified)
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

rem ---- [4] link.exe (used as it is, not built here) ----
if not exist "%LINK_EXE%" (
    set "ERRMSG=link.exe not found: %LINK_EXE%  Put the 64-bit link.exe in data\Media\pe."
    goto :failed
)
echo [INFO] Using "%LINK_EXE%"

rem ---- [5] media image: clean winpe.wim + pe_tools + data\Media\pe ----
call "%HOST_DIR%\prepare_mount_dir.bat" "%MEDIA_MOUNT%"
if errorlevel 1 (
    set "ERRMSG=The mount folder is not usable: %MEDIA_MOUNT%"
    goto :failed
)
copy /y "%SOURCE_DIR%\winpe.wim" "%WORK_WIM%" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy winpe.wim to the work folder."
    goto :failed
)
attrib -r "%WORK_WIM%" >nul 2>&1

echo [INFO] Mounting the WinPE image...
"%DISM%" /Mount-Image /ImageFile:"%WORK_WIM%" /Index:1 /MountDir:"%MEDIA_MOUNT%"
if errorlevel 1 (
    set "ERRMSG=Failed to mount the image."
    goto :failed
)
rem from here on, a failure must discard the mounted image
set "MOUNTED=1"

"%DISM%" /Image:"%MEDIA_MOUNT%" /Set-ScratchSpace:%PE_SCRATCH_MB%
if errorlevel 1 (
    set "ERRMSG=Failed to set the scratch space."
    goto :failed
)
set "RESTORE_DIR=%MEDIA_MOUNT%\restore"
if not exist "%RESTORE_DIR%\" mkdir "%RESTORE_DIR%" 2>nul
if not exist "%RESTORE_DIR%\" (
    set "ERRMSG=Failed to create the restore folder in the image."
    goto :failed
)

rem order matters: tools first, the media scripts last
if exist "%PE_SYS32_DIR%\*" (
    echo [INFO] Copying "%PE_SYS32_DIR%" to System32...
    xcopy "%PE_SYS32_DIR%\*" "%MEDIA_MOUNT%\Windows\System32\" /e /i /h /y >nul
    if errorlevel 1 (
        set "ERRMSG=Failed to copy the system32 files."
        goto :failed
    )
)
if exist "%PE_TOOLS_DIR%\*" (
    echo [INFO] Copying "%PE_TOOLS_DIR%" to restore...
    xcopy "%PE_TOOLS_DIR%\*" "%RESTORE_DIR%\" /e /i /h /y >nul
    if errorlevel 1 (
        set "ERRMSG=Failed to copy the WinPE tools."
        goto :failed
    )
)
echo [INFO] Copying the media scripts...
xcopy "%MEDIA_PE_DIR%\*" "%RESTORE_DIR%\" /h /r /y >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy the media scripts."
    goto :failed
)
rem shared scripts last: they replace an old copy left in data\Media\pe
xcopy "%PE_COMMON_DIR%\*" "%RESTORE_DIR%\" /h /r /y >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy the shared WinPE scripts."
    goto :failed
)
copy /y "%MEDIA_PE_DIR%\startnet.cmd" "%MEDIA_MOUNT%\Windows\System32\startnet.cmd" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy startnet.cmd."
    goto :failed
)
copy /y "%NIRCMD_SRC%" "%MEDIA_MOUNT%\Windows\System32\nircmd.exe" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy nircmd.exe."
    goto :failed
)
for %%F in (aria2c.exe wimlib-imagex.exe) do (
    if not exist "%RESTORE_DIR%\%%F" if not exist "%MEDIA_MOUNT%\Windows\System32\%%F" (
        set "ERRMSG=%%F is missing. Put it in %PE_TOOLS_DIR% or %PE_SYS32_DIR%."
        goto :failed
    )
)

rem registry: InitialKeyboardIndicators = 2 turns Num Lock on
reg load HKLM\DVT_MEDIA_DEFAULT "%MEDIA_MOUNT%\Windows\System32\Config\Default" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to load the registry hive of the image."
    goto :failed
)
set "HIVE_LOADED=1"
reg add "HKLM\DVT_MEDIA_DEFAULT\Control Panel\Keyboard" /v InitialKeyboardIndicators /t REG_SZ /d 2 /f >nul
if errorlevel 1 (
    set "ERRMSG=Failed to write the registry value."
    goto :failed
)
call :unload_hive
if errorlevel 1 (
    set "ERRMSG=Failed to unload the registry hive. A handle may still be open."
    goto :failed
)

if exist "%PE_DRIVERS_DIR%\" (
    echo [INFO] Adding drivers from "%PE_DRIVERS_DIR%"...
    "%DISM%" /Image:"%MEDIA_MOUNT%" /Add-Driver /Driver:"%PE_DRIVERS_DIR%" /Recurse
    if errorlevel 1 (
        set "ERRMSG=Failed to add the drivers."
        goto :failed
    )
) else (
    echo [INFO] No drivers folder. Skipping driver injection.
)

echo [INFO] Saving the image...
"%DISM%" /Unmount-Image /MountDir:"%MEDIA_MOUNT%" /Commit
if errorlevel 1 (
    set "ERRMSG=Failed to save the image."
    goto :failed
)
set "MOUNTED=0"
move /y "%WORK_WIM%" "%MEDIA_WIM%" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to move boot.wim to %MEDIA_OUT_DIR%."
    goto :failed
)

rem ---- [6] media files ----
:media_files
echo [INFO] Assembling the media files...
if exist "%MEDIA_STAGE%\" rd /s /q "%MEDIA_STAGE%"
if exist "%MEDIA_STAGE%\" (
    set "ERRMSG=Failed to empty %MEDIA_STAGE%"
    goto :failed
)
xcopy "%MEDIA_FILES_DIR%\*" "%MEDIA_STAGE%\" /e /i /h /y >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy the media files from %MEDIA_FILES_DIR%."
    goto :failed
)
mkdir "%MEDIA_STAGE%\sources" 2>nul
copy /y "%MEDIA_WIM%" "%MEDIA_STAGE%\sources\boot.wim" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy boot.wim to the media files."
    goto :failed
)
rem startnet.cmd finds the media by \sources\boot.wim and \config
mkdir "%MEDIA_STAGE%\config" 2>nul
for %%F in (ip.txt aria2.conf.100 aria2.conf.1G DVT_backup.torrent) do (
    if exist "%MEDIA_CONFIG_DIR%\%%F" (
        copy /y "%MEDIA_CONFIG_DIR%\%%F" "%MEDIA_STAGE%\config\%%F" >nul
        if errorlevel 1 (
            set "ERRMSG=Failed to copy config\%%F"
            goto :failed
        )
    )
)
rem WinPE settings: startnet.cmd copies <media>\config to X:\restore, so
rem this copy replaces the config.cmd inside boot.wim at every boot
copy /y "%MEDIA_PE_DIR%\config.cmd" "%MEDIA_STAGE%\config\config.cmd" >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy config.cmd to config\"
    goto :failed
)

if "%MODE%"=="iso" goto :make_iso
if "%MODE%"=="usb" goto :make_usb
goto :update_usb


rem ============================================================
rem  ISO (CD / DVD), UEFI and BIOS
rem ============================================================
:make_iso
echo [INFO] Creating "%MEDIA_ISO%"...
if exist "%MEDIA_ISO%" del /f /q "%MEDIA_ISO%"
"%OSCDIMG%" -m -o -u1 -udfver102 -l%MEDIA_LABEL% -bootdata:2#p0,e,b"%ETFSBOOT%"#pEF,e,b"%EFISYS%" "%MEDIA_STAGE%" "%MEDIA_ISO%"
if errorlevel 1 (
    set "ERRMSG=oscdimg failed."
    goto :failed
)
if not exist "%MEDIA_ISO%" (
    set "ERRMSG=The ISO file was not created."
    goto :failed
)
set "DONE_L1=ISO file created : %MEDIA_ISO%  (DVT %DVT_VERSION%)"
set "DONE_L2=Next             : burn it to a CD / DVD"
set "DONE_L3=config\ is on the disc: change data\Media\config and rebuild to update it"
goto :done


rem ============================================================
rem  USB drive: ERASED, one partition (USB_FS, USB_PART_MB), active
rem ============================================================
:make_usb
echo.
call "%MEDIA_PE_DIR%\getdiskinfo.bat"
set "UDISK="
set /p "UDISK=Number of the USB disk to ERASE (empty = cancel) = "
if not defined UDISK (
    echo [INFO] Cancelled.
    goto :cancel
)
set "UDISK=!UDISK: =!"
call :is_number "!UDISK!" || (
    set "ERRMSG=Not a disk number: !UDISK!"
    goto :failed
)

rem -- size from "list disk": 2nd word = number, 4th = size, 5th = unit --
set "USIZE="
set "UUNIT="
> "%DP_IN%" echo list disk
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
for /f "usebackq tokens=2,4,5" %%a in ("%DP_OUT%") do (
    if "%%a"=="!UDISK!" for %%u in (KB MB GB TB) do if /i "%%c"=="%%u" (
        set "USIZE=%%b"
        set "UUNIT=%%c"
    )
)
if not defined UUNIT (
    set "ERRMSG=Disk !UDISK! does not exist or has no media."
    goto :failed
)

rem -- the disk must be a USB disk ("Type : USB" in any language) --
set "UTYPE="
(
    echo select disk !UDISK!
    echo detail disk
) > "%DP_IN%"
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
for /f "usebackq tokens=1,* delims=:" %%a in ("%DP_OUT%") do (
    set "V=%%b"
    if defined V set "V=!V: =!"
    if /i "!V!"=="USB" set "UTYPE=USB"
)
if not defined UTYPE (
    set "ERRMSG=Disk !UDISK! is not a USB disk. Only USB disks can be written."
    goto :failed
)

rem -- never the disk of the running Windows --
call :disk_of_volume %SystemDrive:~0,1%
if "!VOLDISK!"=="!UDISK!" (
    set "ERRMSG=Disk !UDISK! holds %SystemDrive%."
    goto :failed
)

rem -- partition size: USB_PART_MB in MB, empty = the whole disk --
if not defined USB_FS set "USB_FS=fat32"
set "PSIZE="
set "PDESC=whole disk"
if defined USB_PART_MB (
    call :is_number "%USB_PART_MB%" || (
        set "ERRMSG=USB_PART_MB is not a number: %USB_PART_MB%"
        goto :failed
    )
    set "PSIZE= size=%USB_PART_MB%"
    set "PDESC=%USB_PART_MB% MB"
)

echo.
echo  Partition : %USB_FS%, !PDESC!
echo  Disk !UDISK! ^(!USIZE! !UUNIT!, USB^) will be ERASED. All data on it will be lost.
set "ANS="
set /p "ANS=Type YES to continue = "
if not "!ANS!"=="YES" (
    echo [INFO] Cancelled.
    goto :cancel
)

echo [INFO] Formatting disk !UDISK!...
(
    echo select disk !UDISK!
    echo clean
    echo convert mbr
    echo create partition primary!PSIZE!
    echo format quick fs=%USB_FS% label="%MEDIA_LABEL%"
    echo active
    echo assign
    echo exit
) > "%DP_IN%"
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
if errorlevel 1 (
    type "%DP_OUT%"
    if /i "%USB_FS%"=="fat32" if not defined USB_PART_MB (
        echo.
        echo  [HINT] If the format step failed on a drive over 32 GB, updating
        echo         Windows is recommended. Otherwise make the ISO ^(mode 1^) and
        echo         write it with Rufus ^(https://rufus.ie^), or set
        echo         USB_PART_MB=32000 in data\Media\config.cmd.
        echo         The disk has already been erased.
    )
    set "ERRMSG=diskpart failed on disk !UDISK!."
    goto :failed
)

rem -- drive letter of the new volume: "Volume N  <letter>  <label> ..." --
set "ULTR="
for /l %%n in (1,1,5) do if not defined ULTR (
    (
        echo select disk !UDISK!
        echo detail disk
    ) > "%DP_IN%"
    diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
    for /f "usebackq tokens=3,4" %%a in ("%DP_OUT%") do (
        if /i "%%b"=="%MEDIA_LABEL%" for %%L in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do if /i "%%a"=="%%L" set "ULTR=%%L"
    )
    if not defined ULTR timeout /t 2 /nobreak >nul
)
if not defined ULTR (
    set "ERRMSG=The new USB volume has no drive letter."
    goto :failed
)

if exist "%BOOTSECT%" (
    echo [INFO] Writing the BIOS boot code to !ULTR!:...
    "%BOOTSECT%" /nt60 !ULTR!: /force /mbr >nul
    if errorlevel 1 echo [WARN] bootsect failed. The USB drive may not start on BIOS PCs.
) else (
    echo [WARN] bootsect.exe not found. The USB drive may not start on BIOS PCs.
)
set "UDRV=!ULTR!"
goto :copy_usb


rem ============================================================
rem  update an existing DVT USB drive (no format)
rem ============================================================
:update_usb
echo.
set "UDRV="
set /p "UDRV=Drive letter of the DVT USB drive, e.g. E (empty = cancel) = "
if not defined UDRV (
    echo [INFO] Cancelled.
    goto :cancel
)
set "UDRV=!UDRV::=!"
set "UDRV=!UDRV:\=!"
set "UDRV=!UDRV: =!"
if /i "!UDRV!"=="%SystemDrive:~0,1%" (
    set "ERRMSG=!UDRV!: is the Windows drive."
    goto :failed
)
if not exist "!UDRV!:\sources\boot.wim" (
    set "ERRMSG=!UDRV!:\sources\boot.wim not found. Use mode 2 for a new USB drive."
    goto :failed
)

:copy_usb
echo [INFO] Copying the media files to !UDRV!:...
xcopy "%MEDIA_STAGE%\*" "!UDRV!:\" /e /i /h /r /y >nul
if errorlevel 1 (
    set "ERRMSG=Failed to copy the media files to !UDRV!:"
    goto :failed
)
set "DONE_L1=USB drive ready : !UDRV!:  (DVT %DVT_VERSION%)"
set "DONE_L2=Config files    : !UDRV!:\config  (config.cmd, ip.txt, aria2.conf.*, DVT_backup.torrent)"
set "DONE_L3=Remove the USB drive safely before unplugging it."
goto :done


:done
rd /s /q "%MEDIA_STAGE%" >nul 2>&1
del /f /q "%DP_IN%" "%DP_OUT%" >nul 2>&1
call :show_done
pause >nul
exit /b 0

:cancel
rd /s /q "%MEDIA_STAGE%" >nul 2>&1
del /f /q "%DP_IN%" "%DP_OUT%" >nul 2>&1
pause
exit /b 2

:failed
if "%HIVE_LOADED%"=="1" reg unload HKLM\DVT_MEDIA_DEFAULT >nul 2>&1
if "%MOUNTED%"=="1" (
    echo [INFO] Discarding the changes to the mounted image...
    "%DISM%" /Unmount-Image /MountDir:"%MEDIA_MOUNT%" /Discard >nul 2>&1
)
del /f /q "%DP_IN%" "%DP_OUT%" >nul 2>&1
call :show_failed
pause >nul
exit /b 1


rem ============================================================
rem  :unload_hive   up to 3 tries, a handle may close a bit later
rem ============================================================
:unload_hive
for /l %%n in (1,1,3) do (
    reg unload HKLM\DVT_MEDIA_DEFAULT >nul 2>&1
    if not errorlevel 1 (
        set "HIVE_LOADED=0"
        exit /b 0
    )
    timeout /t 2 /nobreak >nul
)
exit /b 1


rem ============================================================
rem  :disk_of_volume <letter>
rem  Sets VOLDISK to the disk number of the volume (empty on error).
rem  "detail volume" marks the disk line with "*" in any language:
rem  "* Disk 0   Online ..."
rem ============================================================
:disk_of_volume
set "VOLDISK="
(
    echo select volume %~1
    echo detail volume
) > "%DP_IN%"
diskpart /s "%DP_IN%" > "%DP_OUT%" 2>&1
for /f "usebackq tokens=1-3" %%a in ("%DP_OUT%") do (
    if "%%a"=="*" if not defined VOLDISK call :is_number "%%c" && set "VOLDISK=%%c"
)
exit /b 0


rem ============================================================
rem  :is_number "<value>"   exit 0 = digits only, 1 = anything else
rem ============================================================
:is_number
set "NUMTEST=%~1"
if not defined NUMTEST exit /b 1
for /f "delims=0123456789" %%z in ("%NUMTEST%") do exit /b 1
exit /b 0


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
