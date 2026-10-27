@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ============================================================
rem  DVT - ping_host.bat (WinPE, shared)
rem  data\common: used by the client local boot and the USB / CD media.
rem  Checks whether a host answers ping.
rem  A real reply line contains "TTL"; "TTL expired in transit"
rem  does not count as a reply.
rem
rem  Usage : call ping_host.bat <host> [tries]
rem  Exit  : 0 = host answered
rem          1 = no answer
rem          2 = no host given
rem ============================================================

set "HOST=%~1"
if not defined HOST exit /b 2
set "TRIES=%~2"
if not defined TRIES set "TRIES=1"

for /l %%n in (1,1,%TRIES%) do (
    for /f "delims=" %%L in ('ping -n 2 -w 1500 %HOST% 2^>nul') do (
        set "L=%%L"
        if not "!L:TTL=!"=="!L!" if "!L:expired=!"=="!L!" exit /b 0
    )
)
exit /b 1
