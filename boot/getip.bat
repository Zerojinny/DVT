@echo off
setlocal EnableDelayedExpansion

rem =========================================================
rem  Set the folder where ip.txt will be saved.
rem  ip.txt format (only written when the IP is Static):
rem     line 1 : IP address
rem     line 2 : Subnet mask
rem     line 3 : Default gateway
rem =========================================================
set "OUTFOLDER=c:\temp"
set "OUTFILE=%OUTFOLDER%\ip.txt"
if not exist "%OUTFOLDER%" mkdir "%OUTFOLDER%"

if exist %OUTFILE% del %OUTFILE% /f /q

rem ---- 1) Find the interface IP that owns the best default route ----
set "BESTMETRIC=999999"
set "IFIP="
set "GW="
set "MASK="
for /f "tokens=1-5" %%a in ('route print -4 0.0.0.0 ^| findstr /R /C:"^ *0\.0\.0\.0 *0\.0\.0\.0 "') do (
    if not "%%e"=="" (
        set /a M=%%e 2>nul
        if !M! LSS !BESTMETRIC! (
            set "BESTMETRIC=!M!"
            set "IFIP=%%d"
            set "GW=%%c"
        )
    )
)

if not defined IFIP (
    echo No adapter connected to the internet ^(default gateway^) was found.
    goto :end
)

rem ---- 2) Look for that IP in the TCP/IP interface registry keys ----
rem  For a Static IP, the subnet mask is read from the SubnetMask value
rem  at the same position as the matched IP in the IPAddress list.
set "RESULT="
set "GUID="
set "MATCHIDX="
for /f "delims=" %%K in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" 2^>nul') do (
    set "DHCPIP="
    set "EN="
    set "STATICIP="
    set "STATICMASK="
    for /f "tokens=1,2,*" %%A in ('reg query "%%K" /v EnableDHCP 2^>nul') do if /i "%%A"=="EnableDHCP" set "EN=%%C"
    for /f "tokens=1,2,*" %%A in ('reg query "%%K" /v DhcpIPAddress 2^>nul') do if /i "%%A"=="DhcpIPAddress" set "DHCPIP=%%C"
    for /f "tokens=1,2,*" %%A in ('reg query "%%K" /v IPAddress 2^>nul') do if /i "%%A"=="IPAddress" set "STATICIP=%%C"
    for /f "tokens=1,2,*" %%A in ('reg query "%%K" /v SubnetMask 2^>nul') do if /i "%%A"=="SubnetMask" set "STATICMASK=%%C"

    if not defined RESULT if "!EN!"=="0x1" if /i "!DHCPIP!"=="!IFIP!" (
        set "RESULT=Dynamic"
        set "GUID=%%~nxK"
    )
    if not defined RESULT if "!EN!"=="0x0" if defined STATICIP (
        set "LIST=!STATICIP:\0= !"
        set "IDX=0"
        for %%i in (!LIST!) do (
            set /a IDX+=1
            if not defined RESULT if "%%i"=="!IFIP!" (
                set "RESULT=Static"
                set "GUID=%%~nxK"
                set "MATCHIDX=!IDX!"
            )
        )
        if defined MATCHIDX if defined STATICMASK (
            set "MLIST=!STATICMASK:\0= !"
            set "MN=0"
            for %%m in (!MLIST!) do (
                set /a MN+=1
                if "!MN!"=="!MATCHIDX!" set "MASK=%%m"
            )
        )
    )
)

rem ---- 3) Get the adapter name from the GUID ----
set "ADNAME=(unknown)"
if defined GUID (
    for /f "tokens=1,2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Network\{4D36E972-E325-11CE-BFC1-08002BE10318}\%GUID%\Connection" /v Name 2^>nul') do if /i "%%A"=="Name" set "ADNAME=%%C"
)

set "SHOWMASK=(n/a)"
if defined MASK set "SHOWMASK=!MASK!"

echo ==============================================
echo  Adapter Name : !ADNAME!
echo  IP Address   : %IFIP%
echo  Subnet Mask  : !SHOWMASK!
echo  Gateway      : %GW%
echo ----------------------------------------------
if not defined RESULT set "RESULT=Could not be determined"
echo  Result       : !RESULT! IP
echo ==============================================

rem ---- 4) Save IP / mask / gateway (3 lines) only if it is a Static IP ----
if /i "!RESULT!"=="Static" (
    if not defined MASK (
        echo [ERROR] Could not determine the subnet mask. Nothing saved.
    ) else (
        >  "%OUTFILE%" echo %IFIP%
        >> "%OUTFILE%" echo !MASK!
        >> "%OUTFILE%" echo %GW%
        echo Static IP detected. Saved to: %OUTFILE%
    )
) else (
    echo Dynamic ^(or undetermined^) IP. Nothing saved, exiting.
)

:end
echo.
endlocal
exit /b
