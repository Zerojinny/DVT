@echo off
rem ============================================================
rem  DVT media - startnet.cmd (WinPE, X:\Windows\System32)
rem  Runs automatically when WinPE starts from a USB drive or a CD.
rem  make_media.bat copies this file into the media image.
rem   1) finds the boot media: the drive that has \sources\boot.wim
rem      and a \config folder
rem   2) copies every file of <media>\config to X:\restore
rem      (DVT_backup.torrent, aria2.conf.1G, aria2.conf.100, ip.txt,
rem      config.cmd - replaces the config.cmd inside the image)
rem   3) starts start_media.bat
rem  Sets: MEDIA_DRV (drive letter only), DVT_CONFIG_ERR=1 on a copy error
rem ============================================================

set "MEDIA_DRV="
set "DVT_CONFIG_ERR="
set /a DVT_TRY=0

rem ---- 1) boot media (USB drives can appear a few seconds late) ----
:find_media
for %%x in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if not defined MEDIA_DRV if exist "%%x:\sources\boot.wim" if exist "%%x:\config\" set "MEDIA_DRV=%%x"
)
if defined MEDIA_DRV goto :copy_config
set /a DVT_TRY+=1
if %DVT_TRY% GEQ 10 goto :start
if %DVT_TRY% EQU 1 echo [INFO] Looking for the boot media...
ping -n 3 127.0.0.1 >nul 2>&1
goto :find_media

rem ---- 2) config folder -> X:\restore ----
:copy_config
echo [INFO] Boot media: %MEDIA_DRV%:
echo [INFO] Copying %MEDIA_DRV%:\config to %SystemDrive%\restore...
xcopy "%MEDIA_DRV%:\config\*" "%SystemDrive%\restore\" /e /i /h /r /y >nul
if errorlevel 1 set "DVT_CONFIG_ERR=1"
rem files copied from a CD are read-only
attrib -r "%SystemDrive%\restore\*" /s >nul 2>&1

rem ---- 3) main flow ----
:start
set "DVT_TRY="
cd /d "%SystemDrive%\restore"
call "%SystemDrive%\restore\start_media.bat"
