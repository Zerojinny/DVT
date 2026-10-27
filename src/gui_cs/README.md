# DVT GUI (C#, single executable)

**English** | [한국어](README.ko.md)

`DVT_GUI.exe` — one file, no installation. It **does not change any DVT
script**: it edits the settings files and starts the existing scripts. The
same features as the PowerShell version in `gui\`.

## Build (once)

Run **`gui_cs\build_gui.bat`**. It compiles `src\*.cs` with the C# compiler
that comes with the .NET Framework 4.x of Windows 10/11 (no Visual Studio, no
SDK, no download) and writes **`DVT_GUI.exe` into the build folder** (the folder
that contains `data\`). The icon, manifest (`asInvoker`, DPI aware) and version
information are embedded.

`DVT_GUI.exe` must stay in the build folder. It needs only the .NET Framework
4.x that Windows 10/11 already has.

## Use

Double-click `DVT_GUI.exe` (no administrator rights needed). Each build script
asks for elevation in its own console window, and its questions (rebuild Y/N,
USB disk number, `YES`, drive letter) are answered there.

The left sidebar switches between the three pages; each page has its own
color (blue / teal / orange) for its header, main button and tabs. A yellow
dot (sidebar) or `●` (tab) marks unsaved changes.

| Page | Runs | Settings edited |
|---|---|---|
| **Client local boot** | `01_make_pe.bat` | `data\host\config.cmd`, `data\pe\config.cmd`, aria2 profiles (Notepad) |
| **USB / CD media** | `02_make_media.bat iso` / `usb` / `update` | `data\Media\pe\config.cmd`, `data\Media\config\ip.txt`, `DVT_backup.torrent`, aria2 profiles, `data\Media\config.cmd` |
| **Test boot** | `03_make_test_pe.bat` | `data\test\test_config.cmd` |

- **Edit an existing DVT USB drive:** in *USB / CD media*, choose the drive
  under *Media settings in*. The WinPE settings, `ip.txt` and the torrent are
  then read from and written to `<USB>:\config` — used at the next boot.
- **Copy client package…** copies `_output\boot` (or `boot_test`) to a folder.
- The status bar shows when a script finished and its result.

## Prerequisites page

The fourth page has two tabs: **Windows ADK** and **WinPE tools**.

### WinPE tools (aria2, wimlib, NirCmd)

Downloads the third-party tools of the WinPE images from their official
sites and copies them to the folders set in `data\host\config.cmd`:

| Tool | Copied to | Files |
|---|---|---|
| aria2 1.37.0 (github.com/aria2/aria2) | `PE_TOOLS_DIR` | `aria2c.exe` |
| wimlib 1.14.5 (wimlib.net) | `PE_TOOLS_DIR` | `wimlib-imagex.exe`, `libwim-15.dll` |
| NirCmd x64 2.87 (nirsoft.net) | `PE_TOOLS_DIR` (`NIRCMD_SRC`) | every file of the zip (`nircmd.exe`, `nircmdc.exe`, `NirCmd.chm`) |

- URLs, allowed hosts and SHA256 hashes are in `gui_cs\tools.ini` (values of
  the Scoop manifests; aria2 and NirCmd also match Npackd / Chocolatey).
  A zip with another hash is refused — except NirCmd, whose download address
  has no version: then the hash is shown and you decide.
- Replaced files are copied to `_output\tools_backup\<time>\` first;
  the zip files stay in `_output\tools_download\`.
- Some antivirus programs report NirCmd as a "potentially unwanted" tool.

### Windows ADK

The Windows ADK tab installs what the builds need from Microsoft — only the
**Deployment Tools** of the Windows ADK and the **Windows PE add-on** — and
shows what is installed (also whether `ADK_PE_DIR` finds `winpe.wim` and
whether the `source` folder already holds the copies DVT keeps after the
first build, in which case the ADK is no longer needed).

- **Version to install:** choose the ADK release (with its WinPE add-on)
  from the list — from Windows 10 1809 (10.1.17763.7320) to the newest
  (default). The installed version is marked `[installed]`. When another
  version is installed, *Uninstall ... first* is checked automatically
  (the ADK setup cannot replace another version, error 2008).
- **Download and install:** the links of the selected release in `data\adk.ini`
  are used (a root link resolved to its folder on `download.microsoft.com`,
  or the direct link when that fails); `adksetup.exe` and
  `adkwinpesetup.exe` are downloaded, must carry a valid **Microsoft
  Authenticode signature**, and their **SHA256** must be the one of the
  selected release (a file of another release or with an unknown hash —
  Microsoft moved or republished the link — is used only after you agree).
  One administrator prompt starts `DVT_GUI.exe --adk-helper`, which checks
  the signatures again and runs both setups with `/quiet /norestart /ceip off
  /features ...`. Option: uninstall the installed ADK and add-on first
  (needed when changing the version).
- **Create offline package:** the setups of the selected release with `/layout` into
  `<folder>\ADK` and `<folder>\WinPE`, for a build PC without internet.
- **Install from offline package:** a folder made that way.
- Logs: `_output\adk_setup\` (`status.txt`, `adk_install.log`,
  `winpe_install.log`).
- New ADK release: add a `[release <version>]` section (name, links, the two
  hashes) to `data\adk.ini` (no rebuild needed). `[known <version>]`
  sections only name the version of files that can no longer be downloaded.

The download method and the hashes come from
[p0w3rsh3ll/ADK](https://github.com/p0w3rsh3ll/ADK) (MIT License, © Emin Atac).

## Languages

All text on the screen (labels, messages and the descriptions of every
setting) is in **`gui_cs\lang\<code>.ini`**: `en.ini` (English) and
`ko.ini` (Korean). Choose the language at the bottom of the sidebar; the
choice is kept in `data\gui_settings.ini`. Without a choice the Windows
display language is used if a file for it exists, otherwise English.

- The files are embedded in `DVT_GUI.exe` by `build_gui.bat`, so the exe also
  works alone. A language file is searched in this order: **`lang\` next to
  `DVT_GUI.exe`**, then `gui_cs\lang\`, then the embedded copy; the first one
  found is used at the next start — edit the text without rebuilding.
- `en.ini` is the reference: text missing in another file is shown in
  English (a key missing everywhere is shown as `[key]`).
- **New language:** copy `en.ini` to e.g. `ja.ini`, change `[meta] name` and
  `font`, translate the text after the `=` signs. It appears in the list.
- Format: `key = text`; `key += text` adds a line; keep `{0}`, `{1}`;
  `;` starts a comment; save as UTF-8. Settings are `[setting file:NAME]`
  with `summary`, `details`, `choice <value>` (the value and `advanced` come
  from `en.ini`).

## How settings are saved

- Only `set "NAME=VALUE"` lines at the start of a line are changed; comments,
  other lines and line ends stay as they are.
- Values computed by the scripts (`%~dp0`, names set twice) are not shown.
- Every setting has a description (from the language file): a short one in the grid and the
  full help below it (what it does, its choices, the comment of the file).
- Settings with fixed choices get a drop-down list with the meaning of each
  value (e.g. `1 - suspend for one restart`).
- Settings that are usually left as they are (paths, tool locations, colors)
  are marked *advanced* and hidden until **Show advanced** is checked.
- Not allowed: `"`, `!`, non-ASCII characters, a single `%` (write `%%`).
- Before every save the old file is copied to `_output\gui_backup\`.

## Antivirus

The exe is small, not packed and not obfuscated, and is built on your own PC
from the source in `src\`. If a scanner still reports it, submit the file as a
false positive (for Microsoft Defender: the Microsoft Security Intelligence
submission portal). Signing the release exe with a code signing certificate
helps the most.

## Files

```
DVT_GUI.exe            result (build folder)
gui_cs\build_gui.bat   build script
gui_cs\app.manifest    asInvoker, DPI aware, Windows 8.1/10/11
gui_cs\DVT.ico         icon
data\adk.ini           ADK releases: download links and setup hashes
                       (read at start; embedded by build_gui.bat)
gui_cs\tools.ini       aria2 / wimlib / NirCmd download links and hashes
gui_cs\lang\en.ini     English text (reference, complete)
gui_cs\lang\ko.ini     Korean text
gui_cs\src\*.cs        source (C# 5, .NET Framework 4.x, WinForms)
                       Lang.cs = loads the language files
```
