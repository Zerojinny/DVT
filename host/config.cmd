rem ============================================================
rem  DVT - shared settings for all Windows-side (host) scripts
rem
rem  Every script in this folder starts with:
rem      call "%~dp0config.cmd"
rem  This file only sets variables. Change values here, not in the
rem  individual scripts.
rem ============================================================

rem ---------- folders ----------
set "HOST_DIR=%~dp0"
set "HOST_DIR=%HOST_DIR:~0,-1%"
for %%I in ("%HOST_DIR%\..") do set "BUILD_DIR=%%~fI"

rem ---------- client PC (make_boot.bat) ----------
rem Working folder on the client PC
set "WORK_DIR=C:\temp"
rem WinPE image built by make_pe.bat and copied to the client
set "BOOT_WIM=%WORK_DIR%\boot\boot.wim"
set "TORRENT=%WORK_DIR%\DVT_backup.torrent"
rem Written only when the client uses a static IP address.
rem One value per line: line 1 = ip, line 2 = subnet, line 3 = gateway
set "IP_FILE=%WORK_DIR%\ip.txt"
rem Exported network drivers (emptied on every run)
set "NETDRV_DIR=%WORK_DIR%\netdrv"
rem Drivers whose manufacturer or name matches this regex are not
rem exported (WinPE already has working drivers for them).
rem Empty = export everything.
set "NETDRV_EXCLUDE=Realtek"
rem Local folder used to mount boot.wim (not synced by OneDrive etc.)
set "BOOT_MOUNT_DIR=%SystemDrive%\DVT_BootMount"
rem Marker file that tells WinPE which disk to erase
set "TAG_FILE=DVT.tag"

rem ---------- boot entry (set_bcd.bat) ----------
set "BOOT_ENTRY_NAME=DVT WinPE"
set "BOOT_MENU_TIMEOUT=5"
rem How the one-time boot entry is removed afterwards:
rem   1 = from inside WinPE (adds a delete command to startnet.cmd in the WIM)
rem   2 = on the next Windows boot (scheduled task, the WIM is not changed)
rem   0 = not removed
set "BCD_CLEANUP_MODE=2"
set "BCD_TASK_NAME=DVT_BCD_Cleanup"
set "BCD_GUID_FILE=%WORK_DIR%\dvt_bcd_entry.guid"
rem Delay before the client PC restarts into WinPE
set "REBOOT_DELAY_SEC=10"

rem ---------- build PC (make_pe.bat) ----------
set "ADK_PE_DIR=%ProgramFiles(x86)%\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64"
set "PE_LANG=en-us"
rem WinPE scripts (the pe folder next to this folder) -> X:\restore
set "PE_SRC_DIR=%BUILD_DIR%\pe"
rem Optional: tools copied to X:\restore (aria2c.exe, wimlib-imagex.exe, DLLs)
set "PE_TOOLS_DIR=%BUILD_DIR%\pe_tools"
rem Optional: files copied to X:\Windows\System32
set "PE_SYS32_DIR=%BUILD_DIR%\system32"
rem Optional: drivers added to every WinPE image
set "PE_DRIVERS_DIR=%BUILD_DIR%\drivers"
set "NIRCMD_SRC=%BUILD_DIR%\nircmd-x64\nircmd.exe"
rem Clean copies of winpe.wim and boot.sdi taken from the ADK
set "SOURCE_DIR=%BUILD_DIR%\source"
rem Build result: boot.wim + boot.sdi
set "OUT_DIR=%BUILD_DIR%\boot"
rem Local work folder (not synced by OneDrive etc.)
set "BUILD_LOCAL=%SystemDrive%\WinPE_LocalBuild"
set "PE_SCRATCH_MB=512"

rem ---------- tools ----------
set "DISM=%SystemRoot%\System32\dism.exe"
set "BCDEDIT=%SystemRoot%\System32\bcdedit.exe"
set "PNPUTIL=%SystemRoot%\System32\pnputil.exe"

rem ---------- console colors ----------
set "COLOR_LINK_1G=27"
set "COLOR_LINK_100M=80"
set "COLOR_LINK_SLOW=40"
set "COLOR_OK=2F"
set "COLOR_FAIL=4F"
