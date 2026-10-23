rem ============================================================
rem  DVT - version.cmd (shared)
rem  The ONLY place where the DVT version is set. Loaded by every
rem  config.cmd (WinPE, media and host). The builders copy it into
rem  the WinPE image (X:\restore) and next to the host scripts.
rem  The version is shown on screen and written to the restored
rem  Windows (HKLM\SOFTWARE\DVT, value Version).
rem ============================================================
set "DVT_VERSION=0.2.0"
