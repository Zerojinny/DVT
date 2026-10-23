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
rem HOST_DIR = <build>\bats\host, BATS_DIR = <build>\bats, BUILD_DIR = <build>
for %%I in ("%HOST_DIR%\..") do set "BATS_DIR=%%~fI"
for %%I in ("%HOST_DIR%\..\..") do set "BUILD_DIR=%%~fI"

rem ---------- version ----------
rem Next to boot.wim on the client (copied by 01_make_pe.bat), or
rem bats\common\version.cmd in the build folder
if exist "%HOST_DIR%\version.cmd" (
    call "%HOST_DIR%\version.cmd"
) else if exist "%BATS_DIR%\common\version.cmd" (
    call "%BATS_DIR%\common\version.cmd"
)
if not defined DVT_VERSION set "DVT_VERSION=unknown"

rem ---------- client PC (make_boot.bat) ----------
rem Working folder on the client PC
set "WORK_DIR=C:\temp"
rem WinPE image next to these scripts: the folder this config.cmd is in.
rem   C:\temp\boot      = _output\boot      (01_make_pe.bat)
rem   C:\temp\boot_test = _output\boot_test (03_make_test_pe.bat)
set "BOOT_WIM=%HOST_DIR%\boot.wim"
set "TORRENT=%WORK_DIR%\DVT_backup.torrent"
rem Written only when the client uses a static IP address.
rem One value per line: line 1 = ip, line 2 = subnet, line 3 = gateway,
rem lines 4-5 = DNS servers (only when Windows has static DNS servers)
set "IP_FILE=%WORK_DIR%\ip.txt"
rem Exported network drivers (emptied on every run)
set "NETDRV_DIR=%WORK_DIR%\netdrv"
rem Drivers whose manufacturer or name matches this regex are not
rem exported (WinPE already has working drivers for them).
rem Empty = export everything.
set "NETDRV_EXCLUDE=Realtek"
rem Local folder used to mount boot.wim (not synced by OneDrive etc.)
set "BOOT_MOUNT_DIR=%SystemDrive%\DVT_BootMount"
rem The disk ID of the Windows disk (GPT disk GUID or MBR signature)
rem is written into boot.wim as restore\<DISK_ID_NAME>. WinPE finds the
rem disk to erase by this ID first.
set "DISK_ID_NAME=target_disk.txt"
rem BitLocker on the Windows drive:
rem   1 = suspend the protection for one restart (manage-bde
rem       -RebootCount 1), so a failed check that returns to Windows
rem       does not ask for the recovery key. It resumes by itself.
rem   0 = leave it as it is
set "BITLOCKER_SUSPEND=1"

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

rem ---------- build PC (01_make_pe.bat) ----------
set "ADK_PE_DIR=%ProgramFiles(x86)%\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64"
set "PE_LANG=en-us"
rem WinPE scripts (the pe folder next to this folder) -> X:\restore
set "PE_SRC_DIR=%BATS_DIR%\pe"
rem WinPE scripts shared by the client local boot, the test image and
rem the USB / CD media -> X:\restore (copied after PE_SRC_DIR)
set "PE_COMMON_DIR=%BATS_DIR%\common"
rem Files that must exist in PE_COMMON_DIR
set "PE_COMMON_FILES=version.cmd check_gateway.bat check_seeder.bat check_space.bat get_firmware.bat get_ip.bat get_target.bat make_disk.bat ping_host.bat restore.bat set_ip.bat start_restore.bat wait.bat wpe_nonet.xml"
rem Optional: tools copied to X:\restore (aria2c.exe, wimlib-imagex.exe, DLLs)
set "PE_TOOLS_DIR=%BUILD_DIR%\pe_tools"
rem Optional: files copied to X:\Windows\System32
set "PE_SYS32_DIR=%BUILD_DIR%\system32"
rem Optional: drivers added to every WinPE image
set "PE_DRIVERS_DIR=%BUILD_DIR%\drivers"
set "NIRCMD_SRC=%BUILD_DIR%\nircmd-x64\nircmd.exe"
rem Clean copies of winpe.wim and boot.sdi taken from the ADK
set "SOURCE_DIR=%BUILD_DIR%\source"
rem All build results go under this folder:
rem   _output\boot      01_make_pe.bat      (boot.wim + boot.sdi + host scripts)
rem   _output\boot_test 03_make_test_pe.bat
rem   _output\media     02_make_media.bat   (boot.wim of the media, ISO)
set "OUT_ROOT=%BUILD_DIR%\_output"
rem Build result of 01_make_pe.bat: boot.wim + boot.sdi
set "OUT_DIR=%OUT_ROOT%\boot"
rem Local work folder (not synced by OneDrive etc.)
set "BUILD_LOCAL=%SystemDrive%\WinPE_LocalBuild"
set "PE_SCRATCH_MB=512"

rem ---------- tools ----------
set "DISM=%SystemRoot%\System32\dism.exe"
set "BCDEDIT=%SystemRoot%\System32\bcdedit.exe"
set "PNPUTIL=%SystemRoot%\System32\pnputil.exe"
set "MANAGEBDE=%SystemRoot%\System32\manage-bde.exe"

rem ---------- console colors ----------
set "COLOR_LINK_1G=27"
set "COLOR_LINK_100M=80"
set "COLOR_LINK_SLOW=40"
set "COLOR_OK=2F"
set "COLOR_FAIL=4F"
