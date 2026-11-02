// ============================================================
//  DVT GUI - Program.cs
//  Entry point. DVT_GUI.exe must be in the DVT build folder (the
//  folder that contains data\01_make_pe.bat and data\host); started
//  from the gui_cs folder it also finds the build folder one level up.
//  data\gui_settings.ini keeps the settings of the GUI:
//    language   = <code>        (without it English is used)
//    start_page = last | seeder | local | media | test | prereq
//                 page shown at the start (default: local)
//    last_page  = <page>        page shown when the GUI was closed
//                               (used by start_page = last)
// ============================================================
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace Dvt
{
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            // elevated helper of the "Windows ADK" page: no window
            if (args.Length > 0 && args[0] == "--adk-helper")
            {
                L.Init(Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory).TrimEnd('\\'));
                return AdkCore.RunHelper(args);
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            // the manifest declares DPI awareness: scale the layout sizes
            try
            {
                using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) Ui.Scale = g.DpiX / 96f;
            }
            catch (Exception) { Ui.Scale = 1f; }

            string exeDir = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory).TrimEnd('\\');
            L.Init(exeDir);
            string root = FindRoot(exeDir);

            while (true)
            {
                L.Load(LoadLanguage(root));
                Ui.InitFonts(L.FontFamily);
                if (root == null)
                {
                    MessageBox.Show(L.F("msg.no_root", exeDir), "DVT GUI", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return 1;
                }
                if (L.Problems.Count > 0)
                {
                    MessageBox.Show(L.T("msg.lang_problems") + "\r\n\r\n" + string.Join("\r\n", L.Problems.ToArray()),
                        "DVT GUI", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
                MainForm form = new MainForm(root);
                Application.Run(form);
                if (!form.RestartRequested) break;
                form.Dispose();
            }
            return 0;
        }

        static string FindRoot(string dir)
        {
            for (int up = 0; up < 3 && !string.IsNullOrEmpty(dir); up++)
            {
                if (File.Exists(Path.Combine(dir, @"data\01_make_pe.bat")) &&
                    File.Exists(Path.Combine(dir, @"data\host\config.cmd")))
                    return dir;
                dir = Path.GetDirectoryName(dir);
            }
            return null;
        }

        // <build>\data\gui_settings.ini
        static string SettingsFile(string root)
        {
            return Path.Combine(Path.Combine(root, "data"), "gui_settings.ini");
        }

        // before v0.3.0 the file was in <build>\_output (still read once)
        static string OldSettingsFile(string root)
        {
            return Path.Combine(Path.Combine(root, "_output"), "gui_settings.ini");
        }

        static string LoadLanguage(string root)
        {
            string code = GetSetting(root, "language", "");
            return code.Length > 0 ? code : L.DefaultCode();
        }

        public static void SaveLanguage(string root, string code)
        {
            SetSetting(root, "language", code, true);
        }

        // page index kept over a restart for another language (-1 = none)
        public static int RestartPage = -1;

        // value of "key = value" in gui_settings.ini, or fallback
        public static string GetSetting(string root, string key, string fallback)
        {
            try
            {
                string f = root == null ? null : SettingsFile(root);
                if (f != null && !File.Exists(f)) f = OldSettingsFile(root);
                if (f != null && File.Exists(f))
                {
                    foreach (string l in File.ReadAllLines(f, Encoding.UTF8))
                    {
                        string t = l.Trim();
                        if (t.StartsWith(";") || t.StartsWith("#")) continue;
                        int eq = t.IndexOf('=');
                        if (eq > 0 && t.Substring(0, eq).Trim().Equals(key, StringComparison.OrdinalIgnoreCase))
                            return t.Substring(eq + 1).Trim();
                    }
                }
            }
            catch (Exception) { }
            return fallback;
        }

        // sets "key = value" in gui_settings.ini; the other lines stay
        public static void SetSetting(string root, string key, string value, bool showError)
        {
            try
            {
                List<string> lines = new List<string>();
                string f = SettingsFile(root);
                string src = File.Exists(f) ? f : OldSettingsFile(root);
                if (File.Exists(src)) lines.AddRange(File.ReadAllLines(src, Encoding.UTF8));
                if (lines.Count == 0) lines.Add("; DVT GUI settings");
                bool found = false;
                for (int n = 0; n < lines.Count; n++)
                {
                    string t = lines[n].Trim();
                    int eq = t.IndexOf('=');
                    if (t.StartsWith(";") || eq <= 0) continue;
                    if (t.Substring(0, eq).Trim().Equals(key, StringComparison.OrdinalIgnoreCase))
                    {
                        lines[n] = key + " = " + value;
                        found = true;
                    }
                }
                if (!found) lines.Add(key + " = " + value);
                Directory.CreateDirectory(Path.GetDirectoryName(f));
                File.WriteAllText(f, string.Join("\r\n", lines.ToArray()) + "\r\n", Encoding.UTF8);
            }
            catch (Exception ex)
            {
                if (showError) MessageBox.Show(ex.Message, "DVT GUI", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }
}
