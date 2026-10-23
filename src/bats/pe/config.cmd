rem ============================================================
rem  DVT - shared settings for all WinPE scripts
rem
rem  01_make_pe.bat copies this folder and bats\common to X:\restore.
rem  Every script there starts with:
rem      call "%~dp0config.cmd"
rem  This file only sets variables. Change values here, not in the
rem  individual scripts.
rem ============================================================

rem ---------- folders and files ----------
set "PE_DIR=%~dp0"
set "PE_DIR=%PE_DIR:~0,-1%"
if not defined TEMP set "TEMP=%SystemRoot%\Temp"

rem ---------- version (bats\common\version.cmd, copied into the image) ----------
if exist "%PE_DIR%\version.cmd" call "%PE_DIR%\version.cmd"
if not defined DVT_VERSION set "DVT_VERSION=unknown"

rem Copied into the image by make_boot.bat
set "TORRENT=%PE_DIR%\DVT_backup.torrent"
set "ARIA2_CONF=%PE_DIR%\aria2.conf"
rem Link speed profile of the client (1G or 100), written by make_boot.bat
set "LINK_FILE=%PE_DIR%\link_profile.txt"
rem Name of the top folder inside the torrent (aria2c creates
rem <drive>:\DL_NAME and the control file <drive>:\DL_NAME.aria2)
set "DL_NAME=DVT_backup"
rem Image file inside that folder
set "WIM_NAME=backup.wim"
rem Index of the image inside WIM_NAME that is restored (1 = first image).
rem List the images with: wimlib-imagex info backup.wim
set "WIM_INDEX=1"
rem Exists only when the client PC used a static IP address.
rem One value per line: line 1 = ip, line 2 = subnet, line 3 = gateway,
rem lines 4-5 = DNS servers (only when Windows had static DNS servers)
set "IP_FILE=%PE_DIR%\ip.txt"
rem Created by start_restore.bat when the download has completed
set "RESTORE_FLAG=%TEMP%\dvt_restore.flag"

rem ---------- external tools: this folder first, then System32 ----------
set "ARIA2=%PE_DIR%\aria2c.exe"
if not exist "%ARIA2%" set "ARIA2=%SystemRoot%\System32\aria2c.exe"
set "WIMLIB=%PE_DIR%\wimlib-imagex.exe"
if not exist "%WIMLIB%" set "WIMLIB=%SystemRoot%\System32\wimlib-imagex.exe"
set "NIRCMD=%PE_DIR%\nircmd.exe"
if not exist "%NIRCMD%" set "NIRCMD=%SystemRoot%\System32\nircmd.exe"

rem ---------- target disk ----------
rem Disk number to erase. Leave empty to detect it automatically.
set "FORCE_DISK="
rem Identity of the Windows disk (GPT disk GUID or MBR signature),
rem written into the image by make_boot.bat. Checked first: it also
rem works when the Windows drive is encrypted with BitLocker.
set "DISK_ID_FILE=%PE_DIR%\target_disk.txt"
rem 1 = when target_disk.txt is missing or matches no disk, use the
rem     disk of the ONLY unformatted (RAW) volume, or the ONLY disk in
rem     the PC. Instant recovery programs can make the Windows partition
rem     look RAW in WinPE and hide the real disk ID.
rem 0 = the disk ID (or FORCE_DISK) is required.
set "AUTO_DISK_FALLBACK=1"
rem Drive letters of the new partitions
set "TDRV=T"
set "SDRV=S"
rem Partition sizes in MB
set "EFI_SIZE_MB=260"
set "MSR_SIZE_MB=16"
set "BIOS_SYS_SIZE_MB=500"

rem ---------- network ----------
rem Used only when ip.txt has no subnet line (line 2)
set "NET_MASK=255.255.255.0"
rem Used only when ip.txt has no DNS lines (lines 4-5)
set "NET_DNS1=8.8.8.8"
set "NET_DNS2=8.8.4.4"
rem Extra host that must answer before a static-IP adapter is accepted.
rem Empty = the gateway only. Use an address inside the deployment
rem network (tracker or seeder), not an internet address.
set "NET_TEST_HOST="
rem Static IP (set_ip.bat): when no adapter reaches the gateway, try all
rem adapters again after SET_IP_RETRY_SEC seconds, SET_IP_RETRIES times
set "SET_IP_RETRIES=3"
set "SET_IP_RETRY_SEC=10"
rem DHCP wait: number of 2-second retries
set "DHCP_WAIT_TRIES=30"

rem ---------- seeder check ----------
set "CHECK_FILE=dvt_check.txt"
set "SEEDER_TIMEOUT_SEC=60"
rem Seeder check attempts by link speed (LINK_PROFILE)
rem   1G  : 1 Gbps or faster
rem   100 : 100 Mbps or slower; also used when the speed is unknown
set "SEEDER_TRIES_1G=2"
set "SEEDER_TRIES_100=5"
rem aria2c log of the seeder check (kept for troubleshooting)
set "SEEDER_LOG=%TEMP%\dvt_seeder.log"
rem Extra aria2c options, e.g. --bt-tracker=http://...
set "SEEDER_EXTRA_OPTS="

rem ---------- disk space check (check_space.bat, before erasing) ----------
rem   1 = stop before erasing when the disk is too small
rem   2 = only warn
rem   0 = no check
set "SPACE_CHECK=1"
rem Size of the applied image. Empty = estimated as APPLIED_SIZE_PCT
rem percent of the download size. For the exact value, run
rem   wimlib-imagex info backup.wim 1
rem and use "Total Bytes" / 1048576 (MB).
set "APPLIED_SIZE_MB="
set "APPLIED_SIZE_PCT=200"
rem Space kept free on the Windows partition (MB)
set "SPACE_MARGIN_MB=2048"

rem ---------- restore ----------
set "BCD_LOCALE=ko-kr"
set "FAIL_REBOOT_SEC=10"
set "DONE_REBOOT_SEC=5"

rem ---------- console colors ----------
set "COLOR_WORK=70"
set "COLOR_RESTORE=27"
set "COLOR_OK=2F"
set "COLOR_FAIL=4F"
