// ============================================================
//  DVT GUI - QbtPanel.cs
//  Page "qBittorrent (seeder)" (first page of the sidebar):
//   - Install / update: finds the newest stable qBittorrent release
//     (data\qbt.ini, SourceForge release list), downloads the standard
//     x64 setup, unpacks it with 7-Zip into a temporary folder (nothing
//     is installed in Windows) and copies only the program files to
//     <build>\qbittorrent. A "profile" folder next to qbittorrent.exe
//     makes qBittorrent portable: its settings stay in
//     <build>\qbittorrent\profile. 7-Zip: the installed one, else 7z.exe
//     unpacked from the 7-Zip setup by 7zr.exe (_output\qbt_download\7zip).
//   - Apply settings: copies the ready-made settings file for the link
//     speed of this PC (doc\qbittorrent.ini\qbittorrent.ini.1G or .100)
//     to profile\qBittorrent\config\qBittorrent.ini (the old file is
//     backed up to _output\gui_backup first).
//   - Image folder: checks the folder that becomes the torrent (backup.wim
//     and dvt_check.txt required, dvt_check.txt created when missing) and
//     calculates the size of the restore with wimlib (APPLIED_SIZE_MB of
//     the WinPE settings, smallest disk that can be restored).
// ============================================================
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Text;

namespace Dvt
{
    public class QbtPanel : UserControl
    {
        readonly string rootDir, downloadDir;
        readonly Dictionary<string, List<KeyValuePair<string, string>>> data;
        readonly Label[] statusLabels = new Label[5];
        readonly ComboBox cboProfile;
        readonly TextBox txtImage;
        readonly Button btnCheck, btnSize;
        readonly Func<Dictionary<string, string>> getPaths;
        readonly Func<string, string, List<string>> setPeValue;
        readonly Button btnFirewall;
        readonly Button btnInstall, btnApply, btnLocal, btnStart, btnOpen, btnHome, btnRefresh;
        readonly ProgressBar progress;
        readonly Label lblProgress;
        readonly TextBox log;
        BackgroundWorker worker;
        string latestVersion;

        // paths: output folders of MainForm (PE_TOOLS_DIR = "PeTools");
        // peValue: writes set "NAME=value" into the WinPE settings files
        public QbtPanel(string root, Func<Dictionary<string, string>> paths, Func<string, string, List<string>> peValue)
        {
            rootDir = root;
            getPaths = paths;
            setPeValue = peValue;
            downloadDir = Path.Combine(Path.Combine(root, "_output"), "qbt_download");
            data = L.ReadData("qbt.ini");
            Dock = DockStyle.Fill;

            // the subtitle is shown in the header of the seeder page (MainForm)
            TableLayoutPanel lay = Ui.NewRows(5 * 28 + 4, 40, 40, 40, 28, 0, 64);

            TableLayoutPanel st = new TableLayoutPanel();
            st.Dock = DockStyle.Fill;
            st.ColumnCount = 2;
            st.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Ui.S(230)));
            st.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            st.RowCount = 5;
            string[] names = { L.T("qbt.row_installed"), L.T("qbt.row_latest"), L.T("qbt.row_link"), L.T("qbt.row_settings"), L.T("qbt.row_firewall") };
            for (int n = 0; n < 5; n++)
            {
                st.RowStyles.Add(new RowStyle(SizeType.Absolute, Ui.S(28)));
                st.Controls.Add(Ui.NewLabel(names[n]), 0, n);
                statusLabels[n] = Ui.NewLabel("");
                statusLabels[n].Font = Ui.FontBold;
                st.Controls.Add(statusLabels[n], 1, n);
            }
            lay.Controls.Add(st, 0, 0);

            // -- qBittorrent: install / update, start, folder --
            FlowLayoutPanel fl = Ui.NewFlow();
            btnInstall = Ui.NewButton(L.T("qbt.btn_install"), 185);
            Ui.Primary(btnInstall, Palette.Seeder);
            btnStart = Ui.NewButton(L.T("qbt.btn_start"), 120);
            btnOpen = Ui.NewButton(L.T("qbt.btn_open"), 100);
            btnHome = Ui.NewButton(L.T("tools.btn_home"), 80);
            btnRefresh = Ui.NewButton(L.T("adk.btn_refresh"), 80);
            foreach (Button b in new[] { btnInstall, btnStart, btnOpen, btnHome, btnRefresh }) FitButton(b);
            fl.Controls.AddRange(new Control[] { RowLabel(L.T("qbt.group_program")), btnInstall, btnStart, btnOpen, btnHome, btnRefresh });
            lay.Controls.Add(fl, 0, 1);

            // -- qBittorrent settings: settings file for the link speed, update for this PC --
            FlowLayoutPanel fo = Ui.NewFlow();
            cboProfile = new ComboBox();
            cboProfile.DropDownStyle = ComboBoxStyle.DropDownList;
            cboProfile.Width = Ui.S(230);
            cboProfile.Margin = new Padding(0, Ui.S(5), Ui.S(6), 0);
            cboProfile.Items.AddRange(new object[] { L.T("qbt.profile_auto"), L.T("qbt.profile_1g"), L.T("qbt.profile_100") });
            cboProfile.SelectedIndex = 0;
            btnApply = Ui.NewButton(L.T("qbt.btn_apply"), 140);
            btnLocal = Ui.NewButton(L.T("qbt.btn_local"), 150);
            btnFirewall = Ui.NewButton(L.T("qbt.btn_firewall"), 150);
            // widths from the text, so the row fits the default window size
            FitCombo(cboProfile);
            foreach (Button b in new[] { btnApply, btnLocal, btnFirewall }) FitButton(b);
            fo.Controls.AddRange(new Control[] { RowLabel(L.T("qbt.group_settings")), cboProfile, btnApply, btnLocal, btnFirewall });
            lay.Controls.Add(fo, 0, 2);

            // -- folder of the image to deploy (DL_NAME): backup.wim + dvt_check.txt --
            FlowLayoutPanel fi = Ui.NewFlow();
            Label li = RowLabel(L.T("qbt.image_folder"));
            txtImage = new TextBox();
            txtImage.Width = Ui.S(240);
            txtImage.Margin = new Padding(0, Ui.S(5), Ui.S(6), 0);
            Button btnBrowse = Ui.NewButton(L.T("qbt.btn_browse"), 90);
            btnCheck = Ui.NewButton(L.T("qbt.btn_check"), 150);
            btnSize = Ui.NewButton(L.T("qbt.btn_size"), 150);
            foreach (Button b in new[] { btnBrowse, btnCheck, btnSize }) FitButton(b);
            fi.Controls.AddRange(new Control[] { li, txtImage, btnBrowse, btnCheck, btnSize });
            lay.Controls.Add(fi, 0, 3);
            btnBrowse.Click += delegate
            {
                using (FolderBrowserDialog dlg = new FolderBrowserDialog())
                {
                    dlg.Description = L.F("qbt.select_image", PeValue("DL_NAME", "DVT_backup"));
                    if (Directory.Exists(txtImage.Text)) dlg.SelectedPath = txtImage.Text;
                    if (dlg.ShowDialog(this) == DialogResult.OK) { txtImage.Text = dlg.SelectedPath; CheckImageFolder(); }
                }
            };
            btnCheck.Click += delegate { CheckImageFolder(); };
            btnSize.Click += delegate { CalculateSize(); };

            FlowLayoutPanel fp = Ui.NewFlow();
            progress = new ProgressBar();
            progress.Width = Ui.S(320);
            progress.Height = Ui.S(18);
            progress.Margin = new Padding(0, Ui.S(5), Ui.S(10), 0);
            lblProgress = Ui.NewFlowLabel("");
            lblProgress.Margin = new Padding(0, Ui.S(6), 0, 0);
            fp.Controls.Add(progress);
            fp.Controls.Add(lblProgress);
            lay.Controls.Add(fp, 0, 4);

            log = new TextBox();
            log.Dock = DockStyle.Fill;
            log.Multiline = true;
            log.ReadOnly = true;
            log.ScrollBars = ScrollBars.Vertical;
            log.Font = Ui.FontMono;
            log.BackColor = SystemColors.Window;
            lay.Controls.Add(log, 0, 5);

            Label note = Ui.NewHint(L.T("qbt.note"));
            note.TextAlign = ContentAlignment.TopLeft;
            lay.Controls.Add(note, 0, 6);
            Controls.Add(lay);

            btnInstall.Click += delegate { StartInstall(); };
            btnApply.Click += delegate { ApplySettings(true); };
            btnLocal.Click += delegate { UpdateForThisPc(); };
            btnFirewall.Click += delegate { AddFirewallRules(true); };
            btnStart.Click += delegate
            {
                if (File.Exists(ExePath)) Process.Start(new ProcessStartInfo(ExePath) { WorkingDirectory = InstallDir });
            };
            btnOpen.Click += delegate { Ui.OpenFolder(Directory.Exists(InstallDir) ? InstallDir : rootDir); };
            btnHome.Click += delegate
            {
                string url = Value("download", "home");
                if (url.StartsWith("https://")) Process.Start(url);
            };
            btnRefresh.Click += delegate { RefreshStatus(); };
            cboProfile.SelectedIndexChanged += delegate { RefreshStatus(); };

            RefreshStatus();
        }

        // button width = text width + padding (at least 80)
        static void FitButton(Button b)
        {
            int w = TextRenderer.MeasureText(b.Text, Ui.FontUI).Width + Ui.S(22);
            b.Width = Math.Max(Ui.S(80), w);
        }

        // combo width = longest item + room for the arrow
        static void FitCombo(ComboBox c)
        {
            int w = 0;
            foreach (object o in c.Items) w = Math.Max(w, TextRenderer.MeasureText(o.ToString(), Ui.FontUI).Width);
            c.Width = w + Ui.S(30);
        }

        // bold label of the same width at the start of each button row
        static Label RowLabel(string text)
        {
            Label l = new Label();
            l.Text = text;
            l.Font = Ui.FontBold;
            l.AutoSize = false;
            l.AutoEllipsis = true;
            l.Width = Ui.S(140);
            l.Height = Ui.S(24);
            l.TextAlign = ContentAlignment.MiddleLeft;
            l.Margin = new Padding(0, Ui.S(5), Ui.S(6), 0);
            return l;
        }

        public bool Busy { get { return worker != null && worker.IsBusy; } }

        string Value(string section, string key) { return L.Value(data, section, key).Trim(); }

        string InstallDir
        {
            get
            {
                string f = Value("install", "folder");
                return Path.Combine(rootDir, f.Length > 0 ? f : "qbittorrent");
            }
        }
        string ExePath { get { return Path.Combine(InstallDir, "qbittorrent.exe"); } }
        string ProfileDir { get { return Path.Combine(InstallDir, "profile"); } }
        string IniPath { get { return Path.Combine(ProfileDir, @"qBittorrent\config\qBittorrent.ini"); } }

        void Log(string text)
        {
            log.AppendText(DateTime.Now.ToString("HH:mm:ss") + "  " + text + "\r\n");
        }

        void SetBusy(bool busy)
        {
            foreach (Control c in new Control[] { btnInstall, btnApply, btnLocal, btnFirewall, btnStart, btnRefresh, cboProfile })
                c.Enabled = !busy;
            if (!busy) { progress.Style = ProgressBarStyle.Blocks; progress.Value = 0; }
        }

        // ---------- status ----------

        public void RefreshStatus()
        {
            if (data == null)
            {
                SetLine(0, false, L.T("qbt.no_data"));
                return;
            }
            string ver = InstalledVersion();
            SetLine(0, ver != null, ver != null ? L.F("qbt.installed", ver, Ui.ShortPath(InstallDir)) : L.F("qbt.not_installed", Ui.ShortPath(InstallDir)));

            statusLabels[1].Text = "\u2022 " + (latestVersion ?? L.T("qbt.latest_unknown"));
            statusLabels[1].ForeColor = SystemColors.ControlText;

            LinkInfo li = DetectLink();
            statusLabels[2].Text = "\u2022 " + (li == null ? L.T("qbt.link_unknown") : L.F("qbt.link", li.Name, SpeedText(li.Mbps), li.Address));
            statusLabels[2].ForeColor = SystemColors.ControlText;

            bool has = File.Exists(IniPath);
            string chosen = ProfileFileName(ChooseProfile(li));
            SetLine(3, has, (has ? L.T("qbt.settings_present") : L.T("qbt.settings_missing")) + "   " + L.F("qbt.settings_next", chosen));

            bool installed = ver != null;
            btnApply.Enabled = installed && !Busy;
            btnLocal.Enabled = installed && has && !Busy;
            btnStart.Enabled = installed && !Busy;
            btnFirewall.Enabled = installed && !Busy;

            List<string> missing = MissingFirewallRules();
            if (missing == null) SetLine(4, false, L.T("qbt.fw_unknown"));
            else if (missing.Count == 0)
            {
                int[] pp = FirewallPorts();
                SetLine(4, true, L.F("qbt.fw_ok", pp[0], pp[1]));
            }
            else SetLine(4, false, L.F("qbt.fw_missing", missing.Count, FirewallRuleNames.Length));
        }

        void SetLine(int n, bool ok, string text)
        {
            statusLabels[n].Text = (ok ? "\u2714 " : "\u2716 ") + text;
            statusLabels[n].ForeColor = ok ? Color.FromArgb(16, 124, 16) : Ui.ColorDanger;
        }

        string InstalledVersion()
        {
            if (!File.Exists(ExePath)) return null;
            string v = AdkCore.FileVersion(ExePath);
            return v.Length > 0 ? v : "?";
        }

        static string SpeedText(long mbps)
        {
            return mbps >= 1000 ? (mbps / 1000.0).ToString("0.#") + " Gbps" : mbps + " Mbps";
        }

        // ---------- link speed ----------

        class LinkInfo { public string Name, Address, Id; public long Mbps; }

        // The connected adapter with an IPv4 default gateway and the highest speed
        static LinkInfo DetectLink()
        {
            LinkInfo best = null;
            try
            {
                foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (ni.OperationalStatus != OperationalStatus.Up) continue;
                    if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback || ni.NetworkInterfaceType == NetworkInterfaceType.Tunnel) continue;
                    IPInterfaceProperties p = ni.GetIPProperties();
                    bool gateway = false;
                    foreach (GatewayIPAddressInformation g in p.GatewayAddresses)
                        if (g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any)) gateway = true;
                    if (!gateway) continue;
                    string addr = "";
                    foreach (UnicastIPAddressInformation u in p.UnicastAddresses)
                        if (u.Address.AddressFamily == AddressFamily.InterNetwork) { addr = u.Address.ToString(); break; }
                    long mbps = ni.Speed / 1000000;
                    if (best == null || mbps > best.Mbps)
                        best = new LinkInfo { Name = ni.Name, Address = addr, Id = ni.Id, Mbps = mbps };
                }
            }
            catch (Exception) { }
            return best;
        }

        // "1g" or "100"
        string ChooseProfile(LinkInfo li)
        {
            if (cboProfile.SelectedIndex == 1) return "1g";
            if (cboProfile.SelectedIndex == 2) return "100";
            long threshold;
            if (!long.TryParse(Value("profiles", "threshold_mbps"), out threshold) || threshold <= 0) threshold = 1000;
            return li != null && li.Mbps >= threshold ? "1g" : "100";
        }

        string ProfileSource(string key)
        {
            string rel = Value("profiles", key);
            return rel.Length == 0 ? "" : Path.Combine(rootDir, rel);
        }

        string ProfileFileName(string key)
        {
            string f = ProfileSource(key);
            return f.Length == 0 ? "?" : Path.GetFileName(f);
        }

        // ---------- apply settings ----------

        static bool QbtRunning()
        {
            try { return Process.GetProcessesByName("qbittorrent").Length > 0; }
            catch (Exception) { return false; }
        }

        // ask = false: called after a first installation (no confirmation)
        bool ApplySettings(bool ask)
        {
            if (!File.Exists(ExePath)) return false;
            string key = ChooseProfile(DetectLink());
            string src = ProfileSource(key);
            if (!File.Exists(src))
            {
                Ui.Info(L.F("msg.not_found", Ui.ShortPath(src)), MessageBoxIcon.Error);
                return false;
            }
            if (QbtRunning())
            {
                Ui.Info(L.T("qbt.running"), MessageBoxIcon.Warning);
                return false;
            }
            bool exists = File.Exists(IniPath);
            if (ask && !Ui.YesNo(L.F(exists ? "qbt.confirm_replace" : "qbt.confirm_apply", Path.GetFileName(src), Ui.ShortPath(IniPath)), MessageBoxIcon.Question))
                return false;
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(IniPath));
                if (exists)
                {
                    string b = DvtUtil.BackupFile(IniPath, Ui.Main.BackupDir);
                    if (b != null) Log(L.F("qbt.log_backup", Ui.ShortPath(b)));
                }
                File.Copy(src, IniPath, true);
                Log(L.F("qbt.log_applied", Path.GetFileName(src), Ui.ShortPath(IniPath)));
                Ui.Status(L.F("qbt.log_applied", Path.GetFileName(src), Ui.ShortPath(IniPath)));
            }
            catch (Exception ex)
            {
                Log(ex.Message);
                Ui.Info(L.F("msg.copy_failed", ex.Message), MessageBoxIcon.Error);
                return false;
            }
            // the copied file gets the IP and the adapter of this PC
            string done = Localize(DetectLink());
            RefreshStatus();
            // after install / update (ask = false) the firewall rules are added next
            Ui.Info((done ?? L.T("qbt.applied_next")) + (ask ? FirewallHint() : ""));
            return true;
        }

        // Button "Update for this PC": the existing qBittorrent.ini gets the
        // IP and the adapter of this PC (the other settings stay)
        void UpdateForThisPc()
        {
            if (!File.Exists(IniPath)) { Ui.Info(L.F("msg.not_found", Ui.ShortPath(IniPath)), MessageBoxIcon.Warning); return; }
            if (QbtRunning()) { Ui.Info(L.T("qbt.running"), MessageBoxIcon.Warning); return; }
            LinkInfo li = DetectLink();
            if (li == null || li.Address.Length == 0) { Ui.Info(L.T("qbt.link_unknown"), MessageBoxIcon.Warning); return; }
            if (!Ui.YesNo(L.F("qbt.confirm_local", Ui.ShortPath(IniPath), li.Name, li.Address), MessageBoxIcon.Question)) return;
            try
            {
                string b = DvtUtil.BackupFile(IniPath, Ui.Main.BackupDir);
                if (b != null) Log(L.F("qbt.log_backup", Ui.ShortPath(b)));
            }
            catch (Exception ex) { Ui.Info(ex.Message, MessageBoxIcon.Error); return; }
            string done = Localize(li);
            RefreshStatus();
            if (done != null) Ui.Info(done + FirewallHint());
        }

        // a hint for the message when firewall rules are missing, else ""
        static string FirewallHint()
        {
            List<string> missing = MissingFirewallRules();
            return missing != null && missing.Count > 0 ? "\r\n\r\n" + L.T("qbt.fw_hint") : "";
        }

        // Writes the IP and the network adapter of this PC to qBittorrent.ini:
        //   [BitTorrent] Session\Interface        adapter ID (e.g. ethernet_32769)
        //                Session\InterfaceName    adapter name (e.g. Ethernet)
        //                Session\InterfaceAddress IP address to bind to
        //   [TorrentCreator] TrackerList        http://<IP>:<port>/announce
        // Returns the message for the user, or null when nothing was changed.
        string Localize(LinkInfo li)
        {
            if (li == null || li.Address.Length == 0)
            {
                Log(L.T("qbt.link_unknown"));
                Ui.Info(L.T("qbt.local_none"), MessageBoxIcon.Warning);
                return null;
            }
            string id = LuidName(li.Id);
            try
            {
                List<string> lines = new List<string>(File.ReadAllLines(IniPath, new UTF8Encoding(false)));
                if (id != null) SetIni(lines, "BitTorrent", @"Session\Interface", id);
                SetIni(lines, "BitTorrent", @"Session\InterfaceName", li.Name);
                SetIni(lines, "BitTorrent", @"Session\InterfaceAddress", li.Address);
                string trackers = GetIni(lines, "TorrentCreator", "TrackerList");
                string port = Value("profiles", "tracker_port");
                if (port.Length == 0) port = "9000";
                string newTrackers = trackers == null || trackers.Trim().Length == 0
                    ? "http://" + li.Address + ":" + port + "/announce"
                    : Regex.Replace(trackers, @"(https?://)[^:/\s]+", "${1}" + li.Address);
                SetIni(lines, "TorrentCreator", "TrackerList", newTrackers);
                File.WriteAllLines(IniPath, lines.ToArray(), new UTF8Encoding(false));
                Log(L.F("qbt.log_local", li.Name, id ?? "-", li.Address, newTrackers));
                Ui.Status(L.F("qbt.log_local", li.Name, id ?? "-", li.Address, newTrackers));
                return L.F("qbt.local_done", li.Name, li.Address, newTrackers) + (id == null ? "\r\n\r\n" + L.T("qbt.local_no_id") : "");
            }
            catch (Exception ex)
            {
                Log(ex.Message);
                Ui.Info(L.F("msg.copy_failed", ex.Message), MessageBoxIcon.Error);
                return null;
            }
        }

        // index of the [section] line, or -1
        static int FindSection(List<string> lines, string section)
        {
            for (int n = 0; n < lines.Count; n++)
                if (string.Equals(lines[n].Trim(), "[" + section + "]", StringComparison.OrdinalIgnoreCase)) return n;
            return -1;
        }

        static string GetIni(List<string> lines, string section, string key)
        {
            int start = FindSection(lines, section);
            if (start < 0) return null;
            for (int n = start + 1; n < lines.Count && !lines[n].TrimStart().StartsWith("["); n++)
            {
                int eq = lines[n].IndexOf('=');
                if (eq > 0 && string.Equals(lines[n].Substring(0, eq).Trim(), key, StringComparison.OrdinalIgnoreCase))
                    return lines[n].Substring(eq + 1);
            }
            return null;
        }

        // replaces key=value in [section], or adds it (and the section)
        static void SetIni(List<string> lines, string section, string key, string value)
        {
            int start = FindSection(lines, section);
            if (start < 0)
            {
                if (lines.Count > 0 && lines[lines.Count - 1].Trim().Length > 0) lines.Add("");
                lines.Add("[" + section + "]");
                lines.Add(key + "=" + value);
                return;
            }
            int last = start;
            for (int n = start + 1; n < lines.Count && !lines[n].TrimStart().StartsWith("["); n++)
            {
                int eq = lines[n].IndexOf('=');
                if (eq > 0 && string.Equals(lines[n].Substring(0, eq).Trim(), key, StringComparison.OrdinalIgnoreCase))
                {
                    lines[n] = key + "=" + value;
                    return;
                }
                if (lines[n].Trim().Length > 0) last = n;
            }
            lines.Insert(last + 1, key + "=" + value);
        }

        // Interface ID as qBittorrent stores it (Qt: ConvertInterfaceLuidToName),
        // e.g. "ethernet_32769"; null when it cannot be read
        static string LuidName(string adapterId)
        {
            try
            {
                Guid g = new Guid(adapterId);
                ulong luid;
                if (ConvertInterfaceGuidToLuid(ref g, out luid) != 0) return null;
                StringBuilder sb = new StringBuilder(260);
                if (ConvertInterfaceLuidToNameW(ref luid, sb, sb.Capacity) != 0) return null;
                return sb.ToString();
            }
            catch (Exception) { return null; }
        }

        [DllImport("iphlpapi.dll")]
        static extern int ConvertInterfaceGuidToLuid(ref Guid interfaceGuid, out ulong interfaceLuid);

        [DllImport("iphlpapi.dll", CharSet = CharSet.Unicode)]
        static extern int ConvertInterfaceLuidToNameW(ref ulong interfaceLuid, StringBuilder interfaceName, int length);

        // ---------- Windows Firewall: inbound rules for qBittorrent ----------

        // rule names (also in doc\manual.md, "Firewall"): program, peer port TCP / UDP, tracker port
        static readonly string[] FirewallRuleNames = {
            "DVT qBittorrent program", "DVT qBittorrent peer", "DVT qBittorrent peer UDP", "DVT qBittorrent tracker" };

        // { peer port, tracker port } from qBittorrent.ini, else from the
        // settings file that would be applied, else 6881 / tracker_port
        int[] FirewallPorts()
        {
            int peer = 0, tracker = 0;
            foreach (string f in new[] { IniPath, ProfileSource(ChooseProfile(DetectLink())) })
            {
                try
                {
                    if (string.IsNullOrEmpty(f) || !File.Exists(f)) continue;
                    List<string> lines = new List<string>(File.ReadAllLines(f, new UTF8Encoding(false)));
                    int v;
                    if (peer == 0 && int.TryParse((GetIni(lines, "BitTorrent", @"Session\Port") ?? "").Trim(), out v) && v > 0 && v < 65536) peer = v;
                    if (tracker == 0 && int.TryParse((GetIni(lines, "Preferences", @"Advanced\trackerPort") ?? "").Trim(), out v) && v > 0 && v < 65536) tracker = v;
                }
                catch (Exception) { }
            }
            if (peer == 0) peer = 6881;
            if (tracker == 0)
            {
                int v;
                tracker = int.TryParse(Value("profiles", "tracker_port"), out v) && v > 0 ? v : 9000;
            }
            return new int[] { peer, tracker };
        }

        // names of the rules that do not exist (null = netsh could not be run);
        // "netsh ... show rule" works without administrator rights and exits
        // with 1 when no rule has the name
        static List<string> MissingFirewallRules()
        {
            List<string> missing = new List<string>();
            try
            {
                string netsh = Path.Combine(Environment.SystemDirectory, "netsh.exe");
                if (!File.Exists(netsh)) return null;
                foreach (string name in FirewallRuleNames)
                {
                    ProcessStartInfo psi = new ProcessStartInfo(netsh, "advfirewall firewall show rule name=\"" + name + "\"");
                    psi.UseShellExecute = false;
                    psi.CreateNoWindow = true;
                    psi.RedirectStandardOutput = true;
                    psi.RedirectStandardError = true;
                    using (Process p = Process.Start(psi))
                    {
                        p.StandardOutput.ReadToEnd();
                        p.StandardError.ReadToEnd();
                        if (!p.WaitForExit(10000)) { try { p.Kill(); } catch (Exception) { } return null; }
                        if (p.ExitCode != 0) missing.Add(name);
                    }
                }
            }
            catch (Exception) { return null; }
            return missing;
        }

        // Writes the netsh commands to a batch file in %TEMP% and runs it once
        // elevated (one UAC prompt). Old rules of the same names are removed
        // first, so the rules always match the current ports and program.
        // ask = false: after install / update, without the question; a
        // success is only logged, a failure is shown.
        void AddFirewallRules(bool ask)
        {
            if (Busy) return;
            if (!File.Exists(ExePath)) { Ui.Info(L.F("qbt.no_exe", Ui.ShortPath(InstallDir)), MessageBoxIcon.Warning); return; }
            int[] pp = FirewallPorts();
            if (ask && !Ui.YesNo(L.F("qbt.fw_confirm", pp[0], pp[1], Ui.ShortPath(ExePath)), MessageBoxIcon.Question)) return;

            string dir = Path.Combine(Path.GetTempPath(), "DVT_qbt_firewall");
            string bat = Path.Combine(dir, "firewall.cmd");
            string logFile = Path.Combine(dir, "firewall.log");
            string add = "netsh advfirewall firewall add rule dir=in action=allow enable=yes profile=any ";
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("@echo off");
            sb.AppendLine("rem DVT GUI: inbound Windows Firewall rules for the portable qBittorrent (seeder)");
            sb.AppendLine("set \"FAIL=0\"");
            sb.AppendLine("> \"%~dp0firewall.log\" echo Windows Firewall rules for qBittorrent");
            foreach (string name in FirewallRuleNames)
                sb.AppendLine("netsh advfirewall firewall delete rule name=\"" + name + "\" >nul 2>&1");
            string[] cmds = {
                add + "name=\"" + FirewallRuleNames[0] + "\" program=\"" + ExePath + "\"",
                add + "name=\"" + FirewallRuleNames[1] + "\" protocol=TCP localport=" + pp[0],
                add + "name=\"" + FirewallRuleNames[2] + "\" protocol=UDP localport=" + pp[0],
                add + "name=\"" + FirewallRuleNames[3] + "\" protocol=TCP localport=" + pp[1] };
            foreach (string c in cmds)
            {
                sb.AppendLine(">> \"%~dp0firewall.log\" echo " + c.Replace("\"", ""));
                sb.AppendLine(c + " >> \"%~dp0firewall.log\" 2>&1");
                sb.AppendLine("if errorlevel 1 set \"FAIL=1\"");
            }
            sb.AppendLine("exit /b %FAIL%");

            Log(L.F("qbt.fw_log", pp[0], pp[1]));
            int code;
            try
            {
                Directory.CreateDirectory(dir);
                File.WriteAllText(bat, sb.ToString(), Encoding.ASCII);
                if (File.Exists(logFile)) File.Delete(logFile);
                ProcessStartInfo psi = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "cmd.exe"), "/c \"\"" + bat + "\"\"");
                psi.UseShellExecute = true;
                psi.Verb = "runas";
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                Cursor old = Cursor.Current;
                Cursor.Current = Cursors.WaitCursor;
                try
                {
                    using (Process p = Process.Start(psi))
                    {
                        p.WaitForExit(60000);
                        code = p.HasExited ? p.ExitCode : -1;
                    }
                }
                finally { Cursor.Current = old; }
            }
            catch (Win32Exception ex)
            {
                string msg = ex.NativeErrorCode == 1223 ? L.T("qbt.fw_cancelled") : ex.Message;
                Log("  " + msg);
                Ui.Info(msg, MessageBoxIcon.Warning);
                return;
            }
            catch (Exception ex) { Log("  " + ex.Message); Ui.Info(ex.Message, MessageBoxIcon.Error); return; }

            // netsh writes in the OEM code page of the console
            try
            {
                if (File.Exists(logFile))
                {
                    Encoding oem = Encoding.Default;
                    try { oem = Encoding.GetEncoding(System.Globalization.CultureInfo.CurrentCulture.TextInfo.OEMCodePage); } catch (Exception) { }
                    foreach (string l in File.ReadAllLines(logFile, oem))
                        if (l.Trim().Length > 0) Log("  " + l.Trim());
                }
            }
            catch (Exception) { }

            RefreshStatus();
            List<string> missing = MissingFirewallRules();
            bool ok = code == 0 && missing != null && missing.Count == 0;
            string text = ok ? L.F("qbt.fw_done", pp[0], pp[1]) : L.F("qbt.fw_failed", code);
            Log(text);
            Ui.Status(text);
            if (ask || !ok) Ui.Info(text, ok ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
        }

        // ---------- folder of the image to deploy ----------

        // value of set "NAME=..." in data\pe\config.cmd (the client local boot)
        string PeValue(string name, string fallback)
        {
            try
            {
                string f = Path.Combine(Path.Combine(Path.Combine(rootDir, "data"), "pe"), "config.cmd");
                foreach (string line in File.ReadAllLines(f))
                {
                    Match m = Regex.Match(line, "^\\s*set\\s+\"" + Regex.Escape(name) + "=([^\"]*)\"", RegexOptions.IgnoreCase);
                    if (m.Success && m.Groups[1].Value.Length > 0) return m.Groups[1].Value;
                }
            }
            catch (Exception) { }
            return fallback;
        }

        // Checks the folder that becomes the torrent (DL_NAME): WIM_NAME and
        // CHECK_FILE are required; a missing CHECK_FILE is created (a few KB,
        // never empty), an empty one is filled after the user agrees.
        void CheckImageFolder()
        {
            string dir = txtImage.Text.Trim().TrimEnd('\\');
            string dlName = PeValue("DL_NAME", "DVT_backup");
            string wimName = PeValue("WIM_NAME", "backup.wim");
            string checkName = PeValue("CHECK_FILE", "dvt_check.txt");
            if (dir.Length == 0 || !Directory.Exists(dir))
            {
                Ui.Info(L.F("qbt.image_missing", dir.Length == 0 ? "-" : dir, dlName), MessageBoxIcon.Warning);
                return;
            }
            List<string> report = new List<string>();
            bool ok = true, created = false;

            // folder name = top folder of the torrent = DL_NAME
            if (!string.Equals(Path.GetFileName(dir), dlName, StringComparison.OrdinalIgnoreCase))
            {
                ok = false;
                report.Add("\u2716 " + L.F("qbt.chk_name", Path.GetFileName(dir), dlName));
            }
            else report.Add("\u2714 " + L.F("qbt.chk_name_ok", dlName));

            // WIM_NAME: required, a WIM file
            string wim = Path.Combine(dir, wimName);
            if (!File.Exists(wim)) { ok = false; report.Add("\u2716 " + L.F("qbt.chk_wim_missing", wimName)); }
            else
            {
                long size = new FileInfo(wim).Length;
                bool magic = false;
                try
                {
                    using (FileStream fs = File.OpenRead(wim))
                    {
                        byte[] b = new byte[5];
                        magic = fs.Read(b, 0, 5) == 5 && Encoding.ASCII.GetString(b) == "MSWIM";
                    }
                }
                catch (Exception) { }
                if (!magic) { ok = false; report.Add("\u2716 " + L.F("qbt.chk_wim_bad", wimName)); }
                else report.Add("\u2714 " + L.F("qbt.chk_wim_ok", wimName, (size / 1048576.0).ToString("N0")));
            }

            // CHECK_FILE: required and not empty; created when missing
            string chk = Path.Combine(dir, checkName);
            try
            {
                if (!File.Exists(chk))
                {
                    WriteCheckFile(chk);
                    created = true;
                    report.Add("\u2714 " + L.F("qbt.chk_check_created", checkName));
                }
                else if (new FileInfo(chk).Length == 0)
                {
                    if (Ui.YesNo(L.F("qbt.chk_check_empty_ask", checkName), MessageBoxIcon.Warning))
                    {
                        WriteCheckFile(chk);
                        created = true;
                        report.Add("\u2714 " + L.F("qbt.chk_check_created", checkName));
                    }
                    else { ok = false; report.Add("\u2716 " + L.F("qbt.chk_check_empty", checkName)); }
                }
                else report.Add("\u2714 " + L.F("qbt.chk_check_ok", checkName, new FileInfo(chk).Length));
            }
            catch (Exception ex) { ok = false; report.Add("\u2716 " + checkName + ": " + ex.Message); }

            // optional parts
            if (Directory.Exists(Path.Combine(dir, "drivers"))) report.Add("\u2022 " + L.T("qbt.chk_drivers"));
            if (File.Exists(Path.Combine(Path.Combine(dir, "files"), "setpc.bat"))) report.Add("\u2022 " + L.T("qbt.chk_setpc"));

            string text = string.Join("\r\n", report.ToArray());
            Log(L.F("qbt.log_check", dir));
            foreach (string r in report) Log("  " + r);
            if (created) text += "\r\n\r\n" + L.T("qbt.chk_recreate_torrent");
            text = (ok ? L.T("qbt.chk_ok") : L.T("qbt.chk_failed")) + "\r\n\r\n" + text;
            Ui.Status(ok ? L.T("qbt.chk_ok") : L.T("qbt.chk_failed"));
            Ui.Info(text, ok ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
        }

        // a few KB of text: aria2c must really download it from a seeder
        static void WriteCheckFile(string path)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("DVT seeder check file - do not delete. Created " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            sb.AppendLine("WinPE downloads only this file to make sure that a seeder is reachable before the disk is erased.");
            sb.AppendLine("Create the torrent again after changing this file.");
            while (sb.Length < 4096) sb.AppendLine("DVT-CHECK " + sb.Length.ToString("D6") + " ................................................................");
            File.WriteAllText(path, sb.ToString(), Encoding.ASCII);
        }

        // ---------- size of the restore (wimlib) ----------

        class WimInfo { public string Name = ""; public long Total = -1, HardLink, Files, Dirs; }

        const long MiB = 1048576;

        static long CeilMiB(long bytes) { return (bytes + MiB - 1) / MiB; }

        int PeInt(string name, int fallback)
        {
            int v;
            return int.TryParse(PeValue(name, ""), out v) && v >= 0 ? v : fallback;
        }

        // Reads backup.wim with "wimlib-imagex info <wim> <index>", adds the
        // other files of the folder and shows APPLIED_SIZE_MB and the
        // smallest disk; the value can be written to the WinPE settings.
        // The sums follow data\common\check_space.bat.
        void CalculateSize()
        {
            string dir = txtImage.Text.Trim().TrimEnd('\\');
            string dlName = PeValue("DL_NAME", "DVT_backup");
            string wimName = PeValue("WIM_NAME", "backup.wim");
            string index = PeValue("WIM_INDEX", "1");
            if (dir.Length == 0 || !Directory.Exists(dir))
            {
                Ui.Info(L.F("qbt.image_missing", dir.Length == 0 ? "-" : dir, dlName), MessageBoxIcon.Warning);
                return;
            }
            string wim = Path.Combine(dir, wimName);
            if (!File.Exists(wim)) { Ui.Info(L.F("qbt.chk_wim_missing", wimName), MessageBoxIcon.Warning); return; }

            string toolDir = Path.Combine(rootDir, "pe_tools");
            try { toolDir = getPaths()["PeTools"]; } catch (Exception) { }
            string wimlib = Path.Combine(toolDir, "wimlib-imagex.exe");
            if (!File.Exists(wimlib))
            {
                Ui.Info(L.F("qbt.size_no_wimlib", Ui.ShortPath(toolDir), L.T("nav.adk") + " > " + L.T("tab.tools")), MessageBoxIcon.Warning);
                return;
            }

            WimInfo w;
            string error;
            Cursor old = Cursor.Current;
            Cursor.Current = Cursors.WaitCursor;
            try
            {
                Log(L.F("qbt.log_size", "wimlib-imagex info \"" + wim + "\" " + index));
                w = ReadWimInfo(wimlib, wim, index, out error);
            }
            finally { Cursor.Current = old; }
            if (w == null)
            {
                Log("  " + error);
                Ui.Info(L.F("qbt.size_failed", wimName, index, error), MessageBoxIcon.Error);
                return;
            }

            // files of the torrent: all files of the folder; "other" = without the WIM
            long allBytes = 0, otherBytes = 0;
            try
            {
                string full = Path.GetFullPath(wim);
                foreach (string f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
                {
                    long n = new FileInfo(f).Length;
                    allBytes += n;
                    if (!string.Equals(Path.GetFullPath(f), full, StringComparison.OrdinalIgnoreCase)) otherBytes += n;
                }
            }
            catch (Exception ex) { Ui.Info(ex.Message, MessageBoxIcon.Error); return; }

            // applied image: file data with hard links counted once, plus about
            // 4 KB per file and folder (NTFS cluster slack and file records)
            long dataBytes = Math.Max(0, w.Total - w.HardLink);
            long overhead = (w.Files + w.Dirs) * 4096;
            long imageMB = CeilMiB(dataBytes + overhead);
            long otherMB = CeilMiB(otherBytes);
            long applied = imageMB + otherMB;
            // download size as check_space.bat counts it (a little more than the real size)
            long dlMB = allBytes / 1000 / 1048 + 1;

            int efi = PeInt("EFI_SIZE_MB", 260), msr = PeInt("MSR_SIZE_MB", 16), bios = PeInt("BIOS_SYS_SIZE_MB", 500);
            int margin = PeInt("SPACE_MARGIN_MB", 2048);
            long sys = Math.Max(efi + msr, bios);
            long needOther = applied + sys + margin;
            long needSame = dlMB + applied + sys + margin;

            // details in the log, a short summary in the message (sizes in GB = 1024 MB)
            Log("  " + L.F("qbt.size_wim", index, w.Name, w.Files.ToString("N0"), w.Dirs.ToString("N0")));
            Log("  Total Bytes " + w.Total.ToString("N0") + ", Hard Link Bytes " + w.HardLink.ToString("N0")
                + ", +4 KB x " + (w.Files + w.Dirs).ToString("N0") + ", other files " + otherBytes.ToString("N0") + " bytes");
            Log("  APPLIED_SIZE_MB = " + applied + ", download " + dlMB + " MB, system partitions " + sys + " MB, SPACE_MARGIN_MB " + margin);

            List<string> r = new List<string>();
            r.Add("APPLIED_SIZE_MB = " + applied);
            r.Add("");
            r.Add(L.T("qbt.size_one"));
            r.Add("   " + L.F("qbt.size_one_sum", Gb(dlMB), Gb(applied), Gb(dlMB + applied)));
            r.Add("   " + L.F("qbt.size_min", DiskSold(needSame)));
            r.Add("");
            r.Add(L.T("qbt.size_two"));
            r.Add("   " + L.F("qbt.size_two_sum", Gb(dlMB), Gb(applied)));
            r.Add("   " + L.F("qbt.size_min", DiskSold(needOther)));
            foreach (string line in r) if (line.Length > 0) Log("  " + line.Trim());

            string value = applied.ToString();
            string text = L.F("qbt.size_title", Ui.ShortPath(dir)) + "\r\n\r\n" + string.Join("\r\n", r.ToArray());
            string units = "\r\n\r\n" + L.F("qbt.size_units", Gb(sys + margin));
            if (setPeValue == null) { Ui.Info(text + units, MessageBoxIcon.Information); return; }
            if (!Ui.YesNo(text + "\r\n\r\n" + L.F("qbt.size_apply_ask", value) + units, MessageBoxIcon.Question))
                return;
            try
            {
                List<string> done = setPeValue("APPLIED_SIZE_MB", value);
                if (done.Count == 0) { Ui.Info(L.F("qbt.size_same", value), MessageBoxIcon.Information); return; }
                List<string> shortNames = new List<string>();
                foreach (string f in done) shortNames.Add(Ui.ShortPath(f));
                string msg = L.F("qbt.size_written", value, string.Join(", ", shortNames.ToArray()));
                Log(msg);
                Ui.Status(msg);
                Ui.Info(msg + "\r\n\r\n" + L.T("qbt.size_rebuild"), MessageBoxIcon.Information);
            }
            catch (Exception ex) { Ui.Info(ex.Message, MessageBoxIcon.Error); }
        }

        // MB (MiB) -> "12.3" GB (GiB)
        static string Gb(long mb) { return (mb / 1024.0).ToString("0.0"); }

        // diskpart shows whole GB (GiB) and check_space.bat counts GB x 1024 MB
        static long DiskGiB(long needMB) { return (needMB + 1023) / 1024; }

        // smallest common disk size (sold in GB of 10^9 bytes) that holds DiskGiB
        static string DiskSold(long needMB)
        {
            long bytes = DiskGiB(needMB) * 1073741824L;
            long[] sizes = { 16, 32, 64, 120, 128, 240, 250, 256, 480, 500, 512, 960, 1000, 1024, 2000, 4000, 8000 };
            foreach (long gb in sizes) if (gb * 1000000000L >= bytes) return gb >= 1000 && gb % 1000 == 0 ? (gb / 1000) + " TB" : gb + " GB";
            return ((bytes + 999999999999L) / 1000000000000L) + " TB";
        }

        // Runs wimlib-imagex info and parses "Total Bytes", "Hard Link Bytes",
        // "File Count", "Directory Count" and "Name". Null on an error.
        static WimInfo ReadWimInfo(string wimlib, string wim, string index, out string error)
        {
            error = "";
            ProcessStartInfo psi = new ProcessStartInfo(wimlib, "info \"" + wim + "\" " + index);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.WorkingDirectory = Path.GetDirectoryName(wimlib);
            byte[] outBytes;
            StringBuilder err = new StringBuilder();
            int code;
            try
            {
                using (Process p = new Process())
                {
                    p.StartInfo = psi;
                    p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) lock (err) err.AppendLine(e.Data); };
                    p.Start();
                    p.BeginErrorReadLine();
                    using (MemoryStream ms = new MemoryStream())
                    {
                        p.StandardOutput.BaseStream.CopyTo(ms);
                        outBytes = ms.ToArray();
                    }
                    if (!p.WaitForExit(120000)) { try { p.Kill(); } catch (Exception) { } error = "timeout"; return null; }
                    p.WaitForExit();
                    code = p.ExitCode;
                }
            }
            catch (Exception ex) { error = ex.Message; return null; }

            string text = DecodeOutput(outBytes);
            WimInfo w = new WimInfo();
            foreach (string raw in text.Split('\n'))
            {
                Match m = Regex.Match(raw, "^\\s*([A-Za-z][A-Za-z ]*?)\\s*:\\s*(.*?)\\s*$");
                if (!m.Success) continue;
                string key = m.Groups[1].Value, val = m.Groups[2].Value;
                if (key == "Name" && w.Name.Length == 0) w.Name = val;
                else if (key == "Total Bytes") w.Total = Number(val);
                else if (key == "Hard Link Bytes") w.HardLink = Number(val);
                else if (key == "File Count") w.Files = Number(val);
                else if (key == "Directory Count") w.Dirs = Number(val);
            }
            if (code != 0 || w.Total < 0)
            {
                string e2;
                lock (err) e2 = err.ToString().Trim();
                if (e2.Length == 0) e2 = text.Trim();
                error = (code != 0 ? "exit code " + code + ": " : "") + (e2.Length > 400 ? e2.Substring(0, 400) : e2);
                return null;
            }
            return w;
        }

        // wimlib may write UTF-16 or UTF-8 when the output is redirected
        static string DecodeOutput(byte[] b)
        {
            int zeros = 0;
            foreach (byte x in b) if (x == 0) zeros++;
            if (b.Length >= 2 && b[0] == 0xFF && b[1] == 0xFE) return Encoding.Unicode.GetString(b, 2, b.Length - 2);
            if (b.Length > 0 && zeros > b.Length / 4) return Encoding.Unicode.GetString(b);
            string t = Encoding.UTF8.GetString(b);
            return t.Length > 0 && t[0] == '\uFEFF' ? t.Substring(1) : t;
        }

        static long Number(string s)
        {
            StringBuilder d = new StringBuilder();
            foreach (char c in s) { if (c >= '0' && c <= '9') d.Append(c); else if (c != ',' && c != '.' && c != ' ') break; }
            long v;
            return long.TryParse(d.ToString(), out v) ? v : 0;
        }

        // ---------- install / update ----------

        class Job { public string Version, Setup, Error; public int Copied; }

        void StartInstall()
        {
            if (Busy) return;
            if (data == null) { Ui.Info(L.T("qbt.no_data"), MessageBoxIcon.Error); return; }
            if (QbtRunning()) { Ui.Info(L.T("qbt.running"), MessageBoxIcon.Warning); return; }
            log.Clear();
            SetBusy(true);
            progress.Style = ProgressBarStyle.Marquee;
            lblProgress.Text = L.T("qbt.state_checking");

            // step 1: newest version (background)
            worker = new BackgroundWorker();
            worker.WorkerReportsProgress = true;
            worker.DoWork += delegate(object s, DoWorkEventArgs e)
            {
                Job j = new Job();
                e.Result = j;
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                try
                {
                    worker.ReportProgress(-1, L.F("qbt.log_list", Value("download", "list")));
                    j.Version = NewestVersion();
                }
                catch (Exception ex)
                {
                    j.Version = Value("download", "fallback_version");
                    worker.ReportProgress(-1, L.F("qbt.log_list_failed", ex.Message, j.Version));
                }
            };
            worker.ProgressChanged += OnProgress;
            worker.RunWorkerCompleted += delegate(object s, RunWorkerCompletedEventArgs e)
            {
                Job j = e.Result as Job;
                worker = null;
                if (j == null || string.IsNullOrEmpty(j.Version)) { Fail(L.T("qbt.no_version")); return; }
                latestVersion = j.Version;
                RefreshStatus();
                Log(L.F("qbt.log_latest", j.Version));
                string installed = InstalledVersion();
                string question = installed != null && SameVersion(installed, j.Version)
                    ? L.F("qbt.confirm_reinstall", j.Version, Ui.ShortPath(InstallDir))
                    : L.F("qbt.confirm_install", j.Version, Ui.ShortPath(InstallDir), installed ?? "-");
                if (!Ui.YesNo(question, MessageBoxIcon.Question)) { Cancel(); return; }
                if (QbtRunning()) { Ui.Info(L.T("qbt.running"), MessageBoxIcon.Warning); Cancel(); return; }
                Install(j);
            };
            worker.RunWorkerAsync();
        }

        void OnProgress(object s, ProgressChangedEventArgs e)
        {
            string text = e.UserState as string;
            if (e.ProgressPercentage < 0) { if (text != null) Log(text); return; }
            progress.Style = ProgressBarStyle.Blocks;
            progress.Value = Math.Min(100, e.ProgressPercentage);
            if (text != null) lblProgress.Text = text;
        }

        void Fail(string text)
        {
            Log(L.F("adk.log_failed", text));
            lblProgress.Text = L.T("adk.state_failed");
            SetBusy(false);
            RefreshStatus();
            Ui.Info(text, MessageBoxIcon.Error);
        }

        void Cancel()
        {
            lblProgress.Text = L.T("adk.state_cancelled");
            SetBusy(false);
            RefreshStatus();
        }

        static bool SameVersion(string a, string b)
        {
            Version va, vb;
            if (Version.TryParse(Norm(a), out va) && Version.TryParse(Norm(b), out vb))
                return va.Major == vb.Major && va.Minor == vb.Minor && va.Build == vb.Build;
            return string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
        }

        // "5.3.0" / "5.3.0.10" -> parsable, "v5.3.0" -> "5.3.0"
        static string Norm(string v)
        {
            Match m = Regex.Match(v ?? "", @"\d+(\.\d+){1,3}");
            return m.Success ? m.Value : "";
        }

        // Newest stable version of the release list (no rc / beta, no lt12)
        string NewestVersion()
        {
            string xml = Fetch(Value("download", "list"), Value("download", "hosts"));
            Version best = null;
            string bestText = null;
            // folder links of the file list ("qbittorrent-win32/qbittorrent-5.3.0/") or
            // file paths of the RSS list; "5.3.0rc1/" and "5.3.0beta1/" do not match
            foreach (Match m in Regex.Matches(xml, @"qbittorrent-win32/qbittorrent-(\d+\.\d+\.\d+(?:\.\d+)?)/", RegexOptions.IgnoreCase))
            {
                Version v;
                if (!Version.TryParse(m.Groups[1].Value, out v)) continue;
                if (best == null || v > best) { best = v; bestText = m.Groups[1].Value; }
            }
            if (bestText == null) throw new InvalidOperationException(L.T("qbt.no_version"));
            return bestText;
        }

        // https and one of the hosts (sub-domains included)
        static bool HostAllowed(Uri u, string hosts)
        {
            if (u.Scheme != "https") return false;
            foreach (string h in hosts.Split(new[] { ' ', ',' }, StringSplitOptions.RemoveEmptyEntries))
                if (string.Equals(u.Host, h, StringComparison.OrdinalIgnoreCase) ||
                    u.Host.EndsWith("." + h, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        static HttpWebRequest NewRequest(string url, string hosts)
        {
            Uri u = new Uri(url);
            if (!HostAllowed(u, hosts)) throw new InvalidOperationException(L.F("tools.bad_host", url));
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(u);
            req.UserAgent = "DVT-GUI";
            req.Proxy = WebRequest.DefaultWebProxy;
            if (req.Proxy != null) req.Proxy.Credentials = CredentialCache.DefaultCredentials;
            return req;
        }

        static string Fetch(string url, string hosts)
        {
            HttpWebRequest req = NewRequest(url, hosts);
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            {
                if (!HostAllowed(resp.ResponseUri, hosts)) throw new InvalidOperationException(L.F("tools.bad_host", resp.ResponseUri.ToString()));
                using (StreamReader r = new StreamReader(resp.GetResponseStream()))
                    return r.ReadToEnd();
            }
        }

        // step 2 (background): download the setup, unpack it into a
        // temporary folder with 7-Zip and copy only the program files
        void Install(Job j)
        {
            string url = string.Format(Value("download", "url"), j.Version);
            j.Setup = Path.Combine(downloadDir, "qbittorrent_" + j.Version + "_x64_setup.exe");
            string target = InstallDir;
            string[] patterns = Value("install", "files").Split(new[] { ' ', ',' }, StringSplitOptions.RemoveEmptyEntries);
            string[] folders = Value("install", "folders").Split(new[] { ' ', ',' }, StringSplitOptions.RemoveEmptyEntries);
            worker = new BackgroundWorker();
            worker.WorkerReportsProgress = true;
            worker.DoWork += delegate(object s, DoWorkEventArgs e)
            {
                e.Result = j;
                string temp = Path.Combine(Path.GetTempPath(), "DVT_qbittorrent_" + DateTime.Now.ToString("yyyyMMddHHmmss"));
                try
                {
                    Directory.CreateDirectory(downloadDir);
                    // the setup of the same version from an earlier download is used
                    // again when its SHA256 matches the one recorded after that download
                    if (CachedSetupOk(j.Setup))
                        worker.ReportProgress(-1, L.F("qbt.log_reuse", Path.GetFileName(j.Setup)));
                    else
                    {
                        worker.ReportProgress(-1, L.F("adk.log_download", url));
                        Download(url, j.Setup, Value("download", "hosts"), true);
                        File.WriteAllText(j.Setup + ".sha256", AdkCore.Sha256(j.Setup) + "  " + Path.GetFileName(j.Setup) + "\r\n", Encoding.ASCII);
                    }

                    string sevenZip = Find7Zip();
                    worker.ReportProgress(-1, L.F("qbt.log_7zip", sevenZip));

                    worker.ReportProgress(-1, L.F("qbt.log_unpack", Path.GetFileName(j.Setup), temp));
                    worker.ReportProgress(0, L.T("qbt.state_unpacking"));
                    Directory.CreateDirectory(temp);
                    RunTool(sevenZip, "x \"" + j.Setup + "\" -o\"" + temp + "\" -y");

                    string src = FindFolderWith(temp, "qbittorrent.exe");
                    if (src == null) throw new InvalidOperationException(L.F("qbt.no_exe", Path.GetFileName(j.Setup)));
                    Directory.CreateDirectory(target);
                    foreach (string pat in patterns)
                        foreach (string f in Directory.GetFiles(src, pat))
                        {
                            File.Copy(f, Path.Combine(target, Path.GetFileName(f)), true);
                            j.Copied++;
                            worker.ReportProgress(-1, L.F("tools.log_copied", Path.GetFileName(f)));
                        }
                    foreach (string d in folders)
                    {
                        string sd = Path.Combine(src, d);
                        if (!Directory.Exists(sd)) continue;
                        j.Copied += CopyTree(sd, Path.Combine(target, d));
                        worker.ReportProgress(-1, L.F("tools.log_copied", d + "\\"));
                    }
                }
                catch (Exception ex) { j.Error = ex.Message; }
                finally
                {
                    try { if (Directory.Exists(temp)) Directory.Delete(temp, true); } catch (Exception) { }
                }
            };
            worker.ProgressChanged += OnProgress;
            worker.RunWorkerCompleted += delegate
            {
                worker = null;
                if (j.Error != null) { Fail(L.F("qbt.install_failed", j.Error)); return; }
                if (!File.Exists(ExePath)) { Fail(L.F("qbt.no_exe", Path.GetFileName(j.Setup))); return; }
                // portable mode: a "profile" folder next to qbittorrent.exe
                try { Directory.CreateDirectory(ProfileDir); }
                catch (Exception ex) { Fail(ex.Message); return; }
                Log(L.F("qbt.log_installed", InstalledVersion(), Ui.ShortPath(InstallDir)));
                SetBusy(false);
                lblProgress.Text = L.T("qbt.state_done");
                RefreshStatus();
                if (!File.Exists(IniPath)) ApplySettings(false);
                else Ui.Info(L.T("qbt.done_kept"));
                // inbound firewall rules for the new qbittorrent.exe and the ports of qBittorrent.ini
                Log(L.T("qbt.fw_auto"));
                AddFirewallRules(false);
            };
            worker.RunWorkerAsync();
        }

        // true when <setup> and <setup>.sha256 (written after the download)
        // exist and the SHA256 of the file still matches
        static bool CachedSetupOk(string setup)
        {
            try
            {
                string side = setup + ".sha256";
                if (!File.Exists(setup) || !File.Exists(side)) return false;
                string want = File.ReadAllText(side).Trim().Split(' ')[0];
                return want.Length == 64 && string.Equals(AdkCore.Sha256(setup), want, StringComparison.OrdinalIgnoreCase);
            }
            catch (Exception) { return false; }
        }

        void Download(string url, string dest, string hosts, bool report)
        {
            string part = dest + ".part";
            HttpWebRequest req = NewRequest(url, hosts);
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            {
                if (!HostAllowed(resp.ResponseUri, hosts)) throw new InvalidOperationException(L.F("tools.bad_host", resp.ResponseUri.ToString()));
                long total = resp.ContentLength;
                using (Stream src = resp.GetResponseStream())
                using (FileStream fs = new FileStream(part, FileMode.Create, FileAccess.Write))
                {
                    byte[] buf = new byte[81920];
                    long done = 0;
                    int n;
                    while ((n = src.Read(buf, 0, buf.Length)) > 0)
                    {
                        fs.Write(buf, 0, n);
                        done += n;
                        if (!report) continue;
                        int pct = total > 0 ? (int)(done * 100 / total) : 0;
                        worker.ReportProgress(pct, L.F("adk.progress_download", Path.GetFileName(dest), done / 1024, total > 0 ? total / 1024 : 0));
                    }
                }
            }
            // a mirror page instead of the program?
            using (FileStream fs = File.OpenRead(part))
            {
                if (fs.Length < 64 * 1024 || fs.ReadByte() != 'M' || fs.ReadByte() != 'Z')
                {
                    fs.Close();
                    File.Delete(part);
                    throw new InvalidOperationException(L.F("qbt.not_program", Path.GetFileName(dest)));
                }
            }
            if (File.Exists(dest)) File.Delete(dest);
            File.Move(part, dest);
        }

        // 7z.exe of an installed 7-Zip, else 7-Zip from 7-zip.org (GitHub):
        // 7zr.exe unpacks 7z.exe and 7z.dll from the 7-Zip setup into
        // _output\qbt_download\7zip (nothing is installed)
        string Find7Zip()
        {
            foreach (RegistryView view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
            {
                try
                {
                    using (RegistryKey hk = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view))
                    using (RegistryKey k = hk.OpenSubKey(@"SOFTWARE\7-Zip"))
                    {
                        if (k == null) continue;
                        foreach (string name in new[] { "Path64", "Path" })
                        {
                            string dir = k.GetValue(name) as string;
                            if (!string.IsNullOrEmpty(dir) && File.Exists(Path.Combine(dir, "7z.exe"))) return Path.Combine(dir, "7z.exe");
                        }
                    }
                }
                catch (Exception) { }
            }
            foreach (string pf in new[] { Environment.GetEnvironmentVariable("ProgramW6432"), Environment.GetEnvironmentVariable("ProgramFiles"), Environment.GetEnvironmentVariable("ProgramFiles(x86)") })
            {
                if (string.IsNullOrEmpty(pf)) continue;
                string f = Path.Combine(Path.Combine(pf, "7-Zip"), "7z.exe");
                if (File.Exists(f)) return f;
            }

            string dir7 = Path.Combine(downloadDir, "7zip");
            string exe = Path.Combine(dir7, "7z.exe");
            if (File.Exists(exe) && File.Exists(Path.Combine(dir7, "7z.dll"))) return exe;
            Directory.CreateDirectory(dir7);
            string hosts = Value("7zip", "hosts");
            string sevenZr = Path.Combine(dir7, "7zr.exe");
            string setup = Path.Combine(dir7, "7zip_setup.exe");
            worker.ReportProgress(-1, L.F("adk.log_download", Value("7zip", "7zr")));
            Download(Value("7zip", "7zr"), sevenZr, hosts, false);
            worker.ReportProgress(-1, L.F("adk.log_download", Value("7zip", "setup")));
            Download(Value("7zip", "setup"), setup, hosts, false);
            RunTool(sevenZr, "x \"" + setup + "\" -o\"" + dir7 + "\" 7z.exe 7z.dll -y");
            if (!File.Exists(exe)) throw new InvalidOperationException(L.T("qbt.no_7zip"));
            return exe;
        }

        // runs a console tool without a window; exit code 0 or 1 (warnings) is OK
        static void RunTool(string exe, string args)
        {
            ProcessStartInfo psi = new ProcessStartInfo(exe, args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            using (Process p = Process.Start(psi))
            {
                p.StandardOutput.ReadToEnd();
                p.WaitForExit();
                if (p.ExitCode > 1)
                    throw new InvalidOperationException(L.F("qbt.tool_failed", Path.GetFileName(exe), p.ExitCode));
            }
        }

        static string FindFolderWith(string root, string file)
        {
            if (File.Exists(Path.Combine(root, file))) return root;
            foreach (string f in Directory.GetFiles(root, file, SearchOption.AllDirectories))
                if (f.IndexOf('$') < 0) return Path.GetDirectoryName(f);
            return null;
        }

        static int CopyTree(string from, string to)
        {
            int n = 0;
            Directory.CreateDirectory(to);
            foreach (string f in Directory.GetFiles(from)) { File.Copy(f, Path.Combine(to, Path.GetFileName(f)), true); n++; }
            foreach (string d in Directory.GetDirectories(from)) n += CopyTree(d, Path.Combine(to, Path.GetFileName(d)));
            return n;
        }
    }
}
