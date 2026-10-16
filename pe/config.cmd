rem ============================================================
rem  DVT - shared settings for all WinPE scripts
rem
rem  Every script in this folder starts with:
rem      call "%~dp0config.cmd"
rem  This file only sets variables. Change values here, not in the
rem  individual scripts.
rem ============================================================

rem ---------- folders and files ----------
set "PE_DIR=%~dp0"
set "PE_DIR=%PE_DIR:~0,-1%"
if not defined TEMP set "TEMP=%SystemRoot%\Temp"

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
rem Exists only when the client PC used a static IP address.
rem One value per line: line 1 = ip, line 2 = subnet, line 3 = gateway
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
rem Marker file written by make_boot.bat on the Windows drive
set "TAG_FILE=DVT.tag"
rem 1 = when no tag file exists, use the disk of the ONLY unformatted
rem     (RAW) volume, or the ONLY disk in the PC. 0 = tag file required.
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

rem ---------- restore ----------
set "BCD_LOCALE=ko-kr"
set "FAIL_REBOOT_SEC=10"
set "DONE_REBOOT_SEC=5"

rem ---------- console colors ----------
set "COLOR_WORK=70"
set "COLOR_RESTORE=27"
set "COLOR_OK=2F"
set "COLOR_FAIL=4F"
