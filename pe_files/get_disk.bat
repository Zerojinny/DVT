setlocal EnableDelayedExpansion

rem ============================================================
rem  Find the disk number to use (result: %ndisk%)
rem   1) If a volume containing DVT.tag exists -> use its disk
rem   2) Otherwise -> use the disk of the first RAW volume that is
rem      NOT a Removable volume (USB sticks are never selected)
rem  The selected disk is printed before it is used.
rem  No external tools except diskpart / wpeutil (no findstr/find).
rem ============================================================

set "nvol="
set "src="
set "tdisk="
set "ndisk="

rem --- Step 1: Search drive letters for the marker file DVT.tag ---
for %%x in (C D E F G H I J K L M N O P Q R S T U V W) do (
    if exist %%x:\DVT.tag set "tdisk=%%x"
)
if defined tdisk goto getdisk2

:getdisk
rem --- Step 2A: No tag -> first RAW, non-removable volume ---
echo list vol > diskpartsc.txt
diskpart /s diskpartsc.txt > vollist.txt

rem  Data line: "  Volume 3     E   DATA   RAW   Partition  ..."
for /f "usebackq tokens=1,2,*" %%a in ("vollist.txt") do (
    if /i "%%a"=="Volume" (
        set "rest= %%c "
        if /i not "!rest: RAW =!"=="!rest!" (
            if /i "!rest: Removable =!"=="!rest!" (
                if not defined nvol set "nvol=%%b"
            )
        )
    )
)
if not defined nvol goto error

(
    echo sel vol !nvol!
    echo det vol
) > detvol.txt
diskpart /s detvol.txt > voldet.txt
set "src=voldet.txt"
goto parsedisk

:getdisk2
rem --- Step 2B: Tag found -> detail that volume ---
(
    echo sel vol !tdisk!
    echo det vol
) > seldisk.txt
diskpart /s seldisk.txt > detvol.txt
set "src=detvol.txt"

:parsedisk
rem  Detail line: "* Disk 0   Online  ..." -> 2nd token "Disk", 3rd = number
for /f "usebackq tokens=1-3" %%a in ("!src!") do (
    if /i "%%b"=="Disk" if not defined ndisk set "ndisk=%%c"
)
if not defined ndisk goto error

rem --- Show which disk was selected (model, size) ---
(
    echo sel disk !ndisk!
    echo det disk
) > diskinfo_in.txt
diskpart /s diskinfo_in.txt > diskinfo.txt
echo ----------------------------------------------
echo  Selected disk to be erased: !ndisk!
type diskinfo.txt
echo ----------------------------------------------
goto end

:error
echo [ERROR] Target disk not found. Rebooting in 5 seconds...
ping 127.0.0.1 -n 6 >nul
wpeutil reboot
exit /b 1

:end
del /q diskpartsc.txt vollist.txt detvol.txt voldet.txt seldisk.txt diskinfo_in.txt diskinfo.txt 2>nul
echo Target disk number: %ndisk%
endlocal & set "ndisk=%ndisk%"
exit /b 0
