# DVT — Deploy Via Torrent: Manual

**English** | [한국어](manual.ko.md)

DVT restores a Windows image to many PCs at once over the local network.
Each PC boots a small WinPE image, downloads the backup image with BitTorrent
(aria2), and applies it with wimlib — so every PC that has finished downloading
also uploads to the others, and adding more PCs does not slow the deployment down
the way a single file server would.

A client PC can start DVT in two ways:

- **Client local boot** — `C:\temp\boot\make_boot.bat` runs in the client's Windows, prepares
  the WinPE image for that PC and restarts into it. There is no need to go to the
  client PC to enter anything.
- **USB / CD media** — `02_make_media.bat` makes a boot USB drive or ISO. Use it
  for PCs that cannot start Windows or have no Windows installed. The operator enters the IP address and the disk at each PC.

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
- [Use it with a PC management tool such as Veyon](#use-it-with-a-pc-management-tool-such-as-veyon)
- [Preparing the torrent](#preparing-the-torrent)
- [qBittorrent setup (seeder and tracker)](#qbittorrent-setup-seeder-and-tracker)
- [Choosing the disk to erase](#choosing-the-disk-to-erase)
- [Network](#network)
- [USB / CD media details](#usb--cd-media-details)
- [Configuration](#configuration)
- [Version](#version)
- [Script reference](#script-reference)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Third-party tools](#third-party-tools)
- [License](#license)

---

## How it works

| | Client local boot | USB / CD media |
|---|---|---|
| Build PC | `01_make_pe.bat` → `_output\boot\` folder | `02_make_media.bat` → ISO or USB drive |
| Client PC, before WinPE | `C:\temp\boot\make_boot.bat` in Windows (once per PC) | nothing — boot from the media |
| WinPE main script | `bats\pe\start_dvt.bat` | `bats\Media\pe\start_media.bat` |
| IP address | detected in Windows (static IP → `ip.txt`) | static IP from `ip.txt` (operator types the last octet) or DHCP, order by `DHCP_ENABLE` |
| Disk to erase | detected (disk ID, then the RAW-volume fallback) | typed by the operator |
| Failure before erasing | reboots into the old Windows | waits for a key, then reboots |
| WinPE settings | `bats\pe\config.cmd` (inside `boot.wim`) | `bats\Media\pe\config.cmd` (also on the media, editable on a USB drive) |

Both ways check the gateway, the seeder and the disk space **before** anything
is erased, and both use the same torrent, aria2 profiles, download and restore
(`restore.bat`, `setpc.bat`). The WinPE scripts that both use are kept once,
in `bats\common`.

### Client local boot

```
[1] Build PC ── 01_make_pe.bat
      ADK winpe.wim + DVT scripts + aria2c, wimlib
      → _output\boot\ folder (boot.wim, boot.sdi, host scripts)
         │
         │  copy _output\boot\ to C:\temp\boot on the client
         ▼
[2] Client PC (Windows) ── C:\temp\boot\make_boot.bat
      • detect the IP address (and static DNS) and link speed
      • read the disk ID of the Windows disk
      • export the network drivers
      • add drivers, ip.txt, torrent, aria2.conf, target_disk.txt
        to boot.wim
      • suspend BitLocker for one restart (if it is on)
      • add a one-time boot entry
         │
         │  reboot
         ▼
[3] Client PC (WinPE) ── start_dvt.bat
      • find the target disk (disk ID, then fallback)
      • configure the network
      • check the gateway and seeder
      • check the disk space           ← a failure up to here reboots into
                                          the old Windows, disk untouched
      • erase the disk, create partitions
      • download by torrent (aria2c)
         │
         │  download complete (aria2c keeps seeding)
         ▼
    restore.bat
      • apply the WIM, drivers, bcdboot, setpc.bat
      • record version and image in HKLM\SOFTWARE\DVT
         │
         ▼
    reboot into the restored Windows
```

### USB / CD media

```
[1] Build PC ── 02_make_media.bat
      source\winpe.wim (clean ADK copy)
      + pe_tools, drivers, nircmd
      + bats\Media\pe and bats\common  (only these scripts)
      → _output\media\boot.wim
      + source\adk_media, bats\Media\config, bats\Media\pe\config.cmd
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
      • check the seeder
      • check the disk space          ← nothing is erased if a step up to
                                         here fails
      • erase the disk, create partitions
      • choose the download drive, download by torrent (aria2c)
         │
         │  download complete (aria2c keeps seeding)
         ▼
    restore.bat
      • apply the WIM, drivers, bcdboot
      • move files, setpc.bat, record in HKLM\SOFTWARE\DVT
         │
         ▼
    reboot (remove the USB drive / CD)
```

The media image does **not** use `_output\boot\boot.wim` or the `bats\pe` folder:
`X:\restore` contains only the tools of `pe_tools` and the files of
`bats\Media\pe` and `bats\common`.

## Features

- **BitTorrent distribution** with aria2c; the restore starts as soon as the
  download is complete, and the PC keeps seeding while the image is applied.
- **Safety checks before erasing**: target disk, network, gateway, a real
  seeder download and the disk space are verified first. Nothing is erased
  when one of them fails.
- **Target disk detection** by the disk ID (GPT disk GUID / MBR signature)
  read in the running Windows, with an explicit override and a careful
  fallback for instant recovery programs. Anything ambiguous is an error.
  On the USB / CD media the operator chooses the disk; the boot media itself
  cannot be chosen.
- **BitLocker**: the disk ID works on an encrypted Windows drive, and the
  protection is suspended for one restart, so a PC that returns to Windows
  after a failed check does not ask for the recovery key.
- **UEFI and legacy BIOS**: GPT or MBR layout and the `bcdboot` firmware type
  are chosen automatically. The ISO and the USB drive boot on both.
- **Static IP or DHCP**: a static address (with its static DNS servers) used
  by Windows is carried into WinPE and applied to whichever adapter reaches
  the gateway. The media tries a
  static IP or DHCP first (`DHCP_ENABLE`) and falls back to the other.
- **Network drivers from the running PC** are exported and injected into WinPE,
  so NICs that WinPE does not support out of the box still work.
- **Link-speed profiles**: separate aria2 settings for 100 Mbps and 1 Gbps links.
- **Post-restore tasks**: extra files are copied to `C:\temp` and an optional
  `setpc.bat` runs once at the first Windows start.
- **Restore record**: the DVT version, the image, the date and more are written
  to `HKLM\SOFTWARE\DVT` of the restored Windows (see [Version](#version)).
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
- USB / CD media only: a 64-bit `link.exe` in `bats\Media\pe`. It is used as it is
  (nothing is compiled); `02_make_media.bat` stops when it is missing.

`02_make_media.bat` stores the ADK `Media` folder in `source\adk_media`, and
oscdimg, the boot sector files and bootsect in `source\adk_tools`. Later runs
use only the stored copies (and `source\winpe.wim`, shared with
`01_make_pe.bat`). `01_make_pe.bat` does not have to run first.

**Client PCs**

- Client local boot: Windows 10/11 x64 with administrator rights (to run `make_boot.bat`)
- USB / CD media: a PC that can boot from USB or CD (UEFI or BIOS)
- Wired network connection to the deployment network

**Deployment network**

- A BitTorrent **tracker** reachable from the clients. DHT, peer exchange and
  local peer discovery are disabled in the aria2 profiles, so peers are found
  through the tracker only.
- At least one **seeder** that has the complete `DVT_backup` folder.
- qBittorrent can be both the seeder and the tracker. See
  [qBittorrent setup](#qbittorrent-setup-seeder-and-tracker).

## Repository layout

```
dvt/
├─ 01_make_pe.bat           build the WinPE image (build PC)
├─ 03_make_test_pe.bat      build the test WinPE image (build PC)
├─ 02_make_media.bat        build the USB / CD media: ISO, new USB drive,
│                           or update a USB drive (build PC)
├─ qbittorrent-setup.en.md  qBittorrent seeder and tracker setup manual
├─ qbittorrent-setup.ko.md  the same manual in Korean
├─ doc/                     manual.md / manual.ko.md (README + qBittorrent
│  │                        manual in one file) and their PDFs
│  └─ qbittorrent.ini/      qBittorrent settings files: qbittorrent.ini.1G,
│                           qbittorrent.ini.100
├─ bats/                    all scripts
│  ├─ common/                  WinPE scripts shared by the client local boot,
│  │  │                        the test image and the USB / CD media
│  │  │                        (copied to X:\restore after pe/ or Media/pe/)
│  │  ├─ version.cmd           the DVT version (the only place it is set)
│  │  ├─ restore.bat           apply the image, boot files, record, clean-up
│  │  ├─ start_restore.bat     called by aria2c when the download is complete
│  │  ├─ check_space.bat       disk space check before erasing
│  │  └─ ...                   check_gateway, check_seeder, get_firmware,
│  │                           get_ip, get_target, make_disk, ping_host,
│  │                           set_ip, wait (see Script reference)
│  ├─ host/                    Windows-side scripts (client PC)
│  │  ├─ config.cmd            settings for the host scripts and 01_make_pe.bat
│  │  ├─ make_boot.bat         prepare a client PC and restart into WinPE
│  │  ├─ get_host_ip.bat       IP address, static DNS and static/DHCP detection
│  │  ├─ get_link_speed.bat    link speed -> aria2 profile
│  │  ├─ get_disk_id.bat       disk ID of the Windows disk
│  │  ├─ suspend_bitlocker.bat BitLocker suspended for one restart
│  │  ├─ export_net_drivers.bat
│  │  ├─ prepare_mount_dir.bat
│  │  ├─ set_bcd.bat           one-time WinPE boot entry
│  │  └─ show_ip.bat           IP address in large digits
│  ├─ pe/                      WinPE scripts of the client local boot
│  │  ├─ config.cmd            settings for the WinPE scripts
│  │  ├─ startnet.cmd          WinPE entry point
│  │  ├─ start_dvt.bat         main flow
│  │  ├─ get_disk.bat          disk to erase (disk ID, fallback)
│  │  ├─ aria2.conf.100        aria2 profile for 100 Mbps links
│  │  └─ aria2.conf.1G         aria2 profile for 1 Gbps links
│  ├─ Media/                   USB / CD media
│  │  ├─ config.cmd            settings for 02_make_media.bat (loads host\config.cmd)
│  │  ├─ link.au3              source of link.exe (reference only)
│  │  ├─ config/               copied to <media>\config
│  │  │  ├─ DVT_backup.torrent
│  │  │  ├─ aria2.conf.100
│  │  │  ├─ aria2.conf.1G
│  │  │  ├─ ip.txt             static IP (see ip.txt.example)
│  │  │  └─ ip.txt.example
│  │  ├─ pe/                   WinPE scripts of the media only -> X:\restore
│  │  │  ├─ config.cmd         settings for the media WinPE scripts
│  │  │  │                     (also copied to <media>\config)
│  │  │  ├─ startnet.cmd       find the media, copy config\, start start_media.bat
│  │  │  ├─ start_media.bat    main flow
│  │  │  ├─ get_input.bat      disk list, IP last octet and disk number
│  │  │  ├─ getdiskinfo.bat    disk list
│  │  │  └─ link.exe           aria2.conf by link speed (64-bit, required)
│  └─ test/                    test image scripts (see Test image)
│     ├─ test_config.cmd       FTP server and test settings
│     ├─ startnet.cmd          test WinPE entry point
│     ├─ start_test.bat        test flow: network, gateway, seeder, upload
│     └─ upload_ftp.bat        FTP upload (curl.exe or ftp.exe)
│
│  ── not in the repository, provided by you ──
├─ pe_tools/                aria2c.exe, wimlib-imagex.exe, DLLs -> X:\restore
├─ system32/                optional files -> X:\Windows\System32
├─ drivers/                 optional drivers added to every WinPE image
├─ nircmd-x64/nircmd.exe
│
│  ── created by the build scripts ──
├─ source/                  stored copies of ADK files (first run only)
│  ├─ winpe.wim, boot.sdi   clean copies (01_make_pe.bat, 02_make_media.bat)
│  ├─ adk_media/            the ADK WinPE "Media" folder (02_make_media.bat)
│  └─ adk_tools/            oscdimg.exe, etfsboot.com, bootsect.exe,
│                           efisys.bin (= ADK efisys_noprompt.bin, renamed)
└─ _output/                 build results
   ├─ boot/                 01_make_pe.bat: boot.wim + boot.sdi + host scripts
   │                        + version.cmd
   │                        (copy this folder to the client as C:\temp\boot)
   ├─ boot_test/            03_make_test_pe.bat (copy to the client as C:\temp\boot_test)
   └─ media/                02_make_media.bat: boot.wim of the media, DVT_media.iso
```

## Quick start — client local boot

### 1. Build the WinPE image (build PC)

1. Install the Windows ADK and the WinPE add-on.
2. Put `aria2c.exe`, `wimlib-imagex.exe` and its DLL in `pe_tools\`,
   and `nircmd.exe` in `nircmd-x64\`.
3. Optionally add drivers to `drivers\` (e.g. storage drivers for new hardware,
   or the WinPE driver for [Realtek NICs](#realtek-nics)).
4. Review `bats\pe\config.cmd` (see [Configuration](#configuration)).
5. Run `01_make_pe.bat`. It asks for elevation if needed.

The result is the `_output\boot\` folder: `boot.wim`, `boot.sdi`, a copy of every
file in `bats\host\` and `version.cmd`. This folder is everything a client PC needs besides the torrent.

> The mount and work folders are on the local system drive
> (`C:\WinPE_LocalBuild`). Do not move them into a folder synced by OneDrive,
> Dropbox or similar: sync clients can bring back deleted files after the unmount.

### 2. Prepare the torrent and the seeder

See [Preparing the torrent](#preparing-the-torrent). Start the tracker and the seeder
(with qBittorrent, see [qBittorrent setup](#qbittorrent-setup-seeder-and-tracker)).

### 3. Prepare each client PC

Copy the `_output\boot\` folder from the build PC to `C:\temp\boot`, and the torrent
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

1. detects the IP address (a static address is saved to `ip.txt`: ip, subnet,
   gateway and the static DNS servers, one per line),
2. reads the link speed and picks `aria2.conf.100` or `aria2.conf.1G`,
3. reads the disk ID of the Windows disk,
4. exports the drivers of the connected network adapters,
5. mounts `boot.wim` and adds the drivers, `ip.txt`, the torrent, `aria2.conf`
   and `target_disk.txt` (the disk ID),
6. suspends BitLocker on the Windows drive for one restart, if it is on,
7. adds a one-time WinPE boot entry,
8. shows the IP address in large digits and restarts after a key press.

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
   [Preparing the torrent](#preparing-the-torrent) and
   [qBittorrent setup](#qbittorrent-setup-seeder-and-tracker)).
2. Put the files in `bats\Media\config`: `DVT_backup.torrent`, `aria2.conf.100`,
   `aria2.conf.1G`, and `ip.txt` for a static IP (see [Network](#network)).
3. Review `bats\Media\pe\config.cmd` (see [Configuration](#configuration)).
4. Run `02_make_media.bat` in the build folder as administrator and choose:
   - `1` ISO → `_output\media\DVT_media.iso`, burn it to a CD / DVD
   - `2` USB → the selected **USB** disk is erased and made bootable
     (FAT32 on the whole disk; `USB_FS` and `USB_PART_MB` in `bats\Media\config.cmd`)
   - `3` update → copies new files to an existing DVT USB drive

   `02_make_media.bat iso`, `02_make_media.bat usb` and `02_make_media.bat update` skip
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

`03_make_test_pe.bat` builds a **test** WinPE image that checks a client PC
end to end without touching any disk. Use it to find network, driver and
seeder problems before the real restore. It is started the same way as the
client local boot (`make_boot.bat`).

In WinPE the test image:

1. sets up the network exactly like the restore image (static IP from
   `ip.txt`, otherwise DHCP) and checks the gateway,
2. runs the seeder check (downloads `dvt_check.txt` only, into memory) and the
   disk space check (report only, it never stops the test),
3. writes a report `<ip>.txt` (DVT version, IP, gateway, adapter, link profile,
   seeder, firmware, detected target disk and how it was found, disk space,
   model, `diskpart list disk`, `detail disk` of the target disk,
   `ipconfig /all`),
4. uploads it to the FTP server and reboots back into Windows.

The erase and restore scripts (`make_disk.bat`, `restore.bat`,
`start_restore.bat`, `start_dvt.bat`) are **not** copied into the test image.

Steps:

1. Set the FTP server in `bats\test\test_config.cmd`:
   `FTP_HOST`, `FTP_PORT`, `FTP_USER`, `FTP_PASS` and, optionally, `FTP_DIR`
   (relative to the login folder). Do not use `!` or `"` in these values.
2. Run `03_make_test_pe.bat` on the build PC. The result is the `_output\boot_test\` folder.
3. On the client, copy `_output\boot_test\` to `C:\temp\boot_test`, put the torrent in
   `C:\temp` and run `C:\temp\boot_test\make_boot.bat`. `C:\temp\boot` and
   `C:\temp\boot_test` can be on the client at the same time: `make_boot.bat` always
   uses the `boot.wim` in its own folder.

| Screen | Meaning |
|---|---|
| Green "PASS" | Gateway and seeder OK, `<ip>.txt` uploaded, rebooting |
| Red "TEST FAILED" | A check or the upload failed. Reboots after `FAIL_REBOOT_SEC` (`TEST_FAIL_REBOOT=1`, default); `TEST_FAIL_REBOOT=0` waits for a key |

With `TEST_UPLOAD_FAIL=1` a failed test also uploads `<ip>_FAIL.txt` when an IP
address was set. The FTP client is `curl.exe` (passive mode, creates `FTP_DIR`)
or, as a fallback, `ftp.exe` (active mode only, `FTP_DIR` must exist). WinPE
contains neither: `03_make_test_pe.bat` copies them from the build PC unless you
put them in `pe_tools\` or `system32\`. The FTP settings are built into the
image, so rebuild it after changing them.

## Use it with a PC management tool such as Veyon

DVT needs two things on every client before WinPE takes over: the
`C:\temp\boot` folder with the torrent, and one run of `make_boot.bat`.
Doing that PC by PC is the slowest part of a deployment. A classroom / PC
management tool like [Veyon](https://veyon.io) (free, open source) lets you
do it for the whole room from one screen:

| DVT step | Without a management tool | With Veyon |
|---|---|---|
| Turn the PCs on | Walk to every PC | **Power on** (Wake-on-LAN) for all PCs |
| Copy `C:\temp\boot` and the torrent | USB stick at every PC | **File transfer** to all PCs, then **Run program** to put the files in `C:\temp` |
| Run `make_boot.bat` | Log in and start it on every PC | **Run program** on all PCs at once |
| Check IP and link speed | Read every monitor | `make_boot.bat` shows the IP in large digits and colors the console by link speed — visible at a glance in Veyon's **monitoring** view |
| Restart into WinPE | Press a key on every PC | **Remote control**, or **Restart** all PCs |
| Confirm the restore | Walk around again | Restored PCs show up in Veyon again (if the Veyon service is in the image) |

The same works for the **test image**: run it on the whole room first, collect
the `<ip>.txt` reports from FTP, fix the failing PCs, then deploy for real.

Things to keep in mind:

- `make_boot.bat` needs **administrator rights**. Approve the elevation prompt
  through Veyon's remote control, or run it with an account that is an
  administrator.
- Veyon puts transferred files in the user's profile folder by default; move
  them to `C:\temp` (e.g. with a small script run through **Run program**).
- While a PC is in **WinPE** the Veyon service is not running, so Veyon cannot
  show it. Read the PC's own screen, or use the test image's FTP reports.
- Put the Veyon service into the **backup image** (and, if needed, set it up
  in `setpc.bat`), so every restored PC can be managed right away.

## Preparing the torrent

The torrent must contain a single top folder named `DVT_backup` (`DL_NAME`):

```
DVT_backup\
├─ backup.wim        the Windows image (index WIM_INDEX, default 1) required
├─ dvt_check.txt     small file (a few KB) for the seeder check    required
├─ drivers\          drivers added to the restored Windows         optional
└─ files\            copied to C:\temp of the restored Windows     optional
   └─ setpc.bat      runs once at the first Windows start          optional
```

- Create `dvt_check.txt` **before** creating the torrent. WinPE downloads only
  this file to prove that a seeder is reachable before it erases anything.
- Put the tracker URL in the torrent. Alternatively set
  `SEEDER_EXTRA_OPTS=--bt-tracker=http://...` in `bats\pe\config.cmd` or
  `bats\Media\pe\config.cmd` (this is used for the seeder check only; the main
  download reads the torrent and `aria2.conf`).
- Save the torrent as `DVT_backup.torrent`: in `C:\temp` of each client for the
  client local boot, in `bats\Media\config` for the media.
- `backup.wim` may hold several images. `WIM_INDEX` in `bats\pe\config.cmd`
  and `bats\Media\pe\config.cmd` selects the one to apply (default `1`). List
  them with `wimlib-imagex info backup.wim`. A wrong index stops the restore
  with a message before the image is applied.
- When the client uses a static IP, `ip.txt` (ip, subnet, gateway, and the DNS
  servers when known) is also copied to `C:\temp` of the restored Windows, so
  `setpc.bat` can set the address again.

> [!WARNING]
> `dvt_check.txt` must **not be an empty 0-byte file.** There is no data to
> download, so aria2c "completes" it without reaching any seeder and the check
> would prove nothing. `check_seeder.bat` therefore fails the check, before
> the disk is erased, when `dvt_check.txt` in the torrent is 0 bytes ("The
> seeder check file in the torrent is empty"). Always put a file with content
> (a few KB) in the folder before you create the torrent. If you change the
> file, create the torrent again.

## qBittorrent setup (seeder and tracker)

One qBittorrent PC can serve the image (seeder) and broker the peer list
(embedded tracker) at the same time. The settings differ between a 100 Mbps or
slower network and a 1 Gbps or faster network, and each is split into required
and recommended items.

> [!IMPORTANT]
> This manual is written for the **standard installer of qBittorrent 5.3.0**
> (`qbittorrent_5.3.0_x64_setup.exe`, libtorrent 2.1). From 5.3.0 the standard
> installer is based on libtorrent 2.1.x. The lt12 installer
> (`qbittorrent_5.3.0_lt12_x64_setup.exe`) uses libtorrent 1.2 and shows a few
> different items; see [lt12 build (libtorrent 1.2)](#lt12-build-libtorrent-12).

> [!NOTE]
> The qBittorrent 5.3.0 release notes say that the libtorrent 2.1 backend has
> worse read performance than 1.2, which can lower upload speed on a heavy
> seeder. If the seeder cannot fill a 1 Gbps or faster link after the settings
> in **1 Gbps or faster** are applied, try the lt12 build.

### Overview

In DVT, one qBittorrent PC acts as both the **seeder** (serves the source image) and the **embedded tracker** (brokers the peer list). Clients booted into WinPE download the image with aria2 and exchange pieces with each other.

- At 100 Mbps or slower, the **network bandwidth** is the bottleneck. The goal is to save seeder upload and let clients share pieces among themselves.
- At 1 Gbps or faster, the seeder's **disk, CPU and socket buffers** are the bottleneck. The goal is to raise buffers and I/O threads so the link stays full.

How to use: apply the common settings in **Common settings** first, pick your environment with **Choosing the environment**, then apply **100 Mbps or slower** or **1 Gbps or faster** on top. Required items are those whose absence makes deployment fail or stall; recommended items improve stability and efficiency. Names follow the qBittorrent 5.3.0 **English UI**: settings are under **Tools → Options**, torrent creation under **Tools → Torrent Creator**. Wording may differ slightly between versions. For the Korean UI, see the Korean edition of this manual ([manual.ko.md](manual.ko.md)). Instead of changing each option, you can also replace the settings file with a [ready-made one](#using-the-ready-made-settings-files-qbittorrentini).

### Common settings (both environments)

Turn on the embedded tracker, lock the protocol to TCP, and create torrents in **V1 format**. aria2 supports neither μTP nor BitTorrent v2.

#### Required

| Page | Setting | Value | Why |
| --- | --- | --- | --- |
| Advanced | Enable embedded tracker | Checked | qBittorrent acts as the tracker |
| Advanced | Embedded tracker port | 9000 (default) | Port used in the torrent's tracker URL |
| Connection | Peer connection protocol | TCP | aria2 does not support μTP |
| Connection | Port used for incoming connections | Fixed port (e.g. 6881) | Keeps firewall rules stable |
| BitTorrent | Torrent Queueing | Unchecked | Keeps the deployment torrent out of the queue |
| BitTorrent | Seeding Limits (ratio / seeding time) | All unchecked | Seeding must not stop mid-deployment |
| Torrent Creator | Torrent format | **V1** | aria2 cannot download V2 or Hybrid torrents |
| Torrent Creator | Tracker URLs | `http://<SEEDER_IP>:9000/announce` | Embedded tracker address; use the seeder's exact LAN IP |
| Torrent Creator | Start seeding immediately | Checked | Seeding starts as soon as the torrent is created |
| Torrent Creator | Piece size | See **100 Mbps or slower** or **1 Gbps or faster** | Balances piece count and hashing load |

**Firewall (seeder PC, elevated Command Prompt)** — required

```
netsh advfirewall firewall add rule name="DVT qBittorrent tracker" dir=in action=allow protocol=TCP localport=9000
netsh advfirewall firewall add rule name="DVT qBittorrent peer" dir=in action=allow protocol=TCP localport=6881
```

If you change either port, change `localport` to match. Add these port rules even if a program-level rule exists, because a network on the Public profile can still be blocked.

#### Recommended

| Page | Setting | Value | Why |
| --- | --- | --- | --- |
| Advanced | Network interface / Optional IP address to bind to | Deployment LAN adapter / seeder IP | Effectively required on multi-NIC seeders; prevents traffic leaving on the wrong network |
| Advanced | Enable port forwarding for embedded tracker | Unchecked | LAN only |
| Connection | Use UPnP / NAT-PMP port forwarding from my router | Unchecked | LAN only |
| BitTorrent | Enable DHT / Enable Peer Exchange (PeX) | Unchecked | Peers are found through the tracker; avoids outside exposure |
| BitTorrent | Enable Local Peer Discovery | Unchecked (if the tracker works) | Redundant with the tracker; a fallback when troubleshooting |
| BitTorrent | Encryption mode | Allow encryption | Compatible with aria2; forcing it costs CPU |
| BitTorrent | Enable anonymous mode | Unchecked | Peer identification is needed |
| Speed | Schedule the use of alternative rate limits | Unchecked | Prevents sudden slowdowns during deployment |
| Behavior | Power Management: Inhibit system sleep when torrents are seeding | Checked | Keeps the seeder awake during deployment |
| Torrent Creator | Private torrent | Checked | DHT and PeX stay off for this torrent regardless of global settings |

### 100 Mbps or slower

Keep seeder upload slots low so each peer completes pieces quickly and passes them on to other clients. A 100 Mbps link tops out around 12 MB/s, so with more than 10 clients the seeder alone drops to roughly 1 MB/s per client.

#### Required

| Page | Setting | Value | Why |
| --- | --- | --- | --- |
| Connection | Maximum number of upload slots per torrent | 8 | Fewer slots mean faster per-peer speed and quicker piece completion for redistribution |
| Connection | Global maximum number of upload slots | 20 | Keeps the per-torrent slots from being capped globally |
| Torrent Creator | Piece size | 4 MiB | Smaller pieces let clients start exchanging sooner |

#### Recommended

| Page | Setting | Value | Why |
| --- | --- | --- | --- |
| Speed | Global Rate Limits → Upload | 11000 KiB/s (about 90 Mbps) | Leaves headroom for remote management and tracker replies |
| Speed | Apply rate limit to peers on LAN | Checked when using the limit above | Otherwise LAN peers are not limited |
| Speed | Apply rate limit to transport overhead | Checked when using the limit above | Limits by actual link usage |
| Connection | Global maximum number of connections | 200 | Comfortably above the peer count |
| Connection | Maximum number of connections per torrent | 100 | |
| Advanced | Upload slots behavior | Fixed slots | Locks the slot count to the values above |
| Advanced | Upload choking algorithm | Round-robin | Spreads pieces evenly across clients |
| Advanced | Disk IO read mode | Enable OS cache | Fewer disk re-reads when the same piece goes to many peers |

Leave all other Advanced settings at their defaults. Disk and CPU are not the bottleneck here.

### 1 Gbps or faster

Remove all rate limits and raise upload slots, send buffers and disk I/O so the seeder fills the link. 1 Gbps is about 119 MB/s, which default send buffers and an HDD often cannot sustain.

#### Required

| Area | Setting | Value | Why |
| --- | --- | --- | --- |
| Hardware | Image storage | SSD or faster (NVMe for 10 Gbps) | An HDD cannot keep up with random reads from many peers |
| Hardware | Seeder NIC and switch uplink | 1 Gbps or faster | A 100 Mbps uplink means a mixed network (**Choosing the environment**) |
| Speed | Global Rate Limits → Upload / Download | 0 (unlimited) | |
| Connection | Global maximum number of upload slots | Unchecked (unlimited) | Bandwidth allows sending to every peer at once |
| Connection | Maximum number of upload slots per torrent | 50 or unchecked | |
| Advanced | Send buffer watermark | 5120 KiB (default 500) | Prevents send buffer starvation on fast links |
| Advanced | Send buffer low watermark | 1024 KiB (default 10) | |
| Advanced | Send buffer watermark factor | 150 % (default 50) | |
| Torrent Creator | Piece size | 8 MiB (16 MiB for images over 50 GB) | Fewer pieces and less hashing load |

#### Recommended

| Area | Setting | Value | Why |
| --- | --- | --- | --- |
| Hardware | Seeder RAM | 16 GB or more | Pieces stay in the OS cache, reducing disk reads |
| NIC properties | Energy Efficient Ethernet / Green Ethernet | Disabled | Reduces speed fluctuation during high-speed transfers |
| NIC properties | Jumbo Packet | Disabled (keep default) | Every WinPE driver and switch must support it, otherwise connections break |
| Connection | Global maximum number of connections | 500 | |
| Connection | Maximum number of connections per torrent | 300 | |
| Advanced | Upload choking algorithm | Round-robin | |
| Advanced | Asynchronous I/O threads | 16 (default 10) | More concurrent read requests |
| Advanced | Hashing threads | Half the CPU core count | Faster torrent creation and rechecks |
| Advanced | Physical memory (RAM) usage limit | 4096 MiB or more (to fit RAM) | Room for caching |
| Advanced | Disk queue size | Default (102400 KiB) | 5.3.0 raised the default to 100 MiB for libtorrent 2.1; do not lower it (lt12 build: see below) |
| Advanced | Disk IO type | Default | Other choices: Memory mapped files, POSIX-compliant, Simple pread/pwrite, Pread/pwrite. If upload falls short or memory use is excessive, compare with Pread/pwrite (restart required) |
| Advanced | Disk IO read mode | Enable OS cache | Repeatedly requested pieces are served from RAM |
| Advanced | Socket backlog size | 100 (default 30) | Handles many clients connecting at once |
| Advanced | Outgoing connections per second | 50 (default 30) | |

### Choosing the environment and mixed networks

Pick the settings by the **slowest link on the path from the seeder to the switch**. Client speed only affects how fast clients exchange pieces with each other.

| Seeder path | Client links | Settings to apply | Note |
| --- | --- | --- | --- |
| 100 Mbps or slower | 100 Mbps or slower | **100 Mbps or slower** | |
| 100 Mbps or slower | 1 Gbps or faster | **100 Mbps or slower** | Fast client-to-client exchange greatly shortens total time |
| 1 Gbps or faster | 100 Mbps or slower | **1 Gbps or faster** | Lower hardware demand; an HDD can work |
| 1 Gbps or faster | 1 Gbps or faster | **1 Gbps or faster** | SSD required |

Check both the seeder NIC link speed (`ncpa.cpl` → adapter Status) and the switch uplink spec. The lower of the two decides.

### Using the ready-made settings files (qbittorrent.ini)

The `doc\qbittorrent.ini` folder contains qBittorrent settings files with the
settings above already applied. Replacing the settings file applies the
**Common settings** and the required and recommended items of one environment
at once, instead of changing each option by hand.

| File | Settings | Notes |
| --- | --- | --- |
| `qbittorrent.ini.1G` | Common settings + **1 Gbps or faster** | For a seeder with 8 cores and 16 GB RAM: hashing threads 4, physical memory (RAM) usage limit 4096 MiB; disk queue size left at the default |
| `qbittorrent.ini.100` | Common settings + **100 Mbps or slower** | Advanced settings at their defaults |

Both files are for qBittorrent 5.3.0 (`Meta\MigrationVersion=12`, the settings
version of 5.3.0). The lt12 build (libtorrent 1.2) ignores libtorrent 2.x items
such as hashing threads, the physical memory limit and the torrent format; with
the lt12 build and `qbittorrent.ini.1G`, set **Disk queue size** to 8192 KiB by
hand. All other settings, such as window sizes and the language, go back to
their defaults.

**Location of the settings file**

| Installation | Folder |
| --- | --- |
| Portable version | `<qBittorrent folder>\Profile\qBittorrent\config` |
| Installed version | `%userprofile%\AppData\Roaming\qBittorrent` |

**How to apply**

1. **Exit qBittorrent completely**, including the tray icon. If the file is
   replaced while qBittorrent runs, qBittorrent overwrites it with the old
   settings when it exits.
2. Back up `qBittorrent.ini` in that folder under another name (e.g.
   `qBittorrent.ini.bak`).
3. Copy the file for your environment into the folder and rename it to
   `qBittorrent.ini`.
4. Start qBittorrent and **change the items below by hand** to match the
   seeder PC.

> [!IMPORTANT]
> The IP in the files (`203.244.132.147`) is an example. If it is not changed
> to the seeder's real LAN IP, qBittorrent accepts no connections and the
> clients cannot reach the tracker.

| Menu | Setting | Set to | Why |
| --- | --- | --- | --- |
| Tools → Options → Advanced | Network interface | The LAN adapter used for deployment | Adapter IDs differ on every PC, so the file cannot set it |
| Tools → Options → Advanced | Optional IP address to bind to | The seeder's LAN IP | The file contains an example IP |
| Tools → Torrent Creator | Tracker URLs | `http://<SEEDER_IP>:9000/announce` | The file contains an example IP |

Restart qBittorrent after changing the network interface or the IP. When the
execution log (**View → Log**) shows it listening only on the seeder's IP, the
binding works. The firewall rules (**Common settings**) and the hardware items
of **1 Gbps or faster** (adapter properties, SSD) cannot be set by the file;
apply them separately.

### Pre-deployment checklist and troubleshooting

#### Pre-deployment checklist

- [ ] The embedded tracker is on, and `netstat -an | find ":9000"` on the seeder shows LISTENING
- [ ] The firewall has inbound allow rules for the tracker port (9000) and peer port (6881)
- [ ] The torrent was created with Torrent format V1 (lt12 build: Optimize alignment unchecked)
- [ ] The tracker URL IP matches the seeder's current LAN IP
- [ ] The torrent is Seeding, not Queued or Stopped
- [ ] The required items from **100 Mbps or slower** or **1 Gbps or faster** are applied for your environment
- [ ] Sleep, screen saver and automatic update restarts on the seeder will not hit the deployment window

#### Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| aria2 cannot open the torrent or reports a metadata error | V2 or Hybrid torrent | Recreate it with Torrent format set to V1 |
| Clients cannot reach the tracker | Firewall, wrong IP in the tracker URL, embedded tracker off | Rerun the firewall commands in **Common settings**; check the tracker URL and Enable embedded tracker |
| A `.pad` folder or empty files appear on clients | lt12 build: Optimize alignment was on | Uncheck it and recreate the torrent |
| Seeder upload is 0 and no peers connect | Bound NIC or IP is not on the deployment network | Check Network interface and Optional IP address to bind to under Advanced |
| Stuck at tens of MB/s on 1 Gbps | Upload slot limits, default send buffers, HDD, LAN peer rate limit | Recheck **1 Gbps or faster** values; move the image to an SSD |
| Every client downloads only from the seeder, never from each other | WinPE firewall blocks inbound client connections | Make sure the client script runs `wpeutil DisableFirewall` |

### lt12 build (libtorrent 1.2)

The lt12 installer `qbittorrent_5.3.0_lt12_x64_setup.exe` is built with
libtorrent 1.2. Everything in this manual applies, except these items:

| Page | Setting | Standard build (this manual) | lt12 build |
| --- | --- | --- | --- |
| Torrent Creator | Torrent format | Shown; select **V1** | Not shown; torrents are always V1 |
| Torrent Creator | Optimize alignment | Not shown | Shown; **uncheck it** (padding files may appear on clients as real files) |
| Advanced | Hashing threads | Shown | Not available |
| Advanced | Disk IO type (requires restart) | Shown | Not available |
| Advanced | Disk queue size (1 Gbps or faster) | Default 102400 KiB; keep it | Default 1024 KiB; set **8192 KiB** |
| Advanced | Physical memory (RAM) usage limit | Shown | Not available |
| Advanced | Disk cache / Disk cache expiry interval | Not available | Shown; keep the defaults |
| Advanced | Coalesce reads & writes | Not available | Shown; keep the default |

aria2 cannot download V2 or Hybrid torrents, so with the standard build always
check Torrent format; with the lt12 build check Optimize alignment instead.

## Choosing the disk to erase

### Client local boot

`get_disk.bat` decides which disk is erased, in this order:

1. **`FORCE_DISK`** in `bats\pe\config.cmd`, if set.
2. The disk whose **disk ID** matches `target_disk.txt` in the image.
   `make_boot.bat` reads the ID of the disk that holds the running Windows
   (the GPT disk GUID, or the MBR signature) and writes it into `boot.wim`;
   WinPE compares it with the `Disk ID` that `diskpart` shows for every disk.
   Disk numbers can differ between Windows and WinPE, the disk ID does not,
   and it can be read even when the Windows drive is locked by BitLocker.
3. Only when `AUTO_DISK_FALLBACK=1` (there is no `target_disk.txt`, or no
   disk has that ID):
   1. the disk of the **only** unformatted (RAW) volume, or
   2. the **only** disk in the PC.

   This fallback is meant for PCs with an **instant recovery program**
   (a "reboot to restore" program). Such programs can make the Windows
   partition look RAW in WinPE, and some of them also change what the disk
   ID looks like from Windows, so the disk ID may not match.

A disk ID on more than one disk (e.g. cloned disks), more than one RAW volume,
or more than one disk is treated as an error, so DVT never guesses. Set
`AUTO_DISK_FALLBACK=0` to require the disk ID (or `FORCE_DISK`).

> [!NOTE]
> The disk ID is compared with the English output of `diskpart`. Keep
> `PE_LANG=en-us` (the default) in `bats\host\config.cmd`; with another WinPE
> language the disk ID is not found and only the fallback (step 3) is left.

### BitLocker

When BitLocker protects the Windows drive, `make_boot.bat` suspends the
protection for **one restart** (`manage-bde -protectors -disable C:
-RebootCount 1`). If a check fails in WinPE and the PC returns to Windows, it
starts without asking for the recovery key, and Windows turns the protection
back on by itself. When the restore runs, the disk is erased anyway.
`BITLOCKER_SUSPEND=0` in `bats\host\config.cmd` leaves BitLocker as it is.

The disk ID (step 2 above) can be read on a BitLocker drive, so the disk is
found whether the drive is encrypted or not.

### USB / CD media

There is no automatic detection. `get_input.bat` shows the disk list and the operator
types the disk number (`R` scans the disks again). The disk must exist, and
the disk of the boot media cannot be selected. With `MEDIA_CONFIRM=1`
(default) the operator confirms with `Y` before the disk is erased.

With **`FORCE_DISK`** set in `bats\Media\pe\config.cmd` (or in
`<media>\config\config.cmd`), that disk is erased and the operator does not
choose it: with a static IP only the last octet is entered (e.g. `150`), with
DHCP nothing is entered. With `MEDIA_CONFIRM=0` as well, a DHCP boot runs
without any input. If the disk does not exist or is the boot media, a warning
is shown and the operator selects the disk; answering `N` to the
confirmation does the same.

## Network

### Client local boot

- **DHCP** (default): WinPE waits for an address (`DHCP_WAIT_TRIES` × 2 s) and
  uses the default route with the lowest metric.
- **Static IP**: if Windows used a static address, `make_boot.bat` stores the
  address, subnet mask, gateway and the static DNS servers in `ip.txt` inside
  the image, one value per line:
  ```
  203.244.132.150
  255.255.255.0
  203.244.132.1
  168.126.63.1
  168.126.63.2
  ```
  Lines 4 and 5 (DNS) are written only when Windows has static DNS servers;
  without them WinPE uses `NET_DNS1/2`. An `ip.txt` with the address only gets
  `NET_MASK` and the gateway `x.x.x.1`. WinPE tries every connected adapter,
  keeps the first one that reaches the gateway (and `NET_TEST_HOST`, if set)
  and returns the others to DHCP.
- **Link speed**: `make_boot.bat` measures it. Links of 1 Gbps or faster get
  `aria2.conf.1G`; everything else gets `aria2.conf.100`. The console color on
  the client shows which one was chosen (`COLOR_LINK_*` in `bats\host\config.cmd`).

### USB / CD media

The order is set by `DHCP_ENABLE` in `bats\Media\pe\config.cmd`.

| `DHCP_ENABLE` | `ip.txt` | What happens |
|---|---|---|
| `0` or empty (default) | exists | **Static IP first.** The operator enters the last octet and the disk number; the address is applied and the gateway is tested. If the test fails, every adapter is switched to DHCP and the DHCP gateway is tested. When that works, WinPE shows that the static IP failed but DHCP succeeded and continues with DHCP and the disk selected before (`DHCP_FALLBACK_CONFIRM=1`: asks first, `N` stops). |
| `1` | exists | **DHCP first.** WinPE waits up to `DHCP_FIRST_TRIES` × 2 s (20 s) for a DHCP address and tests its gateway. When both work, only the disk number is asked. Otherwise the static IP is used: the operator enters the last octet and the disk number, and the address is applied and tested. |
| any | missing | **DHCP only.** Only the disk number is asked. |

When no way works, WinPE stops before anything is erased and waits for a key
to reboot.

`ip.txt` in `bats\Media\config` has the same format as above, but line 1 is a
base address: only its first three octets are used (`ipr`), and the operator
types the last one.

```
203.244.132.0
255.255.255.0
203.244.132.1
168.126.63.1
168.126.63.2
```

Line 2 (subnet), line 3 (gateway) and lines 4-5 (DNS) may be omitted
(`NET_MASK`, `ipr.1` and `NET_DNS1/2`), so an address-only `ip.txt` also works.
Lines starting with `#` are ignored. Save it as ANSI / ASCII, not UTF-8 with
BOM.

When the static IP works, a new `ip.txt` with the values actually applied (ip,
subnet, gateway, DNS) is written and moved to `T:\temp\ip.txt` for `setpc.bat`.
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
> `01_make_pe.bat` and `02_make_media.bat`. The drivers in `drivers\` go into every
> WinPE image.
>
> Emptying `NETDRV_EXCLUDE` to export Realtek's Windows driver is not
> recommended.

## USB / CD media details

### config folder

`02_make_media.bat` copies these files from `bats\Media\config` to `<media>\config`,
plus `bats\Media\pe\config.cmd`. When WinPE starts, `startnet.cmd` copies
`<media>\config` to `X:\restore`, so on a USB drive you can change them
without rebuilding. `<media>\config\config.cmd` replaces the `config.cmd`
inside `boot.wim`, so its settings (`DHCP_ENABLE`, `MEDIA_CONFIRM`, ...) apply
at the next boot. On a CD, change `bats\Media\config` or `bats\Media\pe\config.cmd` and
rebuild.

| File | Purpose |
|---|---|
| `DVT_backup.torrent` | required; its `dvt_check.txt` must not be empty (see [Preparing the torrent](#preparing-the-torrent)) |
| `aria2.conf.1G`, `aria2.conf.100` | required; `link.exe` renames the one for the link speed to `aria2.conf` |
| `ip.txt` | static IP base; tried first or as fallback (`DHCP_ENABLE`) |
| `config.cmd` | copied from `bats\Media\pe\config.cmd`; WinPE settings |

`bats\Media\pe\config.cmd` on the build PC is the original: making or updating a
USB drive (`2`, `3`) copies it over a `config.cmd` that was changed on the
drive.

### USB drive and ISO

- A new USB drive gets one **FAT32** partition (`USB_FS=fat32`), which boots
  on UEFI and BIOS PCs (BIOS through `bootsect`). The partition size is
  `USB_PART_MB` in MB; empty (the default) uses the whole disk.
- By default the whole disk is formatted as FAT32 at any size, whatever the
  Windows build.
- If the format fails on a drive over 32 GB, `02_make_media.bat` shows the
  diskpart output and a hint. The disk has already been erased at that point.
  Updating Windows is recommended; otherwise use one of the choices below.
- **If you cannot update Windows, recommended:** make the ISO (`1`) and
  write it to the USB drive with [Rufus](https://rufus.ie). Rufus formats the
  whole drive as FAT32 at any size, and the drive boots on UEFI and BIOS PCs.
  In Rufus select the USB drive, select `_output\media\DVT_media.iso`, keep the
  file system **FAT32**, and write it in ISO image mode. The `config` folder is
  part of the ISO, so the drive has the same files as one made with `2`; later
  you can update it with `3`.
- Other choices without a Windows update: `USB_PART_MB=32000` (the rest of the disk
  stays unused) or `USB_FS=exfat` (whole disk, but many UEFI firmwares do not
  boot from exFAT).
- `02_make_media.bat` only writes to disks whose type is **USB**, never to the
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

### Shared scripts

The WinPE scripts that the client local boot and the media both need are kept
once, in `bats\common`. `01_make_pe.bat`, `03_make_test_pe.bat` and `02_make_media.bat`
copy `bats\common` into the image after `bats\pe` or `bats\Media\pe`, so a
change there reaches every image at the next build. The few differences
(the boot media is never a download drive, `pc_ip.txt` is moved instead of
copied, the reminder to remove the media) are handled inside the shared
scripts: `MEDIA_DRV` is set only by the `startnet.cmd` of the media.

If a script with the same name as one in `bats\common` is still in `bats\pe`
or `bats\Media\pe` (left from an older version), the build prints a warning
and the `bats\common` copy is used. Delete the old copy.

## Configuration

Change values in these files, not in the scripts.

| File | Used by |
|---|---|
| `bats\host\config.cmd` | client PC (`make_boot.bat`) and build PC (`01_make_pe.bat`) |
| `bats\pe\config.cmd` | WinPE of the client local boot |
| `bats\Media\config.cmd` | `02_make_media.bat` (loads `bats\host\config.cmd` first) |
| `bats\Media\pe\config.cmd` | WinPE of the USB / CD media |

### `bats\host\config.cmd` (client PC and build PC)

| Variable | Default | Description |
|---|---|---|
| `WORK_DIR` | `C:\temp` | Working folder on the client PC |
| `BOOT_WIM` | `boot.wim` in the folder of `make_boot.bat` (`C:\temp\boot` or `C:\temp\boot_test`) | WinPE image to customize and boot |
| `TORRENT` | `%WORK_DIR%\DVT_backup.torrent` | Torrent copied into the image |
| `NETDRV_EXCLUDE` | `Realtek` | Regex; matching network drivers are not exported. Empty = export all. For Realtek, put the WinPE driver in `drivers\` (see [Realtek NICs](#realtek-nics)) |
| `BOOT_MOUNT_DIR` | `%SystemDrive%\DVT_BootMount` | Local mount folder |
| `DISK_ID_NAME` | `target_disk.txt` | File in the image that holds the disk ID (must match `DISK_ID_FILE` in `bats\pe\config.cmd`) |
| `BITLOCKER_SUSPEND` | `1` | `1` = suspend BitLocker on the Windows drive for one restart, `0` = leave it |
| `BOOT_ENTRY_NAME` | `DVT WinPE` | Name of the boot menu entry |
| `BCD_CLEANUP_MODE` | `2` | Removal of the boot entry: `1` from WinPE, `2` at the next Windows boot (scheduled task), `0` never |
| `REBOOT_DELAY_SEC` | `10` | Delay before the restart into WinPE |
| `ADK_PE_DIR`, `PE_LANG` | ADK amd64, `en-us` | Source of `winpe.wim` |
| `BUILD_LOCAL` | `%SystemDrive%\WinPE_LocalBuild` | Local build folder |
| `PE_SCRATCH_MB` | `512` | WinPE scratch space |
| `PE_COMMON_DIR` | `bats\common` | Shared WinPE scripts, copied into every image |

### `bats\pe\config.cmd` (WinPE, client local boot)

| Variable | Default | Description |
|---|---|---|
| `DL_NAME` | `DVT_backup` | Top folder inside the torrent |
| `WIM_NAME` | `backup.wim` | Image file inside that folder |
| `WIM_INDEX` | `1` | Index of the image inside `WIM_NAME` to restore (1 = first image) |
| `FORCE_DISK` | *(empty)* | Disk number to erase; empty = detect |
| `DISK_ID_FILE` | `X:\restore\target_disk.txt` | Disk ID written by `make_boot.bat`; checked first |
| `AUTO_DISK_FALLBACK` | `1` | When the disk ID does not identify the disk, allow the RAW-volume / single-disk fallback (instant recovery programs) |
| `TDRV`, `SDRV` | `T`, `S` | Letters of the new Windows and system partitions |
| `EFI_SIZE_MB`, `MSR_SIZE_MB`, `BIOS_SYS_SIZE_MB` | `260`, `16`, `500` | Partition sizes |
| `NET_MASK` | `255.255.255.0` | Mask for a static IP when `ip.txt` has no subnet line |
| `NET_DNS1`, `NET_DNS2` | `8.8.8.8`, `8.8.4.4` | DNS for a static IP when `ip.txt` has no DNS lines (4-5) |
| `NET_TEST_HOST` | *(empty)* | Extra host that must answer (use the tracker or seeder) |
| `SET_IP_RETRIES`, `SET_IP_RETRY_SEC` | `3`, `10` | Static IP: when no adapter reaches the gateway, all adapters are tried again this many times, after this many seconds |
| `DHCP_WAIT_TRIES` | `30` | DHCP wait, in 2-second steps |
| `CHECK_FILE` | `dvt_check.txt` | File used for the seeder check |
| `SEEDER_TIMEOUT_SEC` | `60` | Seeder check timeout per attempt |
| `SEEDER_TRIES_1G`, `SEEDER_TRIES_100` | `2`, `5` | Seeder check attempts at 1 Gbps or faster / at 100 Mbps or slower (also when the speed is unknown). `make_boot.bat` writes the link profile to `link_profile.txt` in the image |
| `SEEDER_EXTRA_OPTS` | *(empty)* | Extra aria2c options for the seeder check |
| `SPACE_CHECK` | `1` | Disk space check before erasing: `1` = stop when too small, `2` = warn only, `0` = off |
| `APPLIED_SIZE_MB` | *(empty)* | Size of the applied image in MB. Empty = estimated (`APPLIED_SIZE_PCT`) |
| `APPLIED_SIZE_PCT` | `200` | Estimated applied size, in percent of the download size |
| `SPACE_MARGIN_MB` | `2048` | Space kept free on the Windows partition |
| `BCD_LOCALE` | `ko-kr` | Locale passed to `bcdboot` |
| `FAIL_REBOOT_SEC`, `DONE_REBOOT_SEC` | `10`, `5` | Reboot delays |

### `bats\Media\config.cmd` (02_make_media.bat)

| Variable | Default | Description |
|---|---|---|
| `MEDIA_LABEL` | `DVT` | Volume label of the ISO and the USB drive |
| `USB_FS` | `fat32` | File system of a new USB drive: `fat32` or `exfat` |
| `USB_PART_MB` | *(empty)* | Size of the USB partition in MB; empty = the whole disk |
| `MEDIA_OUT_DIR` | `_output\media` in the build folder | Result folder (`boot.wim`, `DVT_media.iso`) |

### `bats\Media\pe\config.cmd` (WinPE, USB / CD media)

It has the same variables as `bats\pe\config.cmd` except `AUTO_DISK_FALLBACK`
and `DISK_ID_FILE` (the operator chooses the disk), plus:

| Variable | Default | Description |
|---|---|---|
| `DHCP_ENABLE` | `0` | `0` / empty = static IP (`ip.txt`) first, `1` = DHCP first |
| `DHCP_FIRST_TRIES` | `10` | `DHCP_ENABLE=1` with `ip.txt`: 2-second tries for DHCP before the static IP |
| `DHCP_FALLBACK_CONFIRM` | `0` | Static IP first, static IP failed but DHCP works: `0` = continue with DHCP, `1` = ask Y/N |
| `LINK_FALLBACK` | `100` | Profile when `link.exe` is missing or fails |
| `OCTET_MIN`, `OCTET_MAX` | `1`, `254` | Allowed last octet |
| `FORCE_DISK` | *(empty)* | Disk number to erase; empty = the operator enters it ([USB / CD media](#usb--cd-media-1)) |
| `MEDIA_CONFIRM` | `1` | Ask Y/N before erasing |
| `DONE_REBOOT_SEC` | `15` | Time to remove the media |

### Disk space check

`check_space.bat` runs after the seeder check, before anything is erased. It
compares the size of the new Windows partition (disk size minus the system
partitions and `SPACE_MARGIN_MB`) with what the restore needs:

- the download goes to **another** local drive with enough free space
  (`get_target.bat`, volumes of the target disk are skipped): the applied
  image only;
- otherwise the download goes to **`T:`** itself: the download **and** the
  applied image.

The applied size is `APPLIED_SIZE_MB` when set. Otherwise it is estimated as
`APPLIED_SIZE_PCT` percent of the torrent size (default 200 %, a
conservative value for a compressed WIM). For the exact value run
`wimlib-imagex info backup.wim <index>` and divide `Total Bytes` by 1048576.
If the torrent or disk size cannot be read, the check is skipped with a
warning.

### aria2 profiles

`bats\pe\aria2.conf.100` and `bats\pe\aria2.conf.1G` (for the media:
`bats\Media\config\aria2.conf.*`) are ordinary aria2 configuration files. Both seed
for up to 60 minutes after the download, disable DHT/PEX/LPD and run
`start_restore.bat` when the download is complete. The 1 Gbps profile allows
more peers, removes the upload limit and enables a disk cache.

## Version

The DVT version is set in one place, `bats\common\version.cmd`
(`DVT_VERSION`). Every `config.cmd` loads it. It is shown in the banner and the
window title of the build scripts, `make_boot.bat`, WinPE and the test report.

`restore.bat` writes a record to the registry of the restored Windows:

```
reg query HKLM\SOFTWARE\DVT
```

| Value | Example |
|---|---|
| `Version` | `0.2.0` |
| `BootMode` | `Local` (client local boot) or `Media` |
| `RestoredAt` | date and time in WinPE (`%DATE% %TIME%`) |
| `Torrent` | `DVT_backup` |
| `ImageFile`, `ImageIndex`, `ImageName` | `backup.wim`, `1`, `Windows 11 Pro` |
| `Firmware` | `UEFI` or `BIOS` |
| `IPAddress` | the address used in WinPE |
| `TargetDisk` | the disk number in WinPE |

## Script reference

### Build PC

| Script | Purpose |
|---|---|
| `01_make_pe.bat` | Builds `_output\boot\boot.wim` from the ADK `winpe.wim` (scripts, tools, drivers, Num Lock on) and copies the host scripts into `_output\boot\` |
| `03_make_test_pe.bat` | Builds the test image `_output\boot_test\boot.wim` (network, gateway and seeder check, FTP upload of `<ip>.txt`, no disk access) |
| `02_make_media.bat` | Builds `_output\media\boot.wim` from the ADK `winpe.wim` with `bats\Media\pe`, then writes the ISO, a new USB drive, or updates a USB drive (`iso`, `usb`, `update`) |

### Client PC (Windows, client local boot)

| Script | Purpose |
|---|---|
| `make_boot.bat` | Main script: prepares the PC and restarts into WinPE (runs from `C:\temp\boot`) |
| `get_host_ip.bat` | Finds the default-route adapter; writes `ip.txt` (ip, subnet, gateway, static DNS) for a static address only |
| `get_link_speed.bat` | Link speed → aria2 profile and console color |
| `get_disk_id.bat` | Disk ID (GPT GUID / MBR signature) of the Windows disk |
| `suspend_bitlocker.bat` | Suspends BitLocker on the Windows drive for one restart |
| `export_net_drivers.bat` | Exports drivers of connected physical NICs with `pnputil` |
| `prepare_mount_dir.bat` | Discards a stale mount and checks the mount folder is empty |
| `set_bcd.bat` | Creates a ramdisk boot entry for `boot.wim`, used for the next boot only |
| `show_ip.bat` | Shows the last octet of the IP address in large digits |

### WinPE, shared (`bats\common\`)

| Script | Purpose |
|---|---|
| `version.cmd` | `DVT_VERSION` |
| `get_firmware.bat` | UEFI or BIOS |
| `get_ip.bat` / `set_ip.bat` | DHCP / static IP (from `ip.txt`, or from arguments on the media) with DNS |
| `check_space.bat` | Disk space check before erasing |
| `check_gateway.bat` | Pings the default gateway |
| `check_seeder.bat` | Downloads `dvt_check.txt` only and verifies its size (rejects a 0-byte file) |
| `make_disk.bat` | Cleans the disk and creates GPT or MBR partitions |
| `get_target.bat` | Picks the download drive (another local volume with enough free space, otherwise `T:`; on the media never the boot media) |
| `start_restore.bat` | Called by aria2c; starts `restore.bat` once in its own window |
| `restore.bat` | Applies the image, drivers, boot files, writes `HKLM\SOFTWARE\DVT`, registers `setpc.bat`, cleans up and reboots |
| `ping_host.bat`, `wait.bat` | Helpers (`timeout.exe` is not available in WinPE) |

### WinPE, client local boot only (`bats\pe\`)

| Script | Purpose |
|---|---|
| `startnet.cmd` | Runs `start_dvt.bat` when WinPE starts |
| `start_dvt.bat` | Main flow: checks, network, erase, download |
| `get_disk.bat` | Disk to erase (disk ID, fallback) |

### WinPE, USB / CD media only (`bats\Media\pe\`)

| Script | Purpose |
|---|---|
| `startnet.cmd` | Finds the boot media, copies `<media>\config` to `X:\restore`, runs `start_media.bat` |
| `start_media.bat` | Main flow: network order, input, checks, erase, download |
| `get_input.bat` | Disk list; last IP octet and disk number (disk from `FORCE_DISK` if set) |
| `getdiskinfo.bat` | Disk list |
| `link.exe` | Link speed → `aria2.conf` |

## Troubleshooting

| Symptom | What to check |
|---|---|
| PC reboots into the old Windows after a few seconds | Client local boot: a check failed before erasing. The message on screen names it (disk, network, gateway or seeder). |
| "The target disk could not be determined" | No disk with the disk ID, and the fallback found no single RAW volume or single disk (or `AUTO_DISK_FALLBACK=0`). Rerun `make_boot.bat`, or set `FORCE_DISK`. |
| "Disk ID ... was found on more than one disk" | Cloned disks with the same ID. Set `FORCE_DISK`, or remove the extra disk. |
| "Disk N is too small for this image" | The disk space check failed before erasing. Use a larger disk, put a second disk with free space in the PC, or set `APPLIED_SIZE_MB` (exact size) or `SPACE_CHECK`. |
| "Image N could not be read from backup.wim" | `WIM_INDEX` does not exist in `backup.wim`. List the images with `wimlib-imagex info backup.wim`. |
| `make_boot.bat`: "BitLocker could not be suspended" | Suspend it by hand (`manage-bde -protectors -disable C: -RebootCount 1`) or set `BITLOCKER_SUSPEND=0`. |
| Build: "... is in bats\common and in ..." | A script left from an older version. Delete the copy in `bats\pe` or `bats\Media\pe`. |
| "No seeder is reachable" | Tracker/seeder running? `dvt_check.txt` in the torrent? Log: `%TEMP%\dvt_seeder.log`. |
| "The seeder check file in the torrent is empty" | `dvt_check.txt` in the torrent is a 0-byte file. Give it content and create the torrent again. |
| No network in WinPE | The NIC driver may be missing. Check `NETDRV_EXCLUDE`, or add the driver to `drivers\` and rebuild. Realtek NICs need the WinPE driver. |
| Connection drops during the download on a Realtek PC | The Windows Realtek driver may be in WinPE. Keep `NETDRV_EXCLUDE=Realtek` and rebuild with Realtek's WinPE driver in `drivers\`. |
| Media: "The IP settings in ...\config\ip.txt are invalid" | Check the format (ip, subnet, gateway, DNS; one per line) and save `ip.txt` as ANSI / ASCII. |
| Media: the PC boots the media again after the restore | Remove the USB drive / CD during the countdown. Nothing is erased without input. |
| `02_make_media.bat` fails to format a large USB drive | FAT32 over 32 GB failed on this build PC. Updating Windows is recommended; otherwise use Rufus, `USB_PART_MB` or `USB_FS=exfat` (see [USB drive and ISO](#usb-drive-and-iso)). |
| `make_boot.bat` says the mount folder is not empty | Run `dism /Cleanup-Mountpoints` and empty the folder. |
| Restore failed after erasing | Read the red message. Fix the cause and run `X:\restore\restore.bat` again from the "DVT Console" window, or press a key to reboot. |

A minimized "DVT Console" window is opened in WinPE for troubleshooting.
diskpart logs are written to `%TEMP%\dvt_make_disk*.log`.

## Limitations

- x64 only (ADK `amd64` WinPE).
- IPv4 only.
- The disk ID is read from the English output of `diskpart`, so WinPE must be
  English (`PE_LANG=en-us`, the default); otherwise only the fallback is used.
- The disk space check estimates the applied size unless `APPLIED_SIZE_MB` is
  set.
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
- [Veyon](https://veyon.io) — optional, PC management (see [above](#use-it-with-a-pc-management-tool-such-as-veyon))

## License

DVT is released under the [BSD 3-Clause License](LICENSE).
Copyright (c) 2026, zerojinny.

The third-party tools above are not part of DVT and keep their own licenses.

## Disclaimer

DVT erases disks by design. Use it at your own risk, and test it on hardware
you can afford to wipe.
