@echo off
rem ============================================================
rem  DVT - startnet.cmd (WinPE, X:\Windows\System32)
rem  Runs automatically when WinPE starts.
rem  make_pe.bat copies this file into the image.
rem ============================================================
cd /d "%SystemDrive%\restore"
call "%SystemDrive%\restore\start_dvt.bat"
