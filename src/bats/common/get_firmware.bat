@echo off
setlocal EnableExtensions
rem ============================================================
rem  DVT - get_firmware.bat (WinPE, shared)
rem  bats\common: used by the client local boot and the USB / CD media.
rem  Detects how this PC was booted (UEFI or legacy BIOS).
rem  make_disk.bat and restore.bat use the result to choose
rem  GPT/MBR and the bcdboot firmware type.
rem
rem  Returns: FIRMWARE = UEFI or BIOS
rem  Exit   : 0 = detected
rem           1 = unknown (UEFI is assumed)
rem ============================================================

wpeutil UpdateBootInfo >nul 2>&1
set "FWTYPE="
for /f "tokens=3" %%a in ('reg query "HKLM\System\CurrentControlSet\Control" /v PEFirmwareType 2^>nul') do set "FWTYPE=%%a"

set "FW="
if "%FWTYPE%"=="0x1" set "FW=BIOS"
if "%FWTYPE%"=="0x2" set "FW=UEFI"

if defined FW (
    echo [INFO] Firmware type: %FW%
    endlocal & set "FIRMWARE=%FW%" & exit /b 0
)

echo [WARN] Could not detect the firmware type. Assuming UEFI.
endlocal & set "FIRMWARE=UEFI" & exit /b 1
