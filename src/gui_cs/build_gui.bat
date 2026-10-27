@echo off
rem ============================================================
rem  DVT GUI - build_gui.bat (Windows, run on the build PC)
rem  Location: <build>\gui_cs (next to the src folder).
rem  Compiles src\*.cs into <build>\DVT_GUI.exe with the C# compiler
rem  that comes with the .NET Framework 4.x of Windows 10/11
rem  (no Visual Studio, no SDK, no download).
rem  The icon (DVT.ico), the manifest (app.manifest), the language
rem  files (lang\*.ini), adk.ini (<build>\data\adk.ini, else
rem  gui_cs\adk.ini) and tools.ini (page Prerequisites) are embedded;
rem  the version information comes from src\AssemblyInfo.cs.
rem  DVT_GUI.exe also reads lang\*.ini, data\adk.ini and tools.ini at
rem  start, so edited copies work without a rebuild.
rem  Administrator rights are not needed.
rem
rem  Usage: build_gui.bat [nopause]
rem  Exit : 0 = OK
rem         1 = failed
rem ============================================================
setlocal EnableExtensions
cd /d "%~dp0"

set "SRC_DIR=%~dp0src"
for %%I in ("%~dp0..") do set "BUILD_DIR=%%~fI"
set "OUT_EXE=%BUILD_DIR%\DVT_GUI.exe"
set "MANIFEST=%~dp0app.manifest"
set "ICON=%~dp0DVT.ico"

rem ---- C# compiler of the .NET Framework 4.x (64-bit first) ----
set "CSC=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
    echo [ERROR] csc.exe of the .NET Framework 4.x was not found.
    echo         Turn on ".NET Framework 4.8 Advanced Services" in Windows Features.
    goto :failed
)

if not exist "%SRC_DIR%\Program.cs" (
    echo [ERROR] Source files not found: %SRC_DIR%
    goto :failed
)
if not exist "%BUILD_DIR%\data\01_make_pe.bat" (
    echo [WARN] %BUILD_DIR% does not look like the DVT build folder.
    echo        DVT_GUI.exe must be in the folder that contains data\01_make_pe.bat.
)

set "OPT_ICON="
if exist "%ICON%" set "OPT_ICON=/win32icon:"%ICON%""

rem ---- language files embedded as Dvt.lang.<code>.ini ----
set "OPT_RES="
for %%F in ("%~dp0lang\*.ini") do call :add_resource "%%~fF" "%%~nF"
if not defined OPT_RES (
    echo [ERROR] No language file found in %~dp0lang ^(en.ini is required^).
    goto :failed
)
if not exist "%~dp0lang\en.ini" (
    echo [ERROR] %~dp0lang\en.ini is required.
    goto :failed
)

rem ---- data of the Windows ADK page, embedded as Dvt.data.adk.ini ----
rem <build>\data\adk.ini first, else gui_cs\adk.ini
set "ADK_INI=%BUILD_DIR%\data\adk.ini"
if not exist "%ADK_INI%" set "ADK_INI=%~dp0adk.ini"
if not exist "%ADK_INI%" (
    echo [ERROR] adk.ini is required ^(%BUILD_DIR%\data or %~dp0^).
    goto :failed
)
echo [INFO] ADK data : %ADK_INI%
set OPT_RES=%OPT_RES% /resource:"%ADK_INI%",Dvt.data.adk.ini

rem ---- data of the WinPE tools tab, embedded as Dvt.data.tools.ini ----
if not exist "%~dp0tools.ini" (
    echo [ERROR] %~dp0tools.ini is required.
    goto :failed
)
set OPT_RES=%OPT_RES% /resource:"%~dp0tools.ini",Dvt.data.tools.ini

echo ==============================================
echo  DVT GUI - build DVT_GUI.exe
echo ==============================================
echo [INFO] Compiler : %CSC%
echo [INFO] Output   : %OUT_EXE%

if exist "%OUT_EXE%" del /f /q "%OUT_EXE%" 2>nul
if exist "%OUT_EXE%" (
    echo [ERROR] %OUT_EXE% is in use. Close the DVT GUI first.
    goto :failed
)

"%CSC%" /nologo /target:winexe /platform:anycpu /optimize+ /warn:4 ^
    /out:"%OUT_EXE%" /win32manifest:"%MANIFEST%" %OPT_ICON% %OPT_RES% ^
    /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.IO.Compression.dll ^
    "%SRC_DIR%\*.cs"
if errorlevel 1 (
    echo [ERROR] The compiler reported errors ^(see above^).
    goto :failed
)
if not exist "%OUT_EXE%" (
    echo [ERROR] DVT_GUI.exe was not created.
    goto :failed
)

echo.
echo [DONE] Built %OUT_EXE%
if /i not "%~1"=="nopause" pause
exit /b 0

:failed
echo.
echo [FAILED] DVT_GUI.exe was not built.
if /i not "%~1"=="nopause" pause
exit /b 1


rem ============================================================
rem  :add_resource "<file>" "<code>"   adds /resource:<file>,Dvt.lang.<code>.ini
rem ============================================================
:add_resource
set OPT_RES=%OPT_RES% /resource:"%~1",Dvt.lang.%~2.ini
echo [INFO] Language : %~2
exit /b 0
