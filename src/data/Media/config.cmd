rem ============================================================
rem  DVT media - settings for 02_make_media.bat (build PC)
rem
rem  02_make_media.bat is in the build folder, next to 01_make_pe.bat.
rem  This file loads data\host\config.cmd first (DISM, ADK, pe_tools,
rem  drivers, build folders), then adds the media settings.
rem  Change values here, not in 02_make_media.bat.
rem  The WinPE settings of the media are in data\Media\pe\config.cmd.
rem ============================================================

rem ---------- shared build settings ----------
call "%~dp0..\host\config.cmd"

rem ---------- folders ----------
set "MEDIA_DIR=%~dp0"
set "MEDIA_DIR=%MEDIA_DIR:~0,-1%"
rem The ONLY WinPE scripts of the media image -> X:\restore
set "MEDIA_PE_DIR=%MEDIA_DIR%\pe"
rem Copied to <media>\config:
rem   ip.txt (static IP only), aria2.conf.100, aria2.conf.1G, DVT_backup.torrent
set "MEDIA_CONFIG_DIR=%MEDIA_DIR%\config"
rem Stored copies of the ADK files used to make the media. Filled from
rem the ADK on the first run; after that the ADK is not needed for them.
rem They are kept in SOURCE_DIR (<build>\source, data\host\config.cmd),
rem next to the clean winpe.wim and boot.sdi:
rem   adk_media : the ADK "Windows Preinstallation Environment\amd64\Media" folder
rem   adk_tools : oscdimg.exe, etfsboot.com, bootsect.exe and efisys.bin
rem               (= the ADK efisys_noprompt.bin, renamed)
set "MEDIA_FILES_DIR=%SOURCE_DIR%\adk_media"
set "MEDIA_TOOLS_DIR=%SOURCE_DIR%\adk_tools"
rem Result: boot.wim of the media and the ISO file
set "MEDIA_OUT_DIR=%OUT_ROOT%\media"
set "MEDIA_WIM=%MEDIA_OUT_DIR%\boot.wim"
set "MEDIA_ISO=%MEDIA_OUT_DIR%\DVT_media.iso"
rem Local work folders (not synced by OneDrive etc.)
set "MEDIA_WORK=%BUILD_LOCAL%\media_work"
set "MEDIA_MOUNT=%BUILD_LOCAL%\media_mount"
set "MEDIA_STAGE=%BUILD_LOCAL%\media_root"

rem ---------- link.exe ----------
rem Kept in data\Media\pe and copied with the other WinPE files. It must be a
rem 64-bit program (WinPE x64 has no 32-bit support). Required.
set "LINK_EXE=%MEDIA_PE_DIR%\link.exe"

rem ---------- ADK sources (first run only) ----------
for %%I in ("%ADK_PE_DIR%\..\..") do set "ADK_ROOT=%%~fI"
set "ADK_MEDIA_DIR=%ADK_PE_DIR%\Media"
set "ADK_OSCDIMG_DIR=%ADK_ROOT%\Deployment Tools\amd64\Oscdimg"
set "ADK_BOOTSECT=%ADK_ROOT%\Deployment Tools\amd64\BCDBoot\bootsect.exe"

rem ---------- stored tools ----------
set "OSCDIMG=%MEDIA_TOOLS_DIR%\oscdimg.exe"
set "ETFSBOOT=%MEDIA_TOOLS_DIR%\etfsboot.com"
rem UEFI boot sector of the ISO. 02_make_media.bat stores the ADK
rem efisys_noprompt.bin under this name, so the CD boots without
rem "Press any key to boot from CD or DVD".
set "EFISYS=%MEDIA_TOOLS_DIR%\efisys.bin"
set "BOOTSECT=%MEDIA_TOOLS_DIR%\bootsect.exe"

rem ---------- media ----------
set "MEDIA_LABEL=DVT"
rem File system of a new USB drive (02_make_media.bat usb): fat32 or exfat.
rem FAT32 boots on UEFI and BIOS PCs. The default formats the whole disk
rem as FAT32 at any size. If the format fails on a drive over 32 GB,
rem updating Windows is recommended; or set USB_PART_MB (e.g. 32000).
rem Many UEFI firmwares do not boot from exFAT.
set "USB_FS=fat32"
rem Size of the USB partition in MB. Empty = the whole disk.
set "USB_PART_MB="
