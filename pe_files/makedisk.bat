cls
echo Making partitions......

set "tdrv=t"
set "sdrv=s"

if not defined ndisk (
    echo [ERROR] ndisk is not set.
    exit /b 1
)

if exist format.txt del format.txt
if exist format_out.txt del format_out.txt

(
echo sel disk %ndisk%
echo clean
echo convert gpt
echo cre part efi size=256
echo format fs=fat32 quick label=EFI
echo ass letter=%sdrv%
echo cre part pri
echo format fs=ntfs quick label=Windows
echo ass letter=%tdrv%
echo exit
) > format.txt

diskpart /s format.txt > format_out.txt
if errorlevel 1 goto :fail
if not exist %sdrv%:\ goto :fail
if not exist %tdrv%:\ goto :fail

del format.txt format_out.txt >nul 2>&1
exit /b 0

:fail
echo [ERROR] Partitioning disk %ndisk% failed. Diskpart output:
if exist format_out.txt type format_out.txt
exit /b 1
