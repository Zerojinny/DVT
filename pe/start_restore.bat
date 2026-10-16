@echo off
setlocal EnableExtensions
rem ============================================================
rem  DVT - start_restore.bat (WinPE)
rem  Called by aria2c (on-bt-download-complete in aria2.conf) when
rem  the download is complete.
rem   - leaves RESTORE_FLAG so start_dvt.bat knows the download
rem     finished, even when restore.bat stops aria2c later
rem   - starts restore.bat in its own window, so aria2c can keep
rem     seeding while the image is applied
rem  Exit : 0
rem ============================================================

call "%~dp0config.cmd"

rem start the restore only once
if exist "%RESTORE_FLAG%" exit /b 0
> "%RESTORE_FLAG%" echo started

start "DVT Restore" "%~dp0restore.bat"
exit /b 0
