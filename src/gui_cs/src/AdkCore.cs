// ============================================================
//  DVT GUI - AdkCore.cs
//  Windows ADK + Windows PE add-on: detection, verification of the
//  setup files and the elevated helper that runs them.
//
//  Method based on p0w3rsh3ll/ADK (https://github.com/p0w3rsh3ll/ADK,
//  MIT License, (c) Emin Atac): the fwlink root links of adk.ini are
//  resolved to the download folder of the current release, and the
//  setup files are checked against known SHA256 hashes.
//  In addition every setup file must carry a valid Authenticode
//  signature of Microsoft (WinVerifyTrust), checked again by the
//  elevated helper right before it runs the file.
//
//  Helper mode (started elevated by the GUI, no window):
//    DVT_GUI.exe --adk-helper install "<adksetup.exe>" "<adkwinpesetup.exe>" "<work folder>" [uninstall]
//    DVT_GUI.exe --adk-helper layout  "<adksetup.exe>" "<adkwinpesetup.exe>" "<work folder>" "<layout folder>"
//  It writes its progress to <work folder>\status.txt:
//    STEP <n>/<total> <text>      one line per step
//    EXIT <code> <text>           last line; 0 = OK, 3010 = OK, restart needed
// ============================================================
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using Microsoft.Win32;

namespace Dvt
{
    // One installed kit found in the Uninstall registry keys
    public class KitEntry
    {
        public string Name = "";
        public string Version = "";
        public string Uninstall = "";
    }

    public class AdkState
    {
        public string KitsRoot = "";          // ...\Windows Kits\10\
        public KitEntry Adk;                  // null = not installed
        public KitEntry Pe;                   // null = not installed
        public bool DeploymentTools;          // oscdimg.exe found
        public bool WinPeWim;                 // amd64\en-us\winpe.wim found
        public string PeDir = "";             // ...\Windows Preinstallation Environment\amd64
    }

    public static class AdkCore
    {
        public const string AdkNamePrefix = "Windows Assessment and Deployment Kit";

        // ---------- detection ----------

        public static AdkState Detect()
        {
            AdkState st = new AdkState();
            try
            {
                foreach (RegistryView view in new[] { RegistryView.Registry32, RegistryView.Registry64 })
                {
                    using (RegistryKey hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view))
                    {
                        using (RegistryKey k = hklm.OpenSubKey(@"SOFTWARE\Microsoft\Windows Kits\Installed Roots"))
                        {
                            if (k != null && st.KitsRoot.Length == 0)
                            {
                                object v = k.GetValue("KitsRoot10");
                                if (v != null) st.KitsRoot = v.ToString();
                            }
                        }
                        using (RegistryKey un = hklm.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"))
                        {
                            if (un == null) continue;
                            foreach (string sub in un.GetSubKeyNames())
                            {
                                using (RegistryKey e = un.OpenSubKey(sub))
                                {
                                    if (e == null) continue;
                                    string name = Convert.ToString(e.GetValue("DisplayName"));
                                    int kind = KitKind(e, name);
                                    if (kind == 0) continue;
                                    KitEntry ke = new KitEntry();
                                    ke.Name = name;
                                    ke.Version = Convert.ToString(e.GetValue("DisplayVersion"));
                                    string q = Convert.ToString(e.GetValue("QuietUninstallString"));
                                    ke.Uninstall = q.Length > 0 ? q : Convert.ToString(e.GetValue("UninstallString"));
                                    if (kind == 2)
                                    { if (st.Pe == null) st.Pe = ke; }
                                    else
                                    { if (st.Adk == null) st.Adk = ke; }
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception) { }

            string root = st.KitsRoot;
            if (root.Length == 0)
                root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Windows Kits\10\");
            string adkDir = Path.Combine(root, "Assessment and Deployment Kit");
            st.PeDir = Path.Combine(adkDir, @"Windows Preinstallation Environment\amd64");
            st.DeploymentTools = File.Exists(Path.Combine(adkDir, @"Deployment Tools\amd64\Oscdimg\oscdimg.exe"));
            st.WinPeWim = File.Exists(Path.Combine(st.PeDir, @"en-us\winpe.wim"));
            return st;
        }

        // 0 = not a kit, 1 = Windows ADK, 2 = Windows PE add-on.
        // The display name is localized (Korean Windows shows a Korean
        // name), so the bundle is recognized first by the setup file in
        // the package cache (BundleCachePath), then by known names.
        static int KitKind(RegistryKey e, string name)
        {
            string cache = Convert.ToString(e.GetValue("BundleCachePath"));
            string file = cache.Length > 0 ? Path.GetFileName(cache) : "";
            if (string.Equals(file, "adkwinpesetup.exe", StringComparison.OrdinalIgnoreCase)) return 2;
            if (string.Equals(file, "adksetup.exe", StringComparison.OrdinalIgnoreCase)) return 1;
            if (Convert.ToString(e.GetValue("SystemComponent")) == "1") return 0;
            if (cache.Length == 0) return 0;     // only bundles (Burn) are kits, not their MSI parts
            foreach (string n in AdkNames)
            {
                if (name.StartsWith(n, StringComparison.OrdinalIgnoreCase))
                {
                    foreach (string pe in PeNames)
                        if (name.IndexOf(pe, StringComparison.OrdinalIgnoreCase) >= 0) return 2;
                    return 1;
                }
            }
            return 0;
        }

        static readonly string[] AdkNames = { AdkNamePrefix, "Windows \uD3C9\uAC00 \uBC0F \uBC30\uD3EC \uD0A4\uD2B8" };
        static readonly string[] PeNames = { "Preinstallation Environment", "\uC0AC\uC804 \uC124\uCE58 \uD658\uACBD" };

        // ---------- verification ----------

        public static string Sha256(string path)
        {
            using (FileStream fs = File.OpenRead(path))
            using (SHA256 sha = SHA256.Create())
            {
                byte[] h = sha.ComputeHash(fs);
                StringBuilder sb = new StringBuilder();
                foreach (byte b in h) sb.Append(b.ToString("X2"));
                return sb.ToString();
            }
        }

        // Version whose [release ...] or [known ...] hash matches, or "" (key = adksetup / adkwinpesetup)
        public static string KnownVersion(Dictionary<string, List<KeyValuePair<string, string>>> data, string key, string hash)
        {
            if (data == null) return "";
            foreach (KeyValuePair<string, List<KeyValuePair<string, string>>> sec in data)
            {
                string v = SectionVersion(sec.Key);
                if (v == null) continue;
                foreach (KeyValuePair<string, string> kv in sec.Value)
                {
                    if (string.Equals(kv.Key, key, StringComparison.OrdinalIgnoreCase) &&
                        string.Equals(kv.Value.Trim(), hash, StringComparison.OrdinalIgnoreCase))
                        return v;
                }
            }
            return "";
        }

        // version of a [release <version>] or [known <version>] section, else null
        public static string SectionVersion(string section)
        {
            foreach (string prefix in new[] { "release ", "known " })
                if (section.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    return section.Substring(prefix.Length).Trim();
            return null;
        }

        // null = valid Authenticode signature of Microsoft Corporation, else the reason
        public static string CheckMicrosoftSignature(string path)
        {
            int rc;
            try { rc = VerifyEmbeddedSignature(path); }
            catch (Exception ex) { return "WinVerifyTrust: " + ex.Message; }
            if (rc != 0) return string.Format("WinVerifyTrust 0x{0:X8}", rc);
            try
            {
                X509Certificate cert = X509Certificate.CreateFromSignedFile(path);
                string subject = cert.Subject ?? "";
                if (subject.IndexOf("O=Microsoft Corporation", StringComparison.OrdinalIgnoreCase) < 0)
                    return "Signer: " + subject;
            }
            catch (Exception ex) { return "Certificate: " + ex.Message; }
            return null;
        }

        public static string FileVersion(string path)
        {
            try
            {
                FileVersionInfo v = FileVersionInfo.GetVersionInfo(path);
                return (v.ProductVersion ?? v.FileVersion ?? "").Trim();
            }
            catch (Exception) { return ""; }
        }

        // ---- WinVerifyTrust (wintrust.dll) ----
        static readonly Guid WintrustActionGenericVerifyV2 = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct WinTrustFileInfo
        {
            public uint cbStruct;
            [MarshalAs(UnmanagedType.LPWStr)] public string pcwszFilePath;
            public IntPtr hFile;
            public IntPtr pgKnownSubject;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct WinTrustData
        {
            public uint cbStruct;
            public IntPtr pPolicyCallbackData;
            public IntPtr pSIPClientData;
            public uint dwUIChoice;             // 2 = WTD_UI_NONE
            public uint fdwRevocationChecks;    // 0 = WTD_REVOKE_NONE
            public uint dwUnionChoice;          // 1 = WTD_CHOICE_FILE
            public IntPtr pFile;
            public uint dwStateAction;          // 0 = WTD_STATEACTION_IGNORE
            public IntPtr hWVTStateData;
            public IntPtr pwszURLReference;
            public uint dwProvFlags;            // 0x1000 = WTD_CACHE_ONLY_URL_RETRIEVAL
            public uint dwUIContext;
            public IntPtr pSignatureSettings;
        }

        [DllImport("wintrust.dll", ExactSpelling = true, SetLastError = false, CharSet = CharSet.Unicode)]
        static extern int WinVerifyTrust(IntPtr hwnd, [MarshalAs(UnmanagedType.LPStruct)] Guid pgActionID, IntPtr pWVTData);

        static int VerifyEmbeddedSignature(string path)
        {
            WinTrustFileInfo fi = new WinTrustFileInfo();
            fi.cbStruct = (uint)Marshal.SizeOf(typeof(WinTrustFileInfo));
            fi.pcwszFilePath = path;
            IntPtr pFile = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WinTrustFileInfo)));
            IntPtr pData = IntPtr.Zero;
            try
            {
                Marshal.StructureToPtr(fi, pFile, false);
                WinTrustData wd = new WinTrustData();
                wd.cbStruct = (uint)Marshal.SizeOf(typeof(WinTrustData));
                wd.dwUIChoice = 2;
                wd.fdwRevocationChecks = 0;
                wd.dwUnionChoice = 1;
                wd.pFile = pFile;
                wd.dwStateAction = 0;
                wd.dwProvFlags = 0x1000;
                pData = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WinTrustData)));
                Marshal.StructureToPtr(wd, pData, false);
                return WinVerifyTrust(IntPtr.Zero, WintrustActionGenericVerifyV2, pData);
            }
            finally
            {
                Marshal.DestroyStructure(pFile, typeof(WinTrustFileInfo));
                Marshal.FreeHGlobal(pFile);
                if (pData != IntPtr.Zero) Marshal.FreeHGlobal(pData);
            }
        }

        // ============================================================
        //  elevated helper
        // ============================================================

        public static int RunHelper(string[] args)
        {
            // args: --adk-helper <mode> <adksetup> <pesetup> <work> [uninstall | <layout folder>]
            if (args.Length < 5) return 87;
            string mode = args[1].ToLowerInvariant();
            string adkSetup = args[2];
            string peSetup = args[3];
            string work = args[4];
            string extra = args.Length > 5 ? args[5] : "";
            Directory.CreateDirectory(work);
            string statusFile = Path.Combine(work, "status.txt");
            File.WriteAllText(statusFile, "", Encoding.UTF8);

            Dictionary<string, List<KeyValuePair<string, string>>> data = L.ReadData("adk.ini");
            string adkFeatures = L.Value(data, "install", "adk_features");
            string peFeatures = L.Value(data, "install", "pe_features");
            if (adkFeatures.Length == 0) adkFeatures = "OptionId.DeploymentTools";
            if (peFeatures.Length == 0) peFeatures = "OptionId.WindowsPreinstallationEnvironment";

            try
            {
                // the files are checked again here, right before they run with
                // administrator rights
                foreach (string f in new[] { adkSetup, peSetup })
                {
                    if (!File.Exists(f)) return Finish(statusFile, 2, "Not found: " + f);
                    string err = CheckMicrosoftSignature(f);
                    if (err != null) return Finish(statusFile, 5, "Signature check failed: " + f + " (" + err + ")");
                }

                if (mode == "layout")
                {
                    if (extra.Length == 0) return Finish(statusFile, 87, "No layout folder.");
                    string adkDir = Path.Combine(extra, "ADK");
                    string peDir = Path.Combine(extra, "WinPE");
                    Status(statusFile, "STEP 1/2 ADK -> " + adkDir);
                    int rc = Run(adkSetup, "/quiet /norestart /ceip off /layout \"" + adkDir + "\" /log \"" + Path.Combine(work, "adk_layout.log") + "\"");
                    if (rc != 0) return Finish(statusFile, rc, "adksetup.exe /layout");
                    Status(statusFile, "STEP 2/2 WinPE -> " + peDir);
                    rc = Run(peSetup, "/quiet /norestart /ceip off /layout \"" + peDir + "\" /log \"" + Path.Combine(work, "winpe_layout.log") + "\"");
                    if (rc != 0) return Finish(statusFile, rc, "adkwinpesetup.exe /layout");
                    return Finish(statusFile, 0, "OK");
                }

                if (mode != "install") return Finish(statusFile, 87, "Unknown mode: " + mode);
                bool uninstall = extra.Equals("uninstall", StringComparison.OrdinalIgnoreCase);
                int total = uninstall ? 4 : 2;
                int step = 0;
                bool restart = false;
                if (uninstall)
                {
                    // the WinPE add-on first, then the ADK
                    AdkState st = Detect();
                    foreach (KitEntry ke in new[] { st.Pe, st.Adk })
                    {
                        step++;
                        if (ke == null || ke.Uninstall.Length == 0)
                        {
                            Status(statusFile, string.Format("STEP {0}/{1} -", step, total));
                            continue;
                        }
                        Status(statusFile, string.Format("STEP {0}/{1} uninstall {2} {3}", step, total, ke.Name, ke.Version));
                        int urc = RunCommandLine(ke.Uninstall, "/quiet /norestart");
                        if (urc == 3010) restart = true;
                        else if (urc != 0) return Finish(statusFile, urc, "Uninstall " + ke.Name);
                    }
                }
                step++;
                Status(statusFile, string.Format("STEP {0}/{1} adksetup.exe {2}", step, total, adkFeatures));
                int r1 = Run(adkSetup, "/quiet /norestart /ceip off /features " + adkFeatures + " /log \"" + Path.Combine(work, "adk_install.log") + "\"");
                if (r1 == 3010) restart = true;
                else if (r1 != 0) return Finish(statusFile, r1, "adksetup.exe");
                step++;
                Status(statusFile, string.Format("STEP {0}/{1} adkwinpesetup.exe {2}", step, total, peFeatures));
                int r2 = Run(peSetup, "/quiet /norestart /ceip off /features " + peFeatures + " /log \"" + Path.Combine(work, "winpe_install.log") + "\"");
                if (r2 == 3010) restart = true;
                else if (r2 != 0) return Finish(statusFile, r2, "adkwinpesetup.exe");
                return Finish(statusFile, restart ? 3010 : 0, "OK");
            }
            catch (Exception ex)
            {
                return Finish(statusFile, 1, ex.Message);
            }
        }

        static void Status(string file, string line)
        {
            using (FileStream fs = new FileStream(file, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
            using (StreamWriter w = new StreamWriter(fs, new UTF8Encoding(false)))
                w.WriteLine(line);
        }

        static int Finish(string file, int code, string text)
        {
            try { Status(file, "EXIT " + code + " " + text); } catch (Exception) { }
            return code;
        }

        static int Run(string exe, string args)
        {
            ProcessStartInfo psi = new ProcessStartInfo(exe, args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = Path.GetDirectoryName(exe);
            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
                return p.ExitCode;
            }
        }

        // "C:\path\setup.exe" /uninstall  -> exe + arguments, plus extra arguments
        static int RunCommandLine(string commandLine, string extraArgs)
        {
            string cl = commandLine.Trim();
            string exe, args;
            if (cl.StartsWith("\""))
            {
                int end = cl.IndexOf('"', 1);
                exe = cl.Substring(1, end - 1);
                args = cl.Substring(end + 1).Trim();
            }
            else
            {
                int sp = cl.IndexOf(' ');
                exe = sp < 0 ? cl : cl.Substring(0, sp);
                args = sp < 0 ? "" : cl.Substring(sp + 1).Trim();
            }
            if (exe.EndsWith("MsiExec.exe", StringComparison.OrdinalIgnoreCase))
                args = args.Replace("/I{", "/X{").Replace("/i{", "/X{") + " /qn /norestart";
            else
                args = args + " " + extraArgs;
            return Run(exe, args.Trim());
        }
    }
}
