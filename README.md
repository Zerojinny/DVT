# DVT — Deploy Via Torrent

**English** | [한국어](README.ko.md)

DVT restores a Windows image to many PCs at once over the local network.
Each PC boots a small WinPE image, downloads the backup image with BitTorrent
(aria2), and applies it with wimlib — so every PC that has finished downloading
also uploads to the others, and adding more PCs does not slow the deployment down
the way a single file server would.

A client PC can start DVT in two ways:

- **Client local boot** — `host\make_boot.bat` runs in the client's Windows, prepares
  the WinPE image for that PC and restarts into it. No input is needed at the PC.
- **USB / CD media** — `make_media.bat` makes a boot USB drive or ISO. Use it
  for PCs that cannot start Windows, or when nothing should run in the client's
  Windows first. The operator enters the IP address and the disk at each PC.

Everything is plain Windows batch. The scripts that run inside WinPE use only
tools that WinPE ships with (no WMIC, WMI, PowerShell or findstr), plus aria2c,
wimlib-imagex and NirCmd.

> [!WARNING]
> DVT **erases a whole disk** on every client PC it runs on. Read
> [Choosing the disk to erase](#choosing-the-disk-to-erase) and test on a spare
> PC before using it in a lab or office.

---

## Contents

- [How it works](#how-it-works)
- [Features](#features)
- [Requirements](#requirements)
- [Repository layout](#repository-layout)
- [Quick start — client local boot](#quick-start--client-local-boot)
- [Quick start — USB / CD media](#quick-start--usb--cd-media)
- [Test image](#test-image)
- [Preparing the torrent](#preparing-the-torrent)
- [Choosing the disk to erase](#choosing-the-disk-to-erase)
- [Network](#network)
- [USB / CD media details](#usb--cd-media-details)
- [Configuration](#configuration)
- [Script reference](#script-reference)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Third-party tools](#third-party-tools)
- [License](#license)

---

## How it works

| | Client local boot | USB / CD media |
|---|---|---|
| Build PC | `make_pe.bat` → `boot\` folder | `make_media.bat` → ISO or USB drive |
| Client PC, before WinPE | `host\make_boot.bat` in Windows (once per PC) | nothing — boot from the media |
| WinPE main script | `pe\start_dvt.bat` | `Media\pe\start_media.bat` |
| IP address | detected in Windows (static IP → `ip.txt`) | static IP from `ip.txt` (operator types the last octet) or DHCP, order by `DHCP_ENABLE` |
| Disk to erase | detected (`DVT.tag`) | typed by the operator |
| Failure before erasing | reboots into the old Windows | waits for a key, then reboots |
| WinPE settings | `pe\config.cmd` (inside `boot.wim`) | `Media\pe\config.cmd` (also on the media, editable on a USB drive) |

Both ways check the gateway and the seeder **before** anything is erased, and
both use the same torrent, aria2 profiles, download and restore
(`restore.bat`, `setpc.bat`).

### Client local boot

```
[1] Build PC ── make_pe.bat
      ADK winpe.wim + DVT scripts + aria2c, wimlib
      → boot\ folder (boot.wim, boot.sdi, host scripts)
         │
         │  copy boot\ to C:\temp\boot on the client
         ▼
[2] Client PC (Windows) ── host\make_boot.bat
      • detect the IP address and link speed
      • export the network drivers
      • add drivers, ip.txt, torrent, aria2.conf to boot.wim
      • write DVT.tag on the Windows drive
      • add a one-time boot entry
         │
         │  reboot
         ▼
[3] Client PC (WinPE) ── start_dvt.bat
      • find the target disk (DVT.tag)
      • configure the network
      • check the gateway and seeder   ← a failure up to here reboots into
                                          the old Windows, disk untouched
      • erase the disk, create partitions
      • download by torrent (aria2c)
         │
         │  download complete (aria2c keeps seeding)
         ▼
    restore.bat
      • apply the WIM, drivers, bcdboot, setpc.bat
         │
         ▼
    reboot into the restored Windows
```

### USB / CD media

```
[1] Build PC ── make_media.bat
      source\winpe.wim (clean ADK copy)
      + pe_tools, drivers, nircmd
      + Media\pe  (only these scripts)
      → media_out\boot.wim
      + Media\adk_media, Media\config, Media\pe\config.cmd
      → ISO (oscdimg) or USB drive
         │
         │  boot from the USB drive / CD
         ▼
[2] Client PC (WinPE) ── startnet.cmd
      • copy <media>\config\* → X:\restore
         ▼
    start_media.bat
      • network order (DHCP_ENABLE: static first / DHCP first)
      • show the disks, enter "150.0" (last IP octet.disk number)
      • check the gateway
      • link.exe → aria2.conf for the link speed
      • check the seeder              ← nothing is erased if a step up to
                                         here fails
      • erase the disk, create partitions
      • choose the download drive, download by torrent (aria2c)
         │
         │  download complete (aria2c keeps seeding)
         ▼
    restore.bat
      • apply the WIM, drivers, bcdboot
      • move files, setpc.bat
         │
         ▼
    reboot (remove the USB drive / CD)
```

The media image does **not** use `boot\boot.wim` or the `pe` folder:
`X:\restore` contains only the tools of `pe_tools` and the files of
`Media\pe`.

## Features

- **BitTorrent distribution** with aria2c; the restore starts as soon as the
  download is complete, and the PC keeps seeding while the image is applied.
- **Safety checks before erasing**: target disk, network, gateway and a real
  seeder download are verified first. Nothing is erased when one of them fails.
- **Target disk detection** by a marker file (`DVT.tag`) written from the
  running Windows, with an explicit override and a careful fallback. Anything
  ambiguous is an error. On the USB / CD media the operator chooses the disk;
  the boot media itself cannot be chosen.
- **UEFI and legacy BIOS**: GPT or MBR layout and the `bcdboot` firmware type
  are chosen automatically. The ISO and the USB drive boot on both.
- **Static IP or DHCP**: a static address used by Windows is carried into WinPE
  and applied to whichever adapter reaches the gateway. The media tries a
  static IP or DHCP first (`DHCP_ENABLE`) and falls back to the other.
- **Network drivers from the running PC** are exported and injected into WinPE,
  so NICs that WinPE does not support out of the box still work.
- **Link-speed profiles**: separate aria2 settings for 100 Mbps and 1 Gbps links.
- **Post-restore tasks**: extra files are copied to `C:\temp` and an optional
  `setpc.bat` runs once at the first Windows start.
- **One-time boot entry** that is removed automatically.
- **USB / CD media** for PCs without a working Windows; its settings can be
  changed on the USB drive without rebuilding.
- **Large IP display** on the client so you can identify a PC from across the room.

## Requirements

**Build PC**

- Windows 10/11 x64, administrator rights
- [Windows ADK](https://learn.microsoft.com/windows-hardware/get-started/adk-install)
  and the **Windows PE add-on** (amd64). The USB / CD media also needs the
  **Deployment Tools** of the ADK, on the first run only (see below).
- `aria2c.exe` and `wimlib-imagex.exe` (with its DLL), placed in `pe_tools\` or `system32\`
- `nircmd.exe` (x64), placed in `nircmd-x64\`
- USB / CD media only: a 64-bit `link.exe` in `Media\pe`. It is used as it is
  (nothing is compiled); `make_media.bat` stops when it is missing.

`make_media.bat` stores the ADK `Media` folder in `Media\adk_media`, and
oscdimg, the boot sector files and bootsect in `Media\adk_tools`. Later runs
use only the stored copies (and `source\winpe.wim`, shared with
`make_pe.bat`). `make_pe.bat` does not have to run first.

**Client PCs**

- Client local boot: Windows 10/11 x64 with administrator rights (to run `make_boot.bat`)
- USB / CD media: a PC that can boot from USB or CD (UEFI or BIOS)
- Wired network connection to the deployment network

**Deployment network**

- A BitTorrent **tracker** reachable from the clients. DHT, peer exchange and
  local peer discovery are disabled in the aria2 profiles, so peers are found
  through the tracker only.
- At least one **seeder** that has the complete `DVT_backup` folder.

## Repository layout

```
dvt/
├─ make_pe.bat              build the WinPE image (build PC)
├─ make_test_pe.bat         build the test WinPE image (build PC)
├─ make_media.bat           build the USB / CD media: ISO, new USB drive,
│                           or update a USB drive (build PC)
├─ host/                    Windows-side scripts (client PC)
│  ├─ config.cmd            settings for the host scripts and make_pe.bat
│  ├─ make_boot.bat         prepare a client PC and restart into WinPE
│  ├─ get_host_ip.bat       IP address and static/DHCP detection
│  ├─ get_link_speed.bat    link speed -> aria2 profile
│  ├─ export_net_drivers.bat
│  ├─ prepare_mount_dir.bat
│  ├─ set_bcd.bat           one-time WinPE boot entry
│  └─ show_ip.bat           IP address in large digits
├─ pe/                      WinPE scripts (copied to X:\restore)
│  ├─ config.cmd            settings for the WinPE scripts
│  ├─ startnet.cmd          WinPE entry point
│  ├─ start_dvt.bat         main flow
│  ├─ restore.bat           apply the image, boot files, clean-up
│  ├─ start_restore.bat     called by aria2c when the download is complete
│  ├─ aria2.conf.100        aria2 profile for 100 Mbps links
│  ├─ aria2.conf.1G         aria2 profile for 1 Gbps links
│  └─ ...                   helper scripts (see Script reference)
├─ Media/                   USB / CD media
│  ├─ config.cmd            settings for make_media.bat (loads host\config.cmd)
│  ├─ link.au3              source of link.exe (reference only)
│  ├─ config/               copied to <media>\config
│  │  ├─ DVT_backup.torrent
│  │  ├─ aria2.conf.100
│  │  ├─ aria2.conf.1G
│  │  ├─ ip.txt             static IP (see ip.txt.example)
│  │  └─ ip.txt.example
│  ├─ pe/                   every WinPE script of the media -> X:\restore
│  │  ├─ config.cmd         settings for the media WinPE scripts
│  │  │                     (also copied to <media>\config)
│  │  ├─ startnet.cmd       find the media, copy config\, start start_media.bat
│  │  ├─ start_media.bat    main flow
│  │  ├─ get_input.bat      disk list, IP last octet and disk number
│  │  ├─ getdiskinfo.bat    disk list
│  │  ├─ set_ip.bat         static IP from arguments (ip, mask, gateway)
│  │  ├─ get_target.bat     download drive, never the boot media
│  │  ├─ restore.bat        apply, move files, remind to remove the media
│  │  ├─ link.exe           aria2.conf by link speed (64-bit, required)
│  │  └─ ...                copies of pe scripts: check_gateway, check_seeder,
│  │                        get_firmware, get_ip, make_disk, ping_host,
│  │                        start_restore, wait
│  ├─ adk_media/            stored copy of the ADK WinPE "Media" folder
│  └─ adk_tools/            stored oscdimg.exe, etfsboot.com, bootsect.exe,
│                           efisys.bin (= ADK efisys_noprompt.bin, renamed)
├─ test/                    test image scripts (see Test image)
│  ├─ test_config.cmd       FTP server and test settings
│  ├─ startnet.cmd          test WinPE entry point
│  ├─ start_test.bat        test flow: network, gateway, seeder, upload
│  └─ upload_ftp.bat        FTP upload (curl.exe or ftp.exe)
│
│  ── not in the repository, provided by you ──
├─ pe_tools/                aria2c.exe, wimlib-imagex.exe, DLLs -> X:\restore
├─ system32/                optional files -> X:\Windows\System32
├─ drivers/                 optional drivers added to every WinPE image
├─ nircmd-x64/nircmd.exe
│
│  ── created by the build scripts ──
├─ source/                  clean winpe.wim and boot.sdi from the ADK
├─ boot/                    make_pe.bat: boot.wim + boot.sdi + host scripts
│                           (copy this folder to the client as C:\temp\boot)
├─ boot_test/               make_test_pe.bat (same use as boot/)
└─ media_out/               make_media.bat: boot.wim of the media, DVT_media.iso
```

## Quick start — client local boot

### 1. Build the WinPE image (build PC)

1. Install the Windows ADK and the WinPE add-on.
2. Put `aria2c.exe`, `wimlib-imagex.exe` and its DLL in `pe_tools\`,
   and `nircmd.exe` in `nircmd-x64\`.
3. Optionally add drivers to `drivers\` (e.g. storage drivers for new hardware,
   or the WinPE driver for [Realtek NICs](#realtek-nics)).
4. Review `pe\config.cmd` (see [Configuration](#configuration)).
5. Run `make_pe.bat`. It asks for elevation if needed.

The result is the `boot\` folder: `boot.wim`, `boot.sdi` and a copy of every
file in `host\`. This folder is everything a client PC needs besides the torrent.

> The mount and work folders are on the local system drive
> (`C:\WinPE_LocalBuild`). Do not move them into a folder synced by OneDrive,
> Dropbox or similar: sync clients can bring back deleted files after the unmount.

### 2. Prepare the torrent and the seeder

See [Preparing the torrent](#preparing-the-torrent). Start the tracker and the seeder.

### 3. Prepare each client PC

Copy the `boot\` folder from the build PC to `C:\temp\boot`, and the torrent
to `C:\temp`:

```
C:\temp\
├─ boot\
│  ├─ boot.wim
│  ├─ boot.sdi
│  ├─ make_boot.bat
│  ├─ config.cmd
│  └─ ...             (the other host scripts)
└─ DVT_backup.torrent
```

Run `C:\temp\boot\make_boot.bat`. It:

1. detects the IP address (a static address is saved to `ip.txt`: ip, subnet
   and gateway, one per line),
2. reads the link speed and picks `aria2.conf.100` or `aria2.conf.1G`,
3. exports the drivers of the connected network adapters,
4. mounts `boot.wim` and adds the drivers, `ip.txt`, the torrent and `aria2.conf`,
5. writes `DVT.tag` to the Windows drive,
6. adds a one-time WinPE boot entry,
7. shows the IP address in large digits and restarts after a key press.

### 4. Let it run

The PC boots into WinPE and restores itself. The console color tells you the state:

| Console | Meaning |
|---|---|
| Light gray background | Checking, partitioning, downloading |
| Green background (new "DVT Restore" window) | Restore running, then completed and rebooting |
| Red background | Failed — read the message on screen |

If a check fails **before** the disk is erased, the PC reboots back into its
old Windows after a few seconds. If something fails **after** the disk was
erased, DVT waits for a key so you can read the error.

## Quick start — USB / CD media

1. Prepare the torrent and the seeder (see
   [Preparing the torrent](#preparing-the-torrent)).
2. Put the files in `Media\config`: `DVT_backup.torrent`, `aria2.conf.100`,
   `aria2.conf.1G`, and `ip.txt` for a static IP (see [Network](#network)).
3. Review `Media\pe\config.cmd` (see [Configuration](#configuration)).
4. Run `make_media.bat` in the build folder as administrator and choose:
   - `1` ISO → `media_out\DVT_media.iso`, burn it to a CD / DVD
   - `2` USB → the selected **USB** disk is erased and made bootable
     (FAT32 on the whole disk; `USB_FS` and `USB_PART_MB` in `Media\config.cmd`)
   - `3` update → copies new files to an existing DVT USB drive

   `make_media.bat iso`, `make_media.bat usb` and `make_media.bat update` skip
   the menu.
5. Boot the client PC from the media, read the disk list, and type
   `<last octet>.<disk>` (e.g. `150.0`) for a static IP, or only the disk
   number for DHCP, then `Y`.
6. When the restore is done the PC reboots in 15 seconds — remove the media.

> [!WARNING]
> The disk number you type is **erased**. Check the disk list carefully. The
> disk of the boot USB drive cannot be selected.

Failures on the media always wait for a key, because an operator is present.

## Test image

`make_test_pe.bat` builds a **test** WinPE image that checks a client PC
end to end without touching any disk. Use it to find network, driver and
seeder problems before the real restore. It is started the same way as the
client local boot (`make_boot.bat`).

In WinPE the test image:

1. sets up the network exactly like the restore image (static IP from
   `ip.txt`, otherwise DHCP) and checks the gateway,
2. runs the seeder check (downloads `dvt_check.txt` only, into memory),
3. writes a report `<ip>.txt` (IP, gateway, adapter, link profile, seeder,
   firmware, detected target disk, model, `diskpart list disk`,
   `detail disk` of the target disk, `ipconfig /all`),
4. uploads it to the FTP server and reboots back into Windows.

The erase and restore scripts (`make_disk.bat`, `restore.bat`,
`start_restore.bat`, `start_dvt.bat`) are **not** copied into the test image.

Steps:

1. Set the FTP server in `test\test_config.cmd`:
   `FTP_HOST`, `FTP_PORT`, `FTP_USER`, `FTP_PASS` and, optionally, `FTP_DIR`
   (relative to the login folder). Do not use `!` or `"` in these values.
2. Run `make_test_pe.bat` on the build PC. The result is the `boot_test\` folder.
3. On the client, copy `boot_test\` to `C:\temp\boot` (instead of `boot\`),
   put the torrent in `C:\temp` and run `make_boot.bat` as usual.

| Screen | Meaning |
|---|---|
| Green "PASS" | Gateway and seeder OK, `<ip>.txt` uploaded, rebooting |
| Red "TEST FAILED" | A check or the upload failed. Reboots after `FAIL_REBOOT_SEC` (`TEST_FAIL_REBOOT=1`, default); `TEST_FAIL_REBOOT=0` waits for a key |

With `TEST_UPLOAD_FAIL=1` a failed test also uploads `<ip>_FAIL.txt` when an IP
address was set. The FTP client is `curl.exe` (passive mode, creates `FTP_DIR`)
or, as a fallback, `ftp.exe` (active mode only, `FTP_DIR` must exist). WinPE
contains neither: `make_test_pe.bat` copies them from the build PC unless you
put them in `pe_tools\` or `system32\`. The FTP settings are built into the
image, so rebuild it after changing them.

## Preparing the torrent

The torrent must contain a single top folder named `DVT_backup` (`DL_NAME`):

```
DVT_backup\
├─ backup.wim        the Windows image (index 1 is applied)        required
├─ dvt_check.txt     small file (a few KB) for the seeder check    required
├─ drivers\          drivers added to the restored Windows         optional
└─ files\            copied to C:\temp of the restored Windows     optional
   └─ setpc.bat      runs once at the first Windows start          optional
```

- Create `dvt_check.txt` **before** creating the torrent. WinPE downloads only
  this file to prove that a seeder is reachable before it erases anything.
- Put the tracker URL in the torrent. Alternatively set
  `SEEDER_EXTRA_OPTS=--bt-tracker=http://...` in `pe\config.cmd` or
  `Media\pe\config.cmd` (this is used for the seeder check only; the main
  download reads the torrent and `aria2.conf`).
- Save the torrent as `DVT_backup.torrent`: in `C:\temp` of each client for the
  client local boot, in `Media\config` for the media.
- When the client uses a static IP, `ip.txt` (ip, subnet, gateway) is also
  copied to `C:\temp` of the restored Windows, so `setpc.bat` can set the
  address again.

> [!WARNING]
> `dvt_check.txt` must **not be an empty 0-byte file.** There is no data to
> download, so aria2c "completes" it without reaching any seeder and the check
> would prove nothing. `check_seeder.bat` therefore fails the check, before
> the disk is erased, when `dvt_check.txt` in the torrent is 0 bytes ("The
> seeder check file in the torrent is empty"). Always put a file with content
> (a few KB) in the folder before you create the torrent. If you change the
> file, create the torrent again.

## Choosing the disk to erase

### Client local boot

`get_disk.bat` decides which disk is erased, in this order:

1. **`FORCE_DISK`** in `pe\config.cmd`, if set.
2. The disk of the volume that contains **`DVT.tag`**. `make_boot.bat` writes
   this file to the running Windows drive and deletes it from all other drives.
3. Only when `AUTO_DISK_FALLBACK=1`:
   1. the disk of the **only** unformatted (RAW) volume, or
   2. the **only** disk in the PC.

A tag on more than one disk, more than one RAW volume, or more than one disk
without a tag is treated as an error, so DVT never guesses. Set
`AUTO_DISK_FALLBACK=0` to require the tag file.

The tag is deleted from the restored Windows, so the next run starts clean.

### USB / CD media

There is no `DVT.tag`. `get_input.bat` shows the disk list and the operator
types the disk number (`R` scans the disks again). The disk must exist, and
the disk of the boot media cannot be selected. With `MEDIA_CONFIRM=1`
(default) the operator confirms with `Y` before the disk is erased.

## Network

### Client local boot

- **DHCP** (default): WinPE waits for an address (`DHCP_WAIT_TRIES` × 2 s) and
  uses the default route with the lowest metric.
- **Static IP**: if Windows used a static address, `make_boot.bat` stores the
  address, subnet mask and gateway in `ip.txt` inside the image, one value per
  line:
  ```
  203.244.132.150
  255.255.255.0
  203.244.132.1
  ```
  WinPE applies these three values with `NET_DNS1/2` (an `ip.txt` with the
  address only gets `NET_MASK` and the gateway `x.x.x.1`), tries every
  connected adapter, keeps the first one that reaches the gateway (and
  `NET_TEST_HOST`, if set) and returns the others to DHCP.
- **Link speed**: `make_boot.bat` measures it. Links of 1 Gbps or faster get
  `aria2.conf.1G`; everything else gets `aria2.conf.100`. The console color on
  the client shows which one was chosen (`COLOR_LINK_*` in `host\config.cmd`).

### USB / CD media

The order is set by `DHCP_ENABLE` in `Media\pe\config.cmd`.

| `DHCP_ENABLE` | `ip.txt` | What happens |
|---|---|---|
| `0` or empty (default) | exists | **Static IP first.** The operator enters the last octet and the disk number; the address is applied and the gateway is tested. If the test fails, every adapter is switched to DHCP and the DHCP gateway is tested. When that works, WinPE shows that the static IP failed but DHCP succeeded and continues with DHCP and the disk selected before (`DHCP_FALLBACK_CONFIRM=1`: asks first, `N` stops). |
| `1` | exists | **DHCP first.** WinPE waits up to `DHCP_FIRST_TRIES` × 2 s (20 s) for a DHCP address and tests its gateway. When both work, only the disk number is asked. Otherwise the static IP is used: the operator enters the last octet and the disk number, and the address is applied and tested. |
| any | missing | **DHCP only.** Only the disk number is asked. |

When no way works, WinPE stops before anything is erased and waits for a key
to reboot.

`ip.txt` in `Media\config` has the same three-line format as above, but
line 1 is a base address: only its first three octets are used (`ipr`), and
the operator types the last one.

```
203.244.132.0
255.255.255.0
203.244.132.1
```

Line 2 (subnet) and line 3 (gateway) may be omitted (`NET_MASK`, and `ipr.1`),
so an address-only `ip.txt` also works. Lines starting with `#` are ignored.
Save it as ANSI / ASCII, not UTF-8 with BOM.

When the static IP works, a new `ip.txt` with the values actually applied (ip,
subnet, gateway) is written and moved to `T:\temp\ip.txt` for `setpc.bat`.
With DHCP (also after the fallback) no `ip.txt` is written.

The link speed is measured in WinPE by `link.exe`, which renames
`aria2.conf.1G` or `aria2.conf.100` to `aria2.conf` (`LINK_FALLBACK` when
`link.exe` is missing or fails).

### Realtek NICs

By default `make_boot.bat` does **not export Realtek network drivers**
(`NETDRV_EXCLUDE=Realtek`). Realtek ships **separate drivers for WinPE**, and
the regular Windows driver in WinPE can cause errors such as the **connection
dropping** during the download. The USB / CD media does not export drivers at
all, so it needs the driver in `drivers\` for every NIC that WinPE does not
support.

> [!IMPORTANT]
> If some PCs have Realtek NICs, put Realtek's **WinPE driver** in the
> `drivers\` folder of the build PC (e.g. `drivers\realtek\`) and rebuild with
> `make_pe.bat` and `make_media.bat`. The drivers in `drivers\` go into every
> WinPE image.
>
> Emptying `NETDRV_EXCLUDE` to export Realtek's Windows driver is not
> recommended.

## USB / CD media details

### config folder

`make_media.bat` copies these files from `Media\config` to `<media>\config`,
plus `Media\pe\config.cmd`. When WinPE starts, `startnet.cmd` copies
`<media>\config` to `X:\restore`, so on a USB drive you can change them
without rebuilding. `<media>\config\config.cmd` replaces the `config.cmd`
inside `boot.wim`, so its settings (`DHCP_ENABLE`, `MEDIA_CONFIRM`, ...) apply
at the next boot. On a CD, change `Media\config` or `Media\pe\config.cmd` and
rebuild.

| File | Purpose |
|---|---|
| `DVT_backup.torrent` | required; its `dvt_check.txt` must not be empty (see [Preparing the torrent](#preparing-the-torrent)) |
| `aria2.conf.1G`, `aria2.conf.100` | required; `link.exe` renames the one for the link speed to `aria2.conf` |
| `ip.txt` | static IP base; tried first or as fallback (`DHCP_ENABLE`) |
| `config.cmd` | copied from `Media\pe\config.cmd`; WinPE settings |

`Media\pe\config.cmd` on the build PC is the original: making or updating a
USB drive (`2`, `3`) copies it over a `config.cmd` that was changed on the
drive.

### USB drive and ISO

- A new USB drive gets one **FAT32** partition (`USB_FS=fat32`), which boots
  on UEFI and BIOS PCs (BIOS through `bootsect`). The partition size is
  `USB_PART_MB` in MB; empty (the default) uses the whole disk.
- Windows before build 26300 cannot format more than 32 GB as FAT32 (build
  26300 or later: up to 2 TB). On such a build PC, with a larger drive and an
  empty `USB_PART_MB`, `make_media.bat` stops **before** erasing the disk.
- **Recommended on a build PC before build 26300:** make the ISO (`1`) and
  write it to the USB drive with [Rufus](https://rufus.ie). Rufus formats the
  whole drive as FAT32 at any size, and the drive boots on UEFI and BIOS PCs.
  In Rufus select the USB drive, select `media_out\DVT_media.iso`, keep the
  file system **FAT32**, and write it in ISO image mode. The `config` folder is
  part of the ISO, so the drive has the same files as one made with `2`; later
  you can update it with `3`.
- Other choices on such a build PC: `USB_PART_MB=32000` (the rest of the disk
  stays unused) or `USB_FS=exfat` (whole disk, but many UEFI firmwares do not
  boot from exFAT).
- `make_media.bat` only writes to disks whose type is **USB**, never to the
  disk that holds `%SystemDrive%`, and asks you to type `YES`.

### Behavior in WinPE

- **Reboot loop**: if the PC starts from the USB drive again after the restore,
  it only stops at the input prompt — nothing is erased without input. The ISO
  uses the no-prompt UEFI boot sector (`efisys_noprompt.bin`, stored as
  `efisys.bin`), so a CD left in the drive also boots again without asking —
  remove the CD while the restore counts down.
- The download drive is chosen automatically (`get_target.bat`): the fixed
  volume with the most free space, otherwise `T:`. The boot media is never
  used, even when it is a USB hard disk.

### Maintenance

The scripts in `Media\pe` that are copies of `pe` scripts must be updated by
hand when the `pe` versions change.

## Configuration

Change values in these files, not in the scripts.

| File | Used by |
|---|---|
| `host\config.cmd` | client PC (`make_boot.bat`) and build PC (`make_pe.bat`) |
| `pe\config.cmd` | WinPE of the client local boot |
| `Media\config.cmd` | `make_media.bat` (loads `host\config.cmd` first) |
| `Media\pe\config.cmd` | WinPE of the USB / CD media |

### `host\config.cmd` (client PC and build PC)

| Variable | Default | Description |
|---|---|---|
| `WORK_DIR` | `C:\temp` | Working folder on the client PC |
| `BOOT_WIM` | `%WORK_DIR%\boot\boot.wim` | WinPE image to customize and boot |
| `TORRENT` | `%WORK_DIR%\DVT_backup.torrent` | Torrent copied into the image |
| `NETDRV_EXCLUDE` | `Realtek` | Regex; matching network drivers are not exported. Empty = export all. For Realtek, put the WinPE driver in `drivers\` (see [Realtek NICs](#realtek-nics)) |
| `BOOT_MOUNT_DIR` | `%SystemDrive%\DVT_BootMount` | Local mount folder |
| `TAG_FILE` | `DVT.tag` | Marker file for the disk to erase (must match `pe\config.cmd`) |
| `BOOT_ENTRY_NAME` | `DVT WinPE` | Name of the boot menu entry |
| `BCD_CLEANUP_MODE` | `2` | Removal of the boot entry: `1` from WinPE, `2` at the next Windows boot (scheduled task), `0` never |
| `REBOOT_DELAY_SEC` | `10` | Delay before the restart into WinPE |
| `ADK_PE_DIR`, `PE_LANG` | ADK amd64, `en-us` | Source of `winpe.wim` |
| `BUILD_LOCAL` | `%SystemDrive%\WinPE_LocalBuild` | Local build folder |
| `PE_SCRATCH_MB` | `512` | WinPE scratch space |

### `pe\config.cmd` (WinPE, client local boot)

| Variable | Default | Description |
|---|---|---|
| `DL_NAME` | `DVT_backup` | Top folder inside the torrent |
| `WIM_NAME` | `backup.wim` | Image file inside that folder |
| `FORCE_DISK` | *(empty)* | Disk number to erase; empty = detect |
| `AUTO_DISK_FALLBACK` | `1` | Allow the RAW-volume / single-disk fallback |
| `TDRV`, `SDRV` | `T`, `S` | Letters of the new Windows and system partitions |
| `EFI_SIZE_MB`, `MSR_SIZE_MB`, `BIOS_SYS_SIZE_MB` | `260`, `16`, `500` | Partition sizes |
| `NET_MASK` | `255.255.255.0` | Mask for a static IP when `ip.txt` has no subnet line |
| `NET_DNS1`, `NET_DNS2` | `8.8.8.8`, `8.8.4.4` | DNS for a static IP |
| `NET_TEST_HOST` | *(empty)* | Extra host that must answer (use the tracker or seeder) |
| `SET_IP_RETRIES`, `SET_IP_RETRY_SEC` | `3`, `10` | Static IP: when no adapter reaches the gateway, all adapters are tried again this many times, after this many seconds |
| `DHCP_WAIT_TRIES` | `30` | DHCP wait, in 2-second steps |
| `CHECK_FILE` | `dvt_check.txt` | File used for the seeder check |
| `SEEDER_TIMEOUT_SEC` | `60` | Seeder check timeout per attempt |
| `SEEDER_TRIES_1G`, `SEEDER_TRIES_100` | `2`, `5` | Seeder check attempts at 1 Gbps or faster / at 100 Mbps or slower (also when the speed is unknown). `make_boot.bat` writes the link profile to `link_profile.txt` in the image |
| `SEEDER_EXTRA_OPTS` | *(empty)* | Extra aria2c options for the seeder check |
| `BCD_LOCALE` | `ko-kr` | Locale passed to `bcdboot` |
| `FAIL_REBOOT_SEC`, `DONE_REBOOT_SEC` | `10`, `5` | Reboot delays |

### `Media\config.cmd` (make_media.bat)

| Variable | Default | Description |
|---|---|---|
| `MEDIA_LABEL` | `DVT` | Volume label of the ISO and the USB drive |
| `USB_FS` | `fat32` | File system of a new USB drive: `fat32` or `exfat` |
| `USB_PART_MB` | *(empty)* | Size of the USB partition in MB; empty = the whole disk |
| `MEDIA_OUT_DIR` | `media_out` in the build folder | Result folder (`boot.wim`, `DVT_media.iso`) |

### `Media\pe\config.cmd` (WinPE, USB / CD media)

It has the same variables as `pe\config.cmd` except `FORCE_DISK` and
`AUTO_DISK_FALLBACK` (the operator chooses the disk), plus:

| Variable | Default | Description |
|---|---|---|
| `DHCP_ENABLE` | `0` | `0` / empty = static IP (`ip.txt`) first, `1` = DHCP first |
| `DHCP_FIRST_TRIES` | `10` | `DHCP_ENABLE=1` with `ip.txt`: 2-second tries for DHCP before the static IP |
| `DHCP_FALLBACK_CONFIRM` | `0` | Static IP first, static IP failed but DHCP works: `0` = continue with DHCP, `1` = ask Y/N |
| `LINK_FALLBACK` | `100` | Profile when `link.exe` is missing or fails |
| `OCTET_MIN`, `OCTET_MAX` | `1`, `254` | Allowed last octet |
| `MEDIA_CONFIRM` | `1` | Ask Y/N before erasing |
| `DONE_REBOOT_SEC` | `15` | Time to remove the media |

### aria2 profiles

`pe\aria2.conf.100` and `pe\aria2.conf.1G` (for the media:
`Media\config\aria2.conf.*`) are ordinary aria2 configuration files. Both seed
for up to 60 minutes after the download, disable DHT/PEX/LPD and run
`start_restore.bat` when the download is complete. The 1 Gbps profile allows
more peers, removes the upload limit and enables a disk cache.

## Script reference

### Build PC

| Script | Purpose |
|---|---|
| `make_pe.bat` | Builds `boot\boot.wim` from the ADK `winpe.wim` (scripts, tools, drivers, Num Lock on) and copies the host scripts into `boot\` |
| `make_test_pe.bat` | Builds the test image `boot_test\boot.wim` (network, gateway and seeder check, FTP upload of `<ip>.txt`, no disk access) |
| `make_media.bat` | Builds `media_out\boot.wim` from the ADK `winpe.wim` with `Media\pe`, then writes the ISO, a new USB drive, or updates a USB drive (`iso`, `usb`, `update`) |

### Client PC (Windows, client local boot)

| Script | Purpose |
|---|---|
| `make_boot.bat` | Main script: prepares the PC and restarts into WinPE (runs from `C:\temp\boot`) |
| `get_host_ip.bat` | Finds the default-route adapter; writes `ip.txt` (ip, subnet, gateway) for a static address only |
| `get_link_speed.bat` | Link speed → aria2 profile and console color |
| `export_net_drivers.bat` | Exports drivers of connected physical NICs with `pnputil` |
| `prepare_mount_dir.bat` | Discards a stale mount and checks the mount folder is empty |
| `set_bcd.bat` | Creates a ramdisk boot entry for `boot.wim`, used for the next boot only |
| `show_ip.bat` | Shows the last octet of the IP address in large digits |

### WinPE (both)

| Script | Purpose |
|---|---|
| `get_firmware.bat` | UEFI or BIOS |
| `get_ip.bat` / `set_ip.bat` | DHCP / static IP |
| `check_gateway.bat` | Pings the default gateway |
| `check_seeder.bat` | Downloads `dvt_check.txt` only and verifies its size (rejects a 0-byte file) |
| `make_disk.bat` | Cleans the disk and creates GPT or MBR partitions |
| `get_target.bat` | Picks the download drive (another local volume with enough free space, otherwise `T:`; on the media never the boot media) |
| `start_restore.bat` | Called by aria2c; starts `restore.bat` once in its own window |
| `restore.bat` | Applies the image, drivers, boot files, `setpc.bat`, cleans up and reboots |
| `ping_host.bat`, `wait.bat` | Helpers (`timeout.exe` is not available in WinPE) |

### WinPE, client local boot only (`pe\`)

| Script | Purpose |
|---|---|
| `startnet.cmd` | Runs `start_dvt.bat` when WinPE starts |
| `start_dvt.bat` | Main flow: checks, network, erase, download |
| `get_disk.bat` | Disk to erase |

### WinPE, USB / CD media only (`Media\pe\`)

| Script | Purpose |
|---|---|
| `startnet.cmd` | Finds the boot media, copies `<media>\config` to `X:\restore`, runs `start_media.bat` |
| `start_media.bat` | Main flow: network order, input, checks, erase, download |
| `get_input.bat` | Disk list; last IP octet and disk number |
| `getdiskinfo.bat` | Disk list |
| `link.exe` | Link speed → `aria2.conf` |

## Troubleshooting

| Symptom | What to check |
|---|---|
| PC reboots into the old Windows after a few seconds | Client local boot: a check failed before erasing. The message on screen names it (disk, network, gateway or seeder). |
| "The target disk could not be determined" | `DVT.tag` missing or on several disks. Rerun `make_boot.bat`, or set `FORCE_DISK`. |
| "No seeder is reachable" | Tracker/seeder running? `dvt_check.txt` in the torrent? Log: `%TEMP%\dvt_seeder.log`. |
| "The seeder check file in the torrent is empty" | `dvt_check.txt` in the torrent is a 0-byte file. Give it content and create the torrent again. |
| No network in WinPE | The NIC driver may be missing. Check `NETDRV_EXCLUDE`, or add the driver to `drivers\` and rebuild. Realtek NICs need the WinPE driver. |
| Connection drops during the download on a Realtek PC | The Windows Realtek driver may be in WinPE. Keep `NETDRV_EXCLUDE=Realtek` and rebuild with Realtek's WinPE driver in `drivers\`. |
| Media: "The IP settings in ...\config\ip.txt are invalid" | Check the three-line format and save `ip.txt` as ANSI / ASCII. |
| Media: the PC boots the media again after the restore | Remove the USB drive / CD during the countdown. Nothing is erased without input. |
| `make_media.bat` stops before erasing a large USB drive | FAT32 over 32 GB on a build PC before build 26300. Use Rufus, `USB_PART_MB` or `USB_FS=exfat` (see [USB drive and ISO](#usb-drive-and-iso)). |
| `make_boot.bat` says the mount folder is not empty | Run `dism /Cleanup-Mountpoints` and empty the folder. |
| Restore failed after erasing | Read the red message. Fix the cause and run `X:\restore\restore.bat` again from the "DVT Console" window, or press a key to reboot. |

A minimized "DVT Console" window is opened in WinPE for troubleshooting.
diskpart logs are written to `%TEMP%\dvt_make_disk*.log`.

## Limitations

- x64 only (ADK `amd64` WinPE).
- IPv4 only.
- The first image (index 1) of `backup.wim` is applied.
- The client local boot needs a working Windows on the client PC to run
  `make_boot.bat`. Use the USB / CD media for PCs without Windows.

## Third-party tools

DVT does not include these tools. Download them from their official sites;
each is distributed under its own license.

- [aria2](https://github.com/aria2/aria2) — BitTorrent download
- [wimlib](https://wimlib.net/) — applying the WIM image
- [NirCmd](https://www.nirsoft.net/utils/nircmd.html) — stopping aria2c
- [Windows ADK and WinPE add-on](https://learn.microsoft.com/windows-hardware/get-started/adk-install) — Microsoft
- [Rufus](https://rufus.ie) — optional, writing the ISO to a USB drive

## License

DVT is released under the [BSD 3-Clause License](LICENSE).
Copyright (c) 2026, zerojinny.

The third-party tools above are not part of DVT and keep their own licenses.

## Disclaimer

DVT erases disks by design. Use it at your own risk, and test it on hardware
you can afford to wipe.
