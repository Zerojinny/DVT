// ============================================================
//  DVT GUI - Program.cs
//  Entry point. DVT_GUI.exe must be in the DVT build folder (the
//  folder that contains data\01_make_pe.bat and data\host); started
//  from the gui_cs folder it also finds the build folder one level up.
//  The chosen language is kept in data\gui_settings.ini
//  (language = <code>); without it the Windows display language is
//  used when a language file for it exists, else English.
// ============================================================
using System;
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
            try
            {
                string f = root == null ? null : SettingsFile(root);
                if (f != null && !File.Exists(f)) f = OldSettingsFile(root);
                if (f != null && File.Exists(f))
                {
                    foreach (string l in File.ReadAllLines(f, Encoding.UTF8))
                    {
                        int eq = l.IndexOf('=');
                        if (eq > 0 && l.Substring(0, eq).Trim().Equals("language", StringComparison.OrdinalIgnoreCase))
                            return l.Substring(eq + 1).Trim();
                    }
                }
            }
            catch (Exception) { }
            return L.DefaultCode();
        }

        public static void SaveLanguage(string root, string code)
        {
            try
            {
                Directory.CreateDirectory(Path.Combine(root, "data"));
                File.WriteAllText(SettingsFile(root), "; DVT GUI settings\r\nlanguage = " + code + "\r\n", Encoding.UTF8);
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "DVT GUI", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }
}
