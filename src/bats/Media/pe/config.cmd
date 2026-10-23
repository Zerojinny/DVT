rem ============================================================
rem  DVT media - shared settings for all WinPE scripts (USB / CD boot)
rem
rem  Based on bats\pe\config.cmd, plus the "media boot" section at the end.
rem  02_make_media.bat copies the bats\Media\pe and bats\common folders (and
rem  the tools of pe_tools) to X:\restore of a clean WinPE image. A copy
rem  of this file in <media>\config replaces it at every boot.
rem
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

rem Files copied from <media>\config by startnet.cmd:
rem   DVT_backup.torrent, aria2.conf.1G, aria2.conf.100, ip.txt (static IP only)
set "TORRENT=%PE_DIR%\DVT_backup.torrent"
rem Created by link.exe from aria2.conf.1G or aria2.conf.100
set "ARIA2_CONF=%PE_DIR%\aria2.conf"
rem Name of the top folder inside the torrent (aria2c creates
rem <drive>:\DL_NAME and the control file <drive>:\DL_NAME.aria2)
set "DL_NAME=DVT_backup"
rem Image file inside that folder
set "WIM_NAME=backup.wim"
rem Index of the image inside WIM_NAME that is restored (1 = first image).
rem List the images with: wimlib-imagex info backup.wim
set "WIM_INDEX=1"
rem Static IP base from <media>\config, one value per line:
rem   line 1 = ip, line 2 = subnet, line 3 = gateway,
rem   lines 4-5 = DNS servers (optional)
rem Which is tried first is set by DHCP_ENABLE (network section).
rem Without ip.txt, DHCP only.
set "BASEIP_FILE=%PE_DIR%\ip.txt"
rem Final settings of this PC (static IP only), same format (DNS lines =
rem the DNS servers actually used), written by start_media.bat. restore.bat moves it to T:\temp\ip.txt.
set "IP_FILE=%PE_DIR%\pc_ip.txt"
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
rem Disk number to erase. Empty = the operator enters it (get_input.bat).
rem Set: the operator enters only the last octet of a static IP (nothing
rem with DHCP). If the disk does not exist or is the boot media, the
rem operator selects the disk. MEDIA_CONFIRM still asks before erasing;
rem answering N there also lets the operator select the disk.
set "FORCE_DISK="
rem Drive letters of the new partitions
set "TDRV=T"
set "SDRV=S"
rem Partition sizes in MB
set "EFI_SIZE_MB=260"
set "MSR_SIZE_MB=16"
set "BIOS_SYS_SIZE_MB=500"

rem ---------- network ----------
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
rem Network order (start_media.bat):
rem   0 or empty : static IP (ip.txt) first; when its gateway test fails,
rem                DHCP is tried (see DHCP_FALLBACK_CONFIRM)
rem   1          : DHCP first; when no DHCP address is received or the DHCP
rem                gateway is unreachable, the static IP (ip.txt) is used
set "DHCP_ENABLE=0"
rem DHCP_ENABLE=1 with ip.txt: 2-second tries for a DHCP address before
rem the static IP is used (without ip.txt DHCP_WAIT_TRIES is used).
rem wpeinit no longer waits for DHCP (wpe_nonet.xml), so these tries are
rem the whole DHCP wait; 20 tries = 40 seconds covers a slow switch port.
set "DHCP_FIRST_TRIES=20"
rem Static IP first, static IP failed but DHCP works:
rem   0 = continue with DHCP without a question
rem   1 = ask the operator Y/N before continuing with DHCP
set "DHCP_FALLBACK_CONFIRM=0"

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
rem longer than bats\pe\config.cmd: time to remove the USB drive / CD
set "DONE_REBOOT_SEC=15"

rem ---------- console colors ----------
set "COLOR_WORK=70"
set "COLOR_RESTORE=27"
set "COLOR_OK=2F"
set "COLOR_FAIL=4F"

rem ---------- media boot (USB / CD) ----------
rem MEDIA_DRV (drive letter of the boot media) is set by startnet.cmd.
rem link.exe (kept in bats\Media\pe) selects aria2.conf by the link speed
rem (renames aria2.conf.1G or aria2.conf.100).
set "LINK_EXE=%PE_DIR%\link.exe"
rem Profile used when link.exe is missing or fails: 1G or 100
set "LINK_FALLBACK=100"
rem Range accepted for the last octet of a static IP address
set "OCTET_MIN=1"
set "OCTET_MAX=254"
rem 1 = ask for Y/N before the selected disk is erased, 0 = no question
set "MEDIA_CONFIRM=1"
