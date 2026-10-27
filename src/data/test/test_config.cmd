rem ============================================================
rem  DVT TEST - settings of the test WinPE image
rem
rem  Read by 03_make_test_pe.bat (build PC) and by the test scripts in
rem  WinPE (start_test.bat, upload_ftp.bat). It only sets variables.
rem  The values are copied into the image: rebuild the test image
rem  with 03_make_test_pe.bat after changing them.
rem
rem  The shared WinPE settings (network, seeder check, colors) come
rem  from data\pe\config.cmd.
rem ============================================================

rem ---------- FTP server (result upload) ----------
rem Address of the FTP server (IP address or host name), e.g. 192.168.0.10
set "FTP_HOST="
set "FTP_PORT=21"
rem Account. Do not use ! or " in these values; write % as %%.
set "FTP_USER="
set "FTP_PASS="
rem Remote folder, relative to the login folder, e.g. dvt/result
rem Empty = the login folder. No spaces.
set "FTP_DIR=home\dvt_test"

rem ---------- FTP client ----------
rem auto = curl.exe first, then ftp.exe
rem curl = curl.exe only, ftp = ftp.exe only
set "FTP_CLIENT=auto"
rem curl.exe only: 1 = passive mode, 0 = active mode
rem (ftp.exe always uses active mode)
set "FTP_PASSIVE=1"
rem curl.exe only: connect timeout and maximum time per attempt
set "FTP_TIMEOUT_SEC=15"
set "FTP_MAX_TIME_SEC=60"
rem Upload attempts and the wait between them
set "FTP_RETRIES=3"
set "FTP_RETRY_SEC=5"

rem ---------- test result ----------
rem Wait before the reboot after a successful test
set "TEST_DONE_REBOOT_SEC=5"
rem After a failed test:
rem   0 = keep the red screen and wait for a key, then reboot
rem   1 = reboot after FAIL_REBOOT_SEC seconds (data\pe\config.cmd)
set "TEST_FAIL_REBOOT=1"
rem 1 = also upload a report when the test fails, as
rem     <ip><TEST_FAIL_SUFFIX>.txt (only when an IP address was set)
rem 0 = upload only on success
set "TEST_UPLOAD_FAIL=0"
set "TEST_FAIL_SUFFIX=_FAIL"
