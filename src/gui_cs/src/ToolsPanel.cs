// ============================================================
//  DVT GUI - ToolsPanel.cs
//  Tab "WinPE tools" of the page "Prerequisites": downloads the
//  third-party tools the WinPE images need and copies them to the
//  folders of data\host\config.cmd:
//    aria2   -> PE_TOOLS_DIR : aria2c.exe
//    wimlib  -> PE_TOOLS_DIR : wimlib-imagex.exe, libwim-15.dll
//    NirCmd  -> PE_TOOLS_DIR : every file of the zip (NIRCMD_SRC points there)
//  The download URLs and SHA256 hashes come from tools.ini. A zip
//  whose hash differs is refused (or, for on_mismatch = ask, used only
//  after the user agrees). Files that are replaced are copied to
//  _output\tools_backup\<time>\ first.
// ============================================================
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Windows.Forms;

namespace Dvt
{
    public class ToolInfo
    {
        public string Key = "", Name = "", Version = "", Url = "", Sha256 = "", OnMismatch = "refuse",
                      Target = "", Home = "", License = "";
        public string[] Hosts = new string[0];
        public string[] Files = new string[0];     // "*" = every file of the zip
        public string[] Check = new string[0];     // files that must exist to count as installed
    }

    public class ToolsPanel : UserControl
    {
        readonly Func<Dictionary<string, string>> getPaths;
        readonly string downloadDir, backupRoot, rootDir;
        readonly List<ToolInfo> tools = new List<ToolInfo>();
        readonly List<Label> statusLabels = new List<Label>();
        readonly List<Button> toolButtons = new List<Button>();
        readonly Button btnAll, btnOpenTools;
        readonly ProgressBar progress;
        readonly Label lblProgress;
        readonly TextBox log;
        BackgroundWorker worker;

        public ToolsPanel(Func<Dictionary<string, string>> getPaths, string root)
        {
            this.getPaths = getPaths;
            rootDir = root;
            downloadDir = Path.Combine(Path.Combine(root, "_output"), "tools_download");
            backupRoot = Path.Combine(Path.Combine(root, "_output"), "tools_backup");
            Dock = DockStyle.Fill;
            LoadTools();

            int toolRows = Math.Max(1, tools.Count);
            TableLayoutPanel lay = Ui.NewRows(26, 34 + 40 * toolRows, 40, 28, 0, 64);
            lay.Controls.Add(Ui.NewHint(L.T("tools.subtitle")), 0, 0);

            // -- one row per tool: name / status / buttons --
            TableLayoutPanel tbl = new TableLayoutPanel();
            tbl.Dock = DockStyle.Fill;
            tbl.ColumnCount = 3;
            tbl.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Ui.S(200)));
            tbl.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            tbl.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Ui.S(230)));
            tbl.RowCount = tools.Count + 1;
            tbl.RowStyles.Add(new RowStyle(SizeType.Absolute, Ui.S(30)));
            tbl.Controls.Add(Ui.NewBoldLabel(L.T("tools.col_tool")), 0, 0);
            tbl.Controls.Add(Ui.NewBoldLabel(L.T("tools.col_status")), 1, 0);
            for (int n = 0; n < tools.Count; n++)
            {
                ToolInfo t = tools[n];
                tbl.RowStyles.Add(new RowStyle(SizeType.Absolute, Ui.S(40)));
                Label name = Ui.NewLabel(t.Name + "  " + t.Version);
                name.Font = Ui.FontBold;
                tbl.Controls.Add(name, 0, n + 1);
                Label st = Ui.NewLabel("");
                statusLabels.Add(st);
                tbl.Controls.Add(st, 1, n + 1);
                FlowLayoutPanel f = Ui.NewFlow();
                Button b = Ui.NewButton(L.T("tools.btn_download"), 120);
                b.Tag = n;
                b.Click += delegate(object s, EventArgs e) { Start(new List<ToolInfo> { tools[(int)((Control)s).Tag] }); };
                Button h = Ui.NewButton(L.T("tools.btn_home"), 90);
                h.Tag = n;
                h.Click += delegate(object s, EventArgs e)
                {
                    string url = tools[(int)((Control)s).Tag].Home;
                    if (url.StartsWith("https://")) Process.Start(url);
                };
                toolButtons.Add(b);
                f.Controls.Add(b);
                f.Controls.Add(h);
                tbl.Controls.Add(f, 2, n + 1);
            }
            lay.Controls.Add(tbl, 0, 1);

            // -- actions --
            FlowLayoutPanel fl = Ui.NewFlow();
            btnAll = Ui.NewButton(L.T("tools.btn_all"), 200);
            Ui.Primary(btnAll, Palette.Adk);
            btnOpenTools = Ui.NewButton(L.T("tools.btn_open_tools"), 170);
            Button btnRefresh = Ui.NewButton(L.T("adk.btn_refresh"), 90);
            fl.Controls.AddRange(new Control[] { btnAll, btnOpenTools, btnRefresh });
            lay.Controls.Add(fl, 0, 2);

            FlowLayoutPanel fp = Ui.NewFlow();
            progress = new ProgressBar();
            progress.Width = Ui.S(320);
            progress.Height = Ui.S(18);
            progress.Margin = new Padding(0, Ui.S(5), Ui.S(10), 0);
            lblProgress = Ui.NewFlowLabel("");
            lblProgress.Margin = new Padding(0, Ui.S(6), 0, 0);
            fp.Controls.Add(progress);
            fp.Controls.Add(lblProgress);
            lay.Controls.Add(fp, 0, 3);

            log = new TextBox();
            log.Dock = DockStyle.Fill;
            log.Multiline = true;
            log.ReadOnly = true;
            log.ScrollBars = ScrollBars.Vertical;
            log.Font = Ui.FontMono;
            log.BackColor = SystemColors.Window;
            lay.Controls.Add(log, 0, 4);

            Label note = Ui.NewHint(L.T("tools.note"));
            note.TextAlign = ContentAlignment.TopLeft;
            lay.Controls.Add(note, 0, 5);
            Controls.Add(lay);

            btnAll.Click += delegate
            {
                List<ToolInfo> missing = new List<ToolInfo>();
                foreach (ToolInfo t in tools) if (MissingFiles(t).Count > 0) missing.Add(t);
                if (missing.Count == 0)
                {
                    if (!Ui.YesNo(L.T("tools.all_present"), MessageBoxIcon.Question)) return;
                    missing.AddRange(tools);
                }
                Start(missing);
            };
            btnOpenTools.Click += delegate { Ui.OpenFolder(TargetDir("PE_TOOLS_DIR")); };
            btnRefresh.Click += delegate { RefreshStatus(); };

            RefreshStatus();
        }

        public bool Busy { get { return worker != null && worker.IsBusy; } }

        void LoadTools()
        {
            Dictionary<string, List<KeyValuePair<string, string>>> d = L.ReadData("tools.ini");
            if (d == null) return;
            foreach (KeyValuePair<string, List<KeyValuePair<string, string>>> sec in d)
            {
                ToolInfo t = new ToolInfo();
                t.Key = sec.Key;
                t.Name = L.Value(d, sec.Key, "name");
                t.Version = L.Value(d, sec.Key, "version");
                t.Url = L.Value(d, sec.Key, "url");
                t.Sha256 = L.Value(d, sec.Key, "sha256").Trim().ToUpperInvariant();
                t.OnMismatch = L.Value(d, sec.Key, "on_mismatch").Trim().ToLowerInvariant();
                t.Target = L.Value(d, sec.Key, "target").Trim().ToUpperInvariant();
                t.Home = L.Value(d, sec.Key, "home");
                t.License = L.Value(d, sec.Key, "license");
                t.Hosts = L.Value(d, sec.Key, "hosts").Split(new[] { ' ', ',' }, StringSplitOptions.RemoveEmptyEntries);
                t.Files = L.Value(d, sec.Key, "files").Split(new[] { ' ', ',' }, StringSplitOptions.RemoveEmptyEntries);
                t.Check = L.Value(d, sec.Key, "check").Split(new[] { ' ', ',' }, StringSplitOptions.RemoveEmptyEntries);
                if (t.Check.Length == 0)
                {
                    List<string> named = new List<string>();
                    foreach (string f in t.Files) if (f != "*") named.Add(f);
                    t.Check = named.ToArray();
                }
                if (t.Url.Length == 0 || t.Files.Length == 0 || t.Check.Length == 0) continue;
                if (t.Name.Length == 0) t.Name = t.Key;
                tools.Add(t);
            }
        }

        // PE_TOOLS_DIR, or the folder of NIRCMD_SRC (data\host\config.cmd)
        string TargetDir(string target)
        {
            Dictionary<string, string> p = getPaths();
            if (target == "NIRCMD") return p["NircmdDir"];
            return p["PeTools"];
        }

        List<string> MissingFiles(ToolInfo t)
        {
            List<string> m = new List<string>();
            string dir = TargetDir(t.Target);
            foreach (string f in t.Check) if (!File.Exists(Path.Combine(dir, f))) m.Add(f);
            return m;
        }

        public void RefreshStatus()
        {
            for (int n = 0; n < tools.Count; n++)
            {
                ToolInfo t = tools[n];
                string dir = TargetDir(t.Target);
                List<string> missing = MissingFiles(t);
                Label l = statusLabels[n];
                if (missing.Count == 0)
                {
                    string first = Path.Combine(dir, t.Check[0]);
                    string ver = AdkCore.FileVersion(first);
                    l.Text = "\u2714 " + L.F("tools.found", Short(dir), ver.Length > 0 ? ver : File.GetLastWriteTime(first).ToString("yyyy-MM-dd"));
                    l.ForeColor = Color.FromArgb(16, 124, 16);
                }
                else
                {
                    l.Text = "\u2716 " + L.F("tools.missing", string.Join(", ", missing.ToArray()), Short(dir));
                    l.ForeColor = Ui.ColorDanger;
                }
            }
        }

        // a folder inside the DVT folder is shown relative to it
        string Short(string dir)
        {
            string r = rootDir.TrimEnd('\\') + "\\";
            return dir.StartsWith(r, StringComparison.OrdinalIgnoreCase) ? dir.Substring(r.Length) : dir;
        }

        void Log(string text)
        {
            log.AppendText(DateTime.Now.ToString("HH:mm:ss") + "  " + text + "\r\n");
        }

        void SetBusy(bool busy)
        {
            btnAll.Enabled = !busy;
            foreach (Button b in toolButtons) b.Enabled = !busy;
            if (!busy) progress.Value = 0;
        }

        // ---------- download, check, extract (background) ----------

        void Start(List<ToolInfo> list)
        {
            if (Busy || list.Count == 0) return;
            List<string> names = new List<string>();
            foreach (ToolInfo t in list) names.Add(t.Name + " " + t.Version + "  ->  " + TargetDir(t.Target));
            if (!Ui.YesNo(L.F("tools.confirm", string.Join("\r\n", names.ToArray())), MessageBoxIcon.Question)) return;

            // folders are resolved here, on the UI thread
            Dictionary<ToolInfo, string> targets = new Dictionary<ToolInfo, string>();
            foreach (ToolInfo t in list) targets[t] = TargetDir(t.Target);
            string backupDir = Path.Combine(backupRoot, DateTime.Now.ToString("yyyyMMdd-HHmmss"));

            log.Clear();
            SetBusy(true);
            worker = new BackgroundWorker();
            worker.WorkerReportsProgress = true;
            worker.DoWork += delegate(object s, DoWorkEventArgs e)
            {
                int ok = 0, failed = 0;
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                Directory.CreateDirectory(downloadDir);
                for (int n = 0; n < list.Count; n++)
                {
                    ToolInfo t = list[n];
                    try
                    {
                        string zip = Path.Combine(downloadDir, t.Key + "-" + t.Version + ".zip");
                        worker.ReportProgress(-1, L.F("tools.log_download", t.Name, t.Url));
                        Download(t, zip, n, list.Count);
                        string hash = AdkCore.Sha256(zip);
                        if (!string.Equals(hash, t.Sha256, StringComparison.OrdinalIgnoreCase))
                        {
                            worker.ReportProgress(-1, L.F("tools.log_hash_mismatch", t.Name, hash, t.Sha256));
                            bool use = false;
                            if (t.OnMismatch == "ask")
                            {
                                Invoke((MethodInvoker)delegate
                                {
                                    use = Ui.YesNo(L.F("tools.ask_hash", t.Name, hash, t.Sha256), MessageBoxIcon.Warning);
                                });
                            }
                            if (!use)
                            {
                                File.Delete(zip);
                                failed++;
                                worker.ReportProgress(-1, L.F("tools.log_refused", t.Name));
                                continue;
                            }
                        }
                        else worker.ReportProgress(-1, L.F("tools.log_hash_ok", t.Name, hash));
                        foreach (string f in Extract(zip, t.Files, targets[t], backupDir))
                            worker.ReportProgress(-1, L.F("tools.log_copied", f));
                        ok++;
                    }
                    catch (Exception ex)
                    {
                        failed++;
                        worker.ReportProgress(-1, L.F("tools.log_failed", t.Name, ex.Message));
                    }
                }
                e.Result = new[] { ok, failed };
            };
            worker.ProgressChanged += delegate(object s, ProgressChangedEventArgs e)
            {
                string text = e.UserState as string;
                if (e.ProgressPercentage < 0) { if (text != null) Log(text); return; }
                progress.Value = Math.Min(100, e.ProgressPercentage);
                if (text != null) lblProgress.Text = text;
            };
            worker.RunWorkerCompleted += delegate(object s, RunWorkerCompletedEventArgs e)
            {
                int[] r = e.Error == null ? e.Result as int[] : null;
                worker = null;
                SetBusy(false);
                RefreshStatus();
                if (r == null) { Log(e.Error == null ? "?" : e.Error.Message); lblProgress.Text = L.T("adk.state_failed"); return; }
                lblProgress.Text = L.F("tools.done", r[0], r[1]);
                Ui.Status(lblProgress.Text);
                if (r[1] > 0) Ui.Info(L.F("tools.some_failed", r[1]), MessageBoxIcon.Warning);
            };
            worker.RunWorkerAsync();
        }

        void Download(ToolInfo t, string dest, int index, int count)
        {
            if (!t.Url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException(L.F("tools.bad_host", t.Url));
            string part = dest + ".part";
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(t.Url);
            req.UserAgent = "DVT-GUI";
            req.Proxy = WebRequest.DefaultWebProxy;
            if (req.Proxy != null) req.Proxy.Credentials = CredentialCache.DefaultCredentials;
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            {
                Uri final = resp.ResponseUri;
                bool hostOk = false;
                foreach (string h in t.Hosts)
                    if (string.Equals(final.Host, h, StringComparison.OrdinalIgnoreCase)) hostOk = true;
                if (!hostOk || final.Scheme != "https")
                    throw new InvalidOperationException(L.F("tools.bad_host", final.ToString()));
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
                        int pct = total > 0 ? (int)(done * 100 / total) : 0;
                        worker.ReportProgress((index * 100 + pct) / count,
                            L.F("adk.progress_download", t.Name, done / 1024, total > 0 ? total / 1024 : 0));
                    }
                }
            }
            if (File.Exists(dest)) File.Delete(dest);
            File.Move(part, dest);
        }

        // Copies the named files (found anywhere in the zip) to the target
        // folder; "*" copies every file of the zip (without its folders).
        // An existing file is copied to the backup folder first.
        public static List<string> Extract(string zipPath, string[] files, string targetDir, string backupDir)
        {
            List<string> done = new List<string>();
            Directory.CreateDirectory(targetDir);
            using (FileStream fs = File.OpenRead(zipPath))
            using (ZipArchive zip = new ZipArchive(fs, ZipArchiveMode.Read))
            {
                // the entries to copy, with the file name they get
                List<KeyValuePair<ZipArchiveEntry, string>> todo = new List<KeyValuePair<ZipArchiveEntry, string>>();
                foreach (string name in files)
                {
                    bool all = name == "*";
                    ZipArchiveEntry found = null;
                    foreach (ZipArchiveEntry e in zip.Entries)
                    {
                        string entryName = e.FullName.Replace('\\', '/');
                        int slash = entryName.LastIndexOf('/');
                        if (slash >= 0) entryName = entryName.Substring(slash + 1);
                        if (entryName.Length == 0) continue;            // a folder
                        if (all) { AddOnce(todo, e, entryName); found = e; }
                        else if (string.Equals(entryName, name, StringComparison.OrdinalIgnoreCase)) { found = e; AddOnce(todo, e, name); break; }
                    }
                    if (found == null) throw new InvalidOperationException(L.F("tools.not_in_zip", name));
                }
                foreach (KeyValuePair<ZipArchiveEntry, string> item in todo)
                {
                    ZipArchiveEntry found = item.Key;
                    string name = item.Value;
                    string dest = Path.Combine(targetDir, name);
                    if (File.Exists(dest))
                    {
                        Directory.CreateDirectory(backupDir);
                        File.Copy(dest, Path.Combine(backupDir, name), true);
                    }
                    string tmp = dest + ".new";
                    using (Stream src = found.Open())
                    using (FileStream o = new FileStream(tmp, FileMode.Create, FileAccess.Write))
                        src.CopyTo(o);
                    if (File.Exists(dest)) File.Delete(dest);
                    File.Move(tmp, dest);
                    done.Add(dest);
                }
            }
            return done;
        }

        static void AddOnce(List<KeyValuePair<ZipArchiveEntry, string>> todo, ZipArchiveEntry e, string name)
        {
            foreach (KeyValuePair<ZipArchiveEntry, string> t in todo)
                if (string.Equals(t.Value, name, StringComparison.OrdinalIgnoreCase)) return;
            todo.Add(new KeyValuePair<ZipArchiveEntry, string>(e, name));
        }
    }
}
