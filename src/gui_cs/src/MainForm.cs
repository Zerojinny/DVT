// ============================================================
//  DVT GUI - MainForm.cs
//  Tabs: Client local boot (01_make_pe.bat), USB / CD media
//  (02_make_media.bat iso | usb | update) and Test boot
//  (03_make_test_pe.bat). The scripts and their settings are in
//  <build>\data; the build results stay in <build>\_output.
//  The DVT scripts run unchanged in their own console window with
//  administrator rights; their questions are answered there.
// ============================================================
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace Dvt
{
    public class MainForm : Form
    {
        public readonly string Root;
        // <build>\data: 01/02/03_make_*.bat, host, pe, Media, test, common
        public readonly string DataDir;
        public readonly string BackupDir;
        public readonly string Version;

        readonly Dictionary<string, ConfigEditor> editors = new Dictionary<string, ConfigEditor>();
        IpPanel ipPanel;
        FilesPanel filesPanel;

        string mediaDrive = "";                       // "" = build folder, "E" = DVT USB drive E:
        readonly List<string> mediaDriveList = new List<string>();
        bool mediaSwitching;
        ComboBox mediaCombo;
        Label lblMediaTarget;

        Label lblBootStatus, lblTestStatus, lblMediaWim, lblMediaIso;
        RadioButton rbIso, rbUsb, rbUpd;
        readonly ToolStripStatusLabel statusLabel;

        Control[] pages;
        AdkPage adkPage;
        ToolsPanel toolsPanel;
        Control prereqPage;
        NavButton[] navButtons;
        AccentTabControl subLocal, subMedia;
        readonly Dictionary<string, TabPage> editorPages = new Dictionary<string, TabPage>();
        TabPage ipPage;

        Process job;
        string jobTitle;
        bool jobWasMedia;
        readonly Timer timer;

        // true when the window was closed to switch the language
        public bool RestartRequested;

        public MainForm(string root)
        {
            Root = root;
            DataDir = Path.Combine(root, "data");
            BackupDir = Path.Combine(root, "_output", "gui_backup");
            Version = ReadVersion();
            Ui.Main = this;

            Text = L.F("app.title", Version);
            Font = Ui.FontUI;
            AutoScaleMode = AutoScaleMode.None;
            Size = new Size(Ui.S(1100), Ui.S(800));
            MinimumSize = new Size(Ui.S(900), Ui.S(640));
            StartPosition = FormStartPosition.CenterScreen;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }


            StatusStrip status = new StatusStrip();
            statusLabel = new ToolStripStatusLabel(L.T("status.ready"));
            statusLabel.Spring = true;
            statusLabel.TextAlign = ContentAlignment.MiddleLeft;
            ToolStripStatusLabel rootLabel = new ToolStripStatusLabel("DVT " + Version + "   |   " + Root);
            status.Items.Add(statusLabel);
            status.Items.Add(rootLabel);

            // ---- pages and the sidebar that switches them ----
            Panel content = new Panel();
            content.Dock = DockStyle.Fill;
            content.Padding = new Padding(Ui.S(12), Ui.S(10), Ui.S(12), Ui.S(6));
            Control pLocal = BuildLocalTab(), pMedia = BuildMediaTab(), pTest = BuildTestTab();
            // after the editors: these read their paths
            adkPage = new AdkPage(GetPaths, Root);
            toolsPanel = new ToolsPanel(GetPaths, Root);
            prereqPage = BuildPrereqPage();
            pages = new Control[] { pLocal, pMedia, pTest, prereqPage };
            foreach (Control p in pages)
            {
                p.Dock = DockStyle.Fill;
                p.Visible = false;
                content.Controls.Add(p);
            }
            Control sidebar = BuildSidebar();

            // Fill first, then the edges (docking runs in reverse order)
            Controls.Add(content);
            Controls.Add(sidebar);
            Controls.Add(status);
            ShowPage(0);

            UpdateMediaDriveList();
            SetMediaTarget(mediaDrive);
            UpdateOutputStatus();

            timer = new Timer();
            timer.Interval = 1000;
            timer.Tick += delegate { CheckJob(); };
            timer.Start();

            FormClosing += delegate(object s, FormClosingEventArgs e)
            {
                if (!ConfirmUnsaved(AllItems(), L.T("action.closing"))) { e.Cancel = true; return; }
                if (adkPage.Busy && !Ui.YesNo(L.T("adk.close_busy"), MessageBoxIcon.Warning)) { e.Cancel = true; return; }
                if (toolsPanel.Busy && !Ui.YesNo(L.T("tools.close_busy"), MessageBoxIcon.Warning)) e.Cancel = true;
            };
        }

        public void SetStatus(string text) { statusLabel.Text = text; }

        string ReadVersion()
        {
            string f = Path.Combine(DataDir, @"common\version.cmd");
            string v = "unknown";
            try
            {
                if (File.Exists(f))
                {
                    foreach (string l in File.ReadAllLines(f))
                    {
                        System.Text.RegularExpressions.Match m =
                            System.Text.RegularExpressions.Regex.Match(l, "^set\\s+\"DVT_VERSION=(.*)\"", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                        if (m.Success) v = m.Groups[1].Value;
                    }
                }
            }
            catch (Exception) { }
            return v;
        }

        ConfigEditor AddEditor(string key, string path, string note)
        {
            ConfigEditor ed = new ConfigEditor(key, path, note);
            editors[key] = ed;
            ed.DirtyChanged += delegate { UpdateUnsavedMarks(); };
            return ed;
        }

        TabPage EditorPage(string key, string title)
        {
            TabPage tp = Ui.NewTabPage(title, editors[key], false);
            editorPages[key] = tp;
            return tp;
        }

        // ============================================================
        //  sidebar
        // ============================================================
        Control BuildSidebar()
        {
            Panel side = new Panel();
            side.Dock = DockStyle.Left;
            side.Width = Ui.S(230);
            side.BackColor = Palette.Sidebar;

            TableLayoutPanel t = new TableLayoutPanel();
            t.Dock = DockStyle.Fill;
            t.ColumnCount = 1;
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            t.RowCount = 7;
            foreach (int h in new[] { 92, 68, 68, 68, 68, 0, 100 })
                t.RowStyles.Add(h > 0 ? new RowStyle(SizeType.Absolute, Ui.S(h)) : new RowStyle(SizeType.Percent, 100f));
            t.Padding = new Padding(0);

            Label logo = new Label();
            logo.Text = "DVT";
            logo.Font = new Font("Segoe UI", 22f, FontStyle.Bold);
            logo.ForeColor = Color.White;
            logo.AutoSize = false;
            logo.Dock = DockStyle.Fill;
            logo.TextAlign = ContentAlignment.BottomLeft;
            logo.Padding = new Padding(Ui.S(14), 0, 0, 0);
            Label tag = new Label();
            tag.Text = L.F("sidebar.tagline", Version);
            tag.ForeColor = Palette.SidebarSub;
            tag.Dock = DockStyle.Bottom;
            tag.Height = Ui.S(24);
            tag.Padding = new Padding(Ui.S(16), 0, 0, 0);
            Panel head = new Panel();
            head.Dock = DockStyle.Fill;
            head.Controls.Add(logo);
            head.Controls.Add(tag);
            t.Controls.Add(head, 0, 0);

            navButtons = new NavButton[4];
            string[] titles = { L.T("nav.local"), L.T("nav.media"), L.T("nav.test"), L.T("nav.adk") };
            string[] subs = { "01_make_pe.bat", "02_make_media.bat", "03_make_test_pe.bat", L.T("nav.adk_sub") };
            Color[] colors = { Palette.Local, Palette.Media, Palette.Test, Palette.Adk };
            for (int n = 0; n < 4; n++)
            {
                NavButton b = new NavButton();
                b.Title = titles[n];
                b.Subtitle = subs[n];
                b.Accent = colors[n];
                b.Dock = DockStyle.Fill;
                b.Tag = n;
                b.Click += delegate(object s, EventArgs e) { ShowPage((int)((Control)s).Tag); };
                navButtons[n] = b;
                t.Controls.Add(b, 0, n + 1);
            }

            // footer: language selection and the legend
            TableLayoutPanel foot = new TableLayoutPanel();
            foot.Dock = DockStyle.Fill;
            foot.ColumnCount = 1;
            foot.RowCount = 2;
            foot.RowStyles.Add(new RowStyle(SizeType.Absolute, Ui.S(34)));
            foot.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
            foot.Padding = new Padding(Ui.S(14), 0, Ui.S(10), Ui.S(4));
            FlowLayoutPanel langRow = Ui.NewFlow();
            Label lblLang = new Label();
            lblLang.Text = L.T("sidebar.language");
            lblLang.ForeColor = Palette.SidebarText;
            lblLang.AutoSize = true;
            lblLang.Margin = new Padding(0, Ui.S(7), Ui.S(6), 0);
            langCombo = new ComboBox();
            langCombo.DropDownStyle = ComboBoxStyle.DropDownList;
            langCombo.Width = Ui.S(120);
            langCombo.Margin = new Padding(0, Ui.S(3), 0, 0);
            langCodes = new List<string>();
            foreach (KeyValuePair<string, string> kv in L.Available())
            {
                langCodes.Add(kv.Key);
                langCombo.Items.Add(kv.Value);
            }
            langCombo.SelectedIndex = Math.Max(0, langCodes.IndexOf(L.Code));
            langCombo.SelectedIndexChanged += delegate { OnLanguageChanged(); };
            langRow.Controls.Add(lblLang);
            langRow.Controls.Add(langCombo);
            foot.Controls.Add(langRow, 0, 0);
            Label legend = new Label();
            legend.Text = L.T("sidebar.unsaved") + "\r\n" + L.T("sidebar.backups");
            legend.ForeColor = Palette.SidebarSub;
            legend.Dock = DockStyle.Fill;
            foot.Controls.Add(legend, 0, 1);
            t.Controls.Add(foot, 0, 6);

            side.Controls.Add(t);
            return side;
        }

        // ============================================================
        //  page 4: prerequisites (Windows ADK, WinPE tools)
        // ============================================================
        Control BuildPrereqPage()
        {
            TableLayoutPanel lay = Ui.NewRows(64, 0);
            lay.Controls.Add(new HeaderBanner(L.T("prereq.title"), L.T("prereq.subtitle"), Palette.Adk), 0, 0);
            AccentTabControl sub = new AccentTabControl(Palette.Adk);
            sub.TabPages.Add(Ui.NewTabPage(L.T("tab.adk"), adkPage, true));
            sub.TabPages.Add(Ui.NewTabPage(L.T("tab.tools"), toolsPanel, true));
            lay.Controls.Add(sub, 0, 1);
            return lay;
        }

        ComboBox langCombo;
        List<string> langCodes;

        void OnLanguageChanged()
        {
            string code = langCodes[langCombo.SelectedIndex];
            if (code == L.Code) return;
            if (!ConfirmUnsaved(AllItems(), L.T("action.change_language")))
            {
                langCombo.SelectedIndex = Math.Max(0, langCodes.IndexOf(L.Code));
                return;
            }
            Program.SaveLanguage(Root, code);
            RestartRequested = true;
            Close();
        }

        void ShowPage(int index)
        {
            for (int n = 0; n < pages.Length; n++)
            {
                pages[n].Visible = (n == index);
                navButtons[n].Selected = (n == index);
            }
            if (pages[index] == prereqPage)
            {
                if (!adkPage.Busy) adkPage.RefreshStatus();
                if (!toolsPanel.Busy) toolsPanel.RefreshStatus();
            }
        }

        void UpdateUnsavedMarks()
        {
            if (navButtons == null || ipPanel == null) return;
            foreach (KeyValuePair<string, TabPage> kv in editorPages)
            {
                AccentTabControl tc = kv.Value.Parent as AccentTabControl;
                if (tc != null) tc.SetUnsaved(kv.Value, editors[kv.Key].Dirty);
            }
            if (ipPage != null) subMedia.SetUnsaved(ipPage, ipPanel.Dirty);
            navButtons[0].Unsaved = editors["host"].Dirty || editors["pe"].Dirty;
            navButtons[1].Unsaved = editors["mediape"].Dirty || editors["media"].Dirty || ipPanel.Dirty;
            navButtons[2].Unsaved = editors["test"].Dirty;
        }

        // ============================================================
        //  tab 1: client local boot
        // ============================================================
        Control BuildLocalTab()
        {
            TableLayoutPanel lay = Ui.NewRows(64, 24, 38, 26, 0);
            lay.Controls.Add(new HeaderBanner(L.T("local.title"), L.T("local.subtitle"), Palette.Local), 0, 0);
            lay.Controls.Add(Ui.NewHint(L.T("local.hint")), 0, 1);

            FlowLayoutPanel fl = Ui.NewFlow();
            Button btnBuild = Ui.NewButton(L.T("btn.build_image"), 130);
            Button btnOpen = Ui.NewButton(L.T("btn.open_output"), 140);
            Button btnPkg = Ui.NewButton(L.T("btn.copy_package"), 160);
            Button btn1G = Ui.NewButton(L.T("btn.edit_aria_1g"), 140);
            Button btn100 = Ui.NewButton(L.T("btn.edit_aria_100"), 140);
            Ui.Primary(btnBuild, Palette.Local);
            fl.Controls.AddRange(new Control[] { btnBuild, btnOpen, btnPkg, btn1G, btn100 });
            lay.Controls.Add(fl, 0, 2);
            lblBootStatus = Ui.NewLabel("");
            lay.Controls.Add(lblBootStatus, 0, 3);

            subLocal = new AccentTabControl(Palette.Local);
            AccentTabControl sub = subLocal;
            AddEditor("host", Path.Combine(DataDir, @"host\config.cmd"), L.T("note.host"));
            AddEditor("pe", Path.Combine(DataDir, @"pe\config.cmd"), L.T("note.pe"));
            sub.TabPages.Add(EditorPage("host", L.T("tab.host")));
            sub.TabPages.Add(EditorPage("pe", L.T("tab.pe")));
            lay.Controls.Add(sub, 0, 4);

            btnBuild.Click += delegate { StartScript("01_make_pe.bat", "", L.T("job.local"), false); };
            btnOpen.Click += delegate { Ui.OpenFolder(GetPaths()["Boot"]); };
            btnPkg.Click += delegate { CopyClientPackage(GetPaths()["Boot"], "boot", @"C:\temp\boot"); };
            btn1G.Click += delegate { Ui.OpenInNotepad(Path.Combine(DataDir, @"pe\aria2.conf.1G")); };
            btn100.Click += delegate { Ui.OpenInNotepad(Path.Combine(DataDir, @"pe\aria2.conf.100")); };
            return lay;
        }

        // ============================================================
        //  tab 2: USB / CD media
        // ============================================================
        Control BuildMediaTab()
        {
            TableLayoutPanel lay = Ui.NewRows(64, 30, 38, 24, 24, 12, 32, 40, 0);
            lay.Controls.Add(new HeaderBanner(L.T("media.title"), L.T("media.subtitle"), Palette.Media), 0, 0);

            FlowLayoutPanel fm = Ui.NewFlow();
            rbIso = NewRadio(L.T("media.iso"));
            rbIso.Checked = true;
            rbUsb = NewRadio(L.T("media.usb"));
            rbUsb.ForeColor = Ui.ColorDanger;
            rbUpd = NewRadio(L.T("media.update"));
            fm.Controls.AddRange(new Control[] { rbIso, rbUsb, rbUpd });
            lay.Controls.Add(fm, 0, 1);

            FlowLayoutPanel fm2 = Ui.NewFlow();
            Button btnRun = Ui.NewButton(L.T("btn.make_media"), 130);
            Ui.Primary(btnRun, Palette.Media);
            Button btnOpen = Ui.NewButton(L.T("btn.open_output"), 140);
            Label hint = Ui.NewFlowLabel(L.T("media.console_hint"));
            hint.ForeColor = SystemColors.GrayText;
            fm2.Controls.AddRange(new Control[] { btnRun, btnOpen, hint });
            lay.Controls.Add(fm2, 0, 2);
            lblMediaWim = Ui.NewLabel("");
            lblMediaIso = Ui.NewLabel("");
            lay.Controls.Add(lblMediaWim, 0, 3);
            lay.Controls.Add(lblMediaIso, 0, 4);

            Label sep = new Label();
            sep.AutoSize = false;
            sep.BorderStyle = BorderStyle.Fixed3D;
            sep.Height = 2;
            sep.Anchor = AnchorStyles.Left | AnchorStyles.Right;
            lay.Controls.Add(sep, 0, 5);

            FlowLayoutPanel ft = Ui.NewFlow();
            Label lt = new Label();
            lt.Text = L.T("media.settings_in");
            lt.Font = Ui.FontBold;
            lt.AutoSize = true;
            lt.Margin = new Padding(0, Ui.S(8), Ui.S(8), 0);
            mediaCombo = new ComboBox();
            mediaCombo.DropDownStyle = ComboBoxStyle.DropDownList;
            mediaCombo.Width = Ui.S(480);
            mediaCombo.Margin = new Padding(0, Ui.S(4), Ui.S(8), 0);
            Button btnDrives = Ui.NewButton(L.T("btn.refresh_drives"), 120);
            ft.Controls.AddRange(new Control[] { lt, mediaCombo, btnDrives });
            lay.Controls.Add(ft, 0, 6);
            lblMediaTarget = Ui.NewLabel("");
            lay.Controls.Add(lblMediaTarget, 0, 7);

            subMedia = new AccentTabControl(Palette.Media);
            AccentTabControl sub = subMedia;
            ipPanel = new IpPanel(GetMediaConfigDir);
            ipPanel.DirtyChanged += delegate { UpdateUnsavedMarks(); };
            filesPanel = new FilesPanel(GetMediaConfigDir);
            AddEditor("mediape", GetMediaPeConfigPath(), "");
            AddEditor("media", Path.Combine(DataDir, @"Media\config.cmd"), L.T("note.media"));
            sub.TabPages.Add(EditorPage("mediape", L.T("tab.mediape")));
            ipPage = Ui.NewTabPage(L.T("tab.ip"), ipPanel, true);
            sub.TabPages.Add(ipPage);
            sub.TabPages.Add(Ui.NewTabPage(L.T("tab.files"), filesPanel, true));
            sub.TabPages.Add(EditorPage("media", L.T("tab.media")));
            lay.Controls.Add(sub, 0, 8);

            btnRun.Click += delegate { RunMedia(); };
            btnOpen.Click += delegate { Ui.OpenFolder(GetPaths()["MediaOut"]); };
            btnDrives.Click += delegate
            {
                if (!ConfirmUnsaved(new[] { "mediape", "ip" }, L.T("action.refresh_drives"))) return;
                UpdateMediaDriveList();
                SetMediaTarget(mediaDrive);
                SetStatus(L.F("status.drives_found", mediaDriveList.Count - 1));
            };
            mediaCombo.SelectedIndexChanged += delegate { OnMediaComboChanged(); };
            return lay;
        }

        RadioButton NewRadio(string text)
        {
            RadioButton r = new RadioButton();
            r.Text = text;
            r.AutoSize = true;
            r.Margin = new Padding(0, Ui.S(6), Ui.S(24), 0);
            return r;
        }

        void RunMedia()
        {
            string mode = rbUsb.Checked ? "usb" : (rbUpd.Checked ? "update" : "iso");
            string torrent = Path.Combine(DataDir, @"Media\config\DVT_backup.torrent");
            if (!File.Exists(torrent) &&
                !Ui.YesNo(L.T("media.no_torrent"), MessageBoxIcon.Warning))
                return;
            if (mode == "usb" &&
                !Ui.YesNo(L.T("media.confirm_usb"), MessageBoxIcon.Warning))
                return;
            StartScript("02_make_media.bat", mode, L.F("job.media", mode), true);
        }

        string GetMediaConfigDir()
        {
            if (mediaDrive.Length > 0) return mediaDrive + @":\config";
            return Path.Combine(DataDir, @"Media\config");
        }

        string GetMediaPeConfigPath()
        {
            if (mediaDrive.Length > 0) return mediaDrive + @":\config\config.cmd";
            return Path.Combine(DataDir, @"Media\pe\config.cmd");
        }

        // DVT USB drives: \sources\boot.wim and \config, not the Windows drive
        void UpdateMediaDriveList()
        {
            mediaSwitching = true;
            try
            {
                string keep = mediaDrive;
                mediaCombo.Items.Clear();
                mediaDriveList.Clear();
                mediaDriveList.Add("");
                mediaCombo.Items.Add(L.T("media.build_folder"));
                string sys = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:").Substring(0, 1);
                foreach (DriveInfo d in DriveInfo.GetDrives())
                {
                    try
                    {
                        if (d.DriveType != DriveType.Removable && d.DriveType != DriveType.Fixed) continue;
                        if (!d.IsReady) continue;
                        string letter = d.Name.Substring(0, 1);
                        if (string.Equals(letter, sys, StringComparison.OrdinalIgnoreCase)) continue;
                        if (!File.Exists(letter + @":\sources\boot.wim")) continue;
                        if (!Directory.Exists(letter + @":\config")) continue;
                        mediaCombo.Items.Add(L.F("media.drive_item",
                            letter, d.VolumeLabel, d.DriveType, d.TotalSize / 1073741824.0));
                        mediaDriveList.Add(letter);
                    }
                    catch (Exception) { }
                }
                int idx = mediaDriveList.IndexOf(keep);
                if (idx < 0) idx = 0;
                mediaCombo.SelectedIndex = idx;
                mediaDrive = mediaDriveList[idx];
            }
            finally { mediaSwitching = false; }
        }

        void OnMediaComboChanged()
        {
            if (mediaSwitching) return;
            int idx = mediaCombo.SelectedIndex;
            if (idx < 0) return;
            string next = mediaDriveList[idx];
            if (next == mediaDrive) return;
            if (!ConfirmUnsaved(new[] { "mediape", "ip" }, L.T("action.switch_media")))
            {
                mediaSwitching = true;
                mediaCombo.SelectedIndex = mediaDriveList.IndexOf(mediaDrive);
                mediaSwitching = false;
                return;
            }
            if (next.Length > 0 && !Directory.Exists(next + @":\config"))
            {
                Ui.Info(L.F("media.drive_gone", next), MessageBoxIcon.Warning);
                UpdateMediaDriveList();
                next = mediaDrive;
            }
            SetMediaTarget(next);
        }

        void SetMediaTarget(string drive)
        {
            mediaDrive = drive;
            ConfigEditor ed = editors["mediape"];
            ed.FilePath = GetMediaPeConfigPath();
            if (drive.Length > 0)
            {
                ed.Note = L.T("note.mediape_usb");
                lblMediaTarget.Text = L.F("media.target_usb", drive);
                lblMediaTarget.ForeColor = Ui.ColorDanger;
            }
            else
            {
                ed.Note = L.T("note.mediape_build");
                lblMediaTarget.Text = L.T("media.target_build");
                lblMediaTarget.ForeColor = SystemColors.GrayText;
            }
            ed.LoadFile();
            ipPanel.LoadFile();
            filesPanel.RefreshStatus();
        }

        // ============================================================
        //  tab 3: test boot
        // ============================================================
        Control BuildTestTab()
        {
            TableLayoutPanel lay = Ui.NewRows(64, 40, 38, 26, 0);
            lay.Controls.Add(new HeaderBanner(L.T("test.title"), L.T("test.subtitle"), Palette.Test), 0, 0);
            lay.Controls.Add(Ui.NewHint(L.T("test.hint")), 0, 1);
            FlowLayoutPanel fl = Ui.NewFlow();
            Button btnBuild = Ui.NewButton(L.T("btn.build_test"), 150);
            Ui.Primary(btnBuild, Palette.Test);
            Button btnOpen = Ui.NewButton(L.T("btn.open_output"), 140);
            Button btnPkg = Ui.NewButton(L.T("btn.copy_package"), 160);
            fl.Controls.AddRange(new Control[] { btnBuild, btnOpen, btnPkg });
            lay.Controls.Add(fl, 0, 2);
            lblTestStatus = Ui.NewLabel("");
            lay.Controls.Add(lblTestStatus, 0, 3);
            lay.Controls.Add(AddEditor("test", Path.Combine(DataDir, @"test\test_config.cmd"), L.T("note.test")), 0, 4);

            btnBuild.Click += delegate
            {
                ConfigEditor ed = editors["test"];
                ed.EndEditing();
                List<string> missing = new List<string>();
                foreach (string n in new[] { "FTP_HOST", "FTP_USER" })
                {
                    ConfigEntry e = ed.Find(n);
                    if (e != null && string.IsNullOrEmpty(e.Value)) missing.Add(n);
                }
                if (missing.Count > 0)
                {
                    Ui.Info(L.F("test.missing", string.Join(", ", missing.ToArray())), MessageBoxIcon.Warning);
                    return;
                }
                StartScript("03_make_test_pe.bat", "", L.T("job.test"), false);
            };
            btnOpen.Click += delegate { Ui.OpenFolder(GetPaths()["Test"]); };
            btnPkg.Click += delegate { CopyClientPackage(GetPaths()["Test"], "boot_test", @"C:\temp\boot_test"); };
            return lay;
        }

        // ============================================================
        //  output folders (read from the saved config files)
        // ============================================================
        Dictionary<string, string> GetPaths()
        {
            Dictionary<string, string> map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            map["BUILD_DIR"] = Root;
            map["DATA_DIR"] = DataDir;
            map["HOST_DIR"] = Path.Combine(DataDir, "host");
            map["MEDIA_DIR"] = Path.Combine(DataDir, "Media");
            foreach (string k in new[] { "host", "media" })
            {
                ConfigEditor ed;
                if (!editors.TryGetValue(k, out ed) || ed.Config == null) continue;
                foreach (ConfigEntry e in ed.Config.Entries)
                    if (!e.ReadOnly && !map.ContainsKey(e.Name)) map[e.Name] = e.Original;
            }
            Dictionary<string, string> p = new Dictionary<string, string>();
            string outRoot = ResolveOr("%OUT_ROOT%", map, Path.Combine(Root, "_output"));
            p["Boot"] = ResolveOr("%OUT_DIR%", map, Path.Combine(outRoot, "boot"));
            p["Test"] = Path.Combine(outRoot, "boot_test");
            p["MediaOut"] = ResolveOr("%MEDIA_OUT_DIR%", map, Path.Combine(outRoot, "media"));
            p["MediaWim"] = ResolveOr("%MEDIA_WIM%", map, Path.Combine(p["MediaOut"], "boot.wim"));
            p["MediaIso"] = ResolveOr("%MEDIA_ISO%", map, Path.Combine(p["MediaOut"], "DVT_media.iso"));
            p["Source"] = ResolveOr("%SOURCE_DIR%", map, Path.Combine(Root, "source"));
            p["PeTools"] = ResolveOr("%PE_TOOLS_DIR%", map, Path.Combine(Root, "pe_tools"));
            string nircmd = ResolveOr("%NIRCMD_SRC%", map, Path.Combine(Root, @"pe_tools\nircmd.exe"));
            p["NircmdDir"] = Path.GetDirectoryName(nircmd);
            p["AdkPe"] = ResolveOr("%ADK_PE_DIR%", map,
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                    @"Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64"));
            return p;
        }

        static string ResolveOr(string text, Dictionary<string, string> map, string fallback)
        {
            string r = DvtUtil.Resolve(text, map);
            return r.Contains("%") ? fallback : r;
        }

        void UpdateOutputStatus()
        {
            Dictionary<string, string> p = GetPaths();
            SetBuildStatus(lblBootStatus, L.T("label.boot_wim"), Path.Combine(p["Boot"], "boot.wim"), p["Boot"]);
            SetBuildStatus(lblTestStatus, L.T("label.boot_wim"), Path.Combine(p["Test"], "boot.wim"), p["Test"]);
            SetBuildStatus(lblMediaWim, L.T("label.media_wim"), p["MediaWim"], "");
            SetBuildStatus(lblMediaIso, L.T("label.iso"), p["MediaIso"], p["MediaOut"]);
        }

        static void SetBuildStatus(Label l, string what, string file, string folder)
        {
            bool ok = File.Exists(file);
            l.Text = (ok ? "\u2714 " + L.F("status.built", what, DvtUtil.FileText(file)) : "\u2716 " + L.F("status.not_built", what)) +
                (folder.Length > 0 ? "      " + folder : "");
            l.ForeColor = ok ? Color.FromArgb(16, 124, 16) : SystemColors.GrayText;
            l.Font = Ui.FontBold;
        }

        // ============================================================
        //  unsaved changes: editor keys and/or "ip"
        // ============================================================
        string[] AllItems()
        {
            List<string> l = new List<string>(editors.Keys);
            l.Add("ip");
            return l.ToArray();
        }

        bool IsDirty(string k)
        {
            if (k == "ip") return ipPanel.Dirty;
            ConfigEditor ed = editors[k];
            ed.EndEditing();
            return ed.Dirty;
        }

        string ItemPath(string k)
        {
            return k == "ip" ? ipPanel.FilePath : editors[k].FilePath;
        }

        bool ConfirmUnsaved(string[] items, string action)
        {
            List<string> dirty = new List<string>();
            foreach (string k in items) if (IsDirty(k)) dirty.Add(k);
            if (dirty.Count == 0) return true;
            List<string> names = new List<string>();
            foreach (string k in dirty) names.Add(ItemPath(k));
            DialogResult r = MessageBox.Show(this,
                L.F("unsaved.question", "  " + string.Join("\r\n  ", names.ToArray()), action),
                "DVT GUI", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            if (r == DialogResult.Cancel) return false;
            foreach (string k in dirty)
            {
                if (r == DialogResult.Yes)
                {
                    bool ok = (k == "ip") ? ipPanel.SaveFile() : editors[k].SaveFile();
                    if (!ok) return false;
                }
                else
                {
                    if (k == "ip") ipPanel.LoadFile(); else editors[k].LoadFile();
                }
            }
            return true;
        }

        // ============================================================
        //  running the DVT scripts
        // ============================================================
        void StartScript(string bat, string argument, string title, bool isMedia)
        {
            if (job != null && !job.HasExited)
            {
                Ui.Info(L.F("job.running", jobTitle), MessageBoxIcon.Warning);
                return;
            }
            if (!ConfirmUnsaved(AllItems(), L.T("action.run"))) return;
            string path = Path.Combine(DataDir, bat);
            if (!File.Exists(path)) { Ui.Info(L.F("msg.not_found", path), MessageBoxIcon.Error); return; }

            ProcessStartInfo psi = new ProcessStartInfo(path, argument);
            psi.UseShellExecute = true;
            psi.Verb = "runas";
            psi.WorkingDirectory = DataDir;
            try
            {
                job = Process.Start(psi);
            }
            catch (Win32Exception ex)
            {
                job = null;
                SetStatus(ex.NativeErrorCode == 1223 ? L.F("job.cancelled_uac", title) : L.F("job.not_started", title, ex.Message));
                return;
            }
            catch (Exception ex)
            {
                job = null;
                SetStatus(L.F("job.not_started", title, ex.Message));
                return;
            }
            if (job == null) { SetStatus(L.F("job.not_started", title, "")); return; }
            jobTitle = title;
            jobWasMedia = isMedia;
            SetStatus(L.F("job.started", title, DateTime.Now.ToString("HH:mm:ss")));
        }

        void CheckJob()
        {
            if (job == null) return;
            int? code = null;
            try
            {
                if (!job.HasExited) return;
                code = job.ExitCode;
            }
            catch (Exception) { }
            string result;
            if (code == null) result = L.T("job.result_finished");
            else if (code == 0) result = L.T("job.result_ok");
            else if (code == 1) result = L.T("job.result_failed");
            else if (code == 2) result = L.T("job.result_cancelled");
            else if (code == 10) result = L.T("job.result_elevation");
            else result = L.F("job.result_code", code);
            SetStatus(L.F("job.done", jobTitle, result, DateTime.Now.ToString("HH:mm:ss")));
            job.Dispose();
            job = null;

            UpdateOutputStatus();
            if (jobWasMedia)
            {
                // a new or updated USB drive: refresh the list, but never drop unsaved edits
                if (!editors["mediape"].Dirty && !ipPanel.Dirty)
                {
                    UpdateMediaDriveList();
                    SetMediaTarget(mediaDrive);
                }
                else filesPanel.RefreshStatus();
            }
        }

        void CopyClientPackage(string source, string folderName, string clientPath)
        {
            if (!File.Exists(Path.Combine(source, "boot.wim")))
            {
                Ui.Info(L.F("pkg.build_first", Path.Combine(source, "boot.wim")), MessageBoxIcon.Warning);
                return;
            }
            using (FolderBrowserDialog dlg = new FolderBrowserDialog())
            {
                dlg.Description = L.F("pkg.select", folderName);
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                string dest = Path.Combine(dlg.SelectedPath, folderName);
                try
                {
                    Cursor = Cursors.WaitCursor;
                    CopyFolder(source, dest);
                    Cursor = Cursors.Default;
                    Ui.Info(L.F("pkg.done", dest, clientPath));
                    SetStatus(L.F("status.pkg_copied", dest));
                }
                catch (Exception ex)
                {
                    Cursor = Cursors.Default;
                    Ui.Info(L.F("msg.copy_failed", ex.Message), MessageBoxIcon.Error);
                }
            }
        }

        static void CopyFolder(string src, string dest)
        {
            Directory.CreateDirectory(dest);
            foreach (string f in Directory.GetFiles(src))
                File.Copy(f, Path.Combine(dest, Path.GetFileName(f)), true);
            foreach (string d in Directory.GetDirectories(src))
                CopyFolder(d, Path.Combine(dest, Path.GetFileName(d)));
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            timer.Stop();
            base.OnFormClosed(e);
        }
    }
}
