@echo off
rem ============================================================
rem  DVT TEST - startnet.cmd (WinPE, X:\Windows\System32)
rem  Runs automatically when the TEST WinPE starts.
rem  03_make_test_pe.bat copies this file into the test image.
rem ============================================================
cd /d "%SystemDrive%\restore"
call "%SystemDrive%\restore\start_test.bat"
