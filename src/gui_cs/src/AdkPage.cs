// ============================================================
//  DVT GUI - AdkPage.cs
//  Page "Windows ADK": shows whether the Windows ADK (Deployment
//  Tools) and the Windows PE add-on are installed, and installs them:
//   - Version to install: the releases of adk.ini ([release ...]).
//   - Download and install: adksetup.exe and adkwinpesetup.exe of the
//     selected release are downloaded from Microsoft (links of adk.ini),
//     checked (Microsoft signature + SHA256 of the selected release)
//     and run silently by the
//     elevated helper (AdkCore.RunHelper) with only the features DVT
//     needs. The setups download their packages from Microsoft.
//   - Create offline package: the same setups with /layout, for a
//     build PC without internet.
//   - Install from offline package: a folder made that way.
//  Download method based on p0w3rsh3ll/ADK (MIT License).
// ============================================================
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Windows.Forms;

namespace Dvt
{
    public class AdkPage : UserControl
    {
        readonly Func<Dictionary<string, string>> getPaths;
        readonly string workDir;
        Dictionary<string, List<KeyValuePair<string, string>>> data;

        readonly Label[] statusLabels = new Label[5];
        readonly Button btnInstall, btnOffline, btnFromFolder, btnPage, btnRefresh, btnLogs;
        readonly CheckBox chkUninstall;
        readonly ComboBox cboRelease;
        readonly List<Release> releases = new List<Release>();
        string installedAdkVersion;
        readonly ProgressBar progress;
        readonly Label lblProgress;
        readonly TextBox log;
        readonly Timer timer;

        BackgroundWorker worker;
        Process helper;
        string helperStatusFile;
        int helperLinesShown;
        DateTime helperStarted;
        string pendingMode;            // "install" or "layout"
        string pendingLayoutDir;
        Release pendingRelease;

        public AdkPage(Func<Dictionary<string, string>> getPaths, string root)
        {
            this.getPaths = getPaths;
            workDir = Path.Combine(Path.Combine(root, "_output"), "adk_setup");
            data = L.ReadData("adk.ini");
            Dock = DockStyle.Fill;

            // the page banner is drawn by MainForm (page "Prerequisites")
            TableLayoutPanel lay = Ui.NewRows(26, 30, 150, 38, 26, 40, 30, 28, 0, 44);
            lay.Controls.Add(Ui.NewHint(L.T("adk.subtitle")), 0, 0);
            lay.Controls.Add(Ui.NewBoldLabel(L.T("adk.status_title")), 0, 1);

            // -- status --
            TableLayoutPanel st = new TableLayoutPanel();
            st.Dock = DockStyle.Fill;
            st.ColumnCount = 2;
            st.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Ui.S(230)));
            st.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            st.RowCount = 5;
            string[] names = { L.T("adk.row_adk"), L.T("adk.row_pe"), L.T("adk.row_pedir"), L.T("adk.row_source"), L.T("adk.row_latest") };
            for (int n = 0; n < 5; n++)
            {
                st.RowStyles.Add(new RowStyle(SizeType.Absolute, Ui.S(28)));
                st.Controls.Add(Ui.NewLabel(names[n]), 0, n);
                statusLabels[n] = Ui.NewLabel("");
                statusLabels[n].Font = Ui.FontBold;
                st.Controls.Add(statusLabels[n], 1, n);
            }
            lay.Controls.Add(st, 0, 2);

            // -- version to install --
            LoadReleases();
            FlowLayoutPanel fr = Ui.NewFlow();
            Label lblRelease = Ui.NewFlowLabel(L.T("adk.row_select"));
            lblRelease.Font = Ui.FontBold;
            lblRelease.Margin = new Padding(0, Ui.S(8), Ui.S(10), 0);
            cboRelease = new ComboBox();
            cboRelease.DropDownStyle = ComboBoxStyle.DropDownList;
            cboRelease.Width = Ui.S(520);
            cboRelease.Margin = new Padding(0, Ui.S(4), 0, 0);
            fr.Controls.Add(lblRelease);
            fr.Controls.Add(cboRelease);
            lay.Controls.Add(fr, 0, 3);
            lay.Controls.Add(Ui.NewHint(L.T("adk.select_hint")), 0, 4);

            // -- actions --
            FlowLayoutPanel fl = Ui.NewFlow();
            btnInstall = Ui.NewButton(L.T("adk.btn_install"), 170);
            Ui.Primary(btnInstall, Palette.Adk);
            btnOffline = Ui.NewButton(L.T("adk.btn_offline"), 175);
            btnFromFolder = Ui.NewButton(L.T("adk.btn_from_folder"), 185);
            btnPage = Ui.NewButton(L.T("adk.btn_page"), 145);
            btnRefresh = Ui.NewButton(L.T("adk.btn_refresh"), 90);
            fl.Controls.AddRange(new Control[] { btnInstall, btnOffline, btnFromFolder, btnPage, btnRefresh });
            lay.Controls.Add(fl, 0, 5);

            FlowLayoutPanel fo = Ui.NewFlow();
            chkUninstall = new CheckBox();
            chkUninstall.Text = L.T("adk.chk_uninstall");
            chkUninstall.AutoSize = true;
            chkUninstall.Margin = new Padding(0, Ui.S(6), Ui.S(16), 0);
            btnLogs = Ui.NewButton(L.T("adk.btn_logs"), 140);
            fo.Controls.Add(chkUninstall);
            fo.Controls.Add(btnLogs);
            lay.Controls.Add(fo, 0, 6);

            FlowLayoutPanel fp = Ui.NewFlow();
            progress = new ProgressBar();
            progress.Width = Ui.S(320);
            progress.Height = Ui.S(18);
            progress.Margin = new Padding(0, Ui.S(5), Ui.S(10), 0);
            lblProgress = Ui.NewFlowLabel("");
            lblProgress.Margin = new Padding(0, Ui.S(6), 0, 0);
            fp.Controls.Add(progress);
            fp.Controls.Add(lblProgress);
            lay.Controls.Add(fp, 0, 7);

            log = new TextBox();
            log.Dock = DockStyle.Fill;
            log.Multiline = true;
            log.ReadOnly = true;
            log.ScrollBars = ScrollBars.Vertical;
            log.Font = Ui.FontMono;
            log.BackColor = SystemColors.Window;
            lay.Controls.Add(log, 0, 8);

            Label note = Ui.NewHint(L.T("adk.note"));
            note.TextAlign = ContentAlignment.TopLeft;
            lay.Controls.Add(note, 0, 9);

            Controls.Add(lay);

            btnInstall.Click += delegate { StartDownload("install", null); };
            btnOffline.Click += delegate { CreateOffline(); };
            btnFromFolder.Click += delegate { InstallFromFolder(); };
            btnPage.Click += delegate
            {
                string url = L.Value(data, "download", "info_page");
                if (url.StartsWith("https://")) Process.Start(url);
            };
            btnRefresh.Click += delegate { RefreshStatus(); };
            btnLogs.Click += delegate { Ui.OpenFolder(workDir); };
            cboRelease.SelectedIndexChanged += delegate { UpdateUninstallDefault(); };

            timer = new Timer();
            timer.Interval = 1000;
            timer.Tick += delegate { PollHelper(); };

            RefreshStatus();
        }

        public bool Busy
        {
            get { return (worker != null && worker.IsBusy) || helper != null; }
        }

        void SetBusy(bool busy)
        {
            foreach (Control c in new Control[] { btnInstall, btnOffline, btnFromFolder, btnRefresh, chkUninstall, cboRelease })
                c.Enabled = !busy;
            if (!busy)
            {
                progress.Style = ProgressBarStyle.Blocks;
                progress.Value = 0;
            }
        }

        void Log(string text)
        {
            log.AppendText(DateTime.Now.ToString("HH:mm:ss") + "  " + text + "\r\n");
        }

        // ---------- status ----------

        public void RefreshStatus()
        {
            AdkState s = AdkCore.Detect();
            Dictionary<string, string> p = getPaths();

            SetLine(0, s.Adk != null && s.DeploymentTools,
                s.Adk != null ? L.F("adk.installed", s.Adk.Version) + (s.DeploymentTools ? "" : "  " + L.T("adk.no_deploy_tools")) : L.T("adk.not_installed"));
            SetLine(1, s.Pe != null && s.WinPeWim,
                s.Pe != null ? L.F("adk.installed", s.Pe.Version) + (s.WinPeWim ? "" : "  " + L.T("adk.no_winpe_wim")) : L.T("adk.not_installed"));

            string cfgPe = p["AdkPe"];
            bool cfgOk = File.Exists(Path.Combine(cfgPe, @"en-us\winpe.wim"));
            SetLine(2, cfgOk, cfgOk ? cfgPe : L.F("adk.pedir_missing", cfgPe));

            string src = p["Source"];
            List<string> missing = new List<string>();
            foreach (string f in new[] { "winpe.wim", "boot.sdi", @"adk_media\bootmgr", @"adk_tools\oscdimg.exe", @"adk_tools\etfsboot.com", @"adk_tools\efisys.bin" })
                if (!File.Exists(Path.Combine(src, f))) missing.Add(f);
            if (missing.Count == 0) SetLine(3, true, L.T("adk.source_complete"));
            else if (missing.Count == 6) SetLine(3, false, L.T("adk.source_none"));
            else SetLine(3, false, L.F("adk.source_partial", string.Join(", ", missing.ToArray())));

            string latest = LatestKnown();
            string latestName = "";
            if (latest.Length > 0)
            {
                latestName = L.Value(data, "release " + latest, "name");
                if (latestName.Length == 0) latestName = L.Value(data, "known " + latest, "name");
            }
            bool upToDate = s.Adk != null && latest.Length > 0 && SameOrNewer(s.Adk.Version, latest);
            // information only: a neutral bullet unless the installed ADK is this release
            statusLabels[4].Text = (upToDate ? "\u2714 " : "\u2022 ") + (latest.Length == 0 ? "-" : latest + "   " + latestName);
            statusLabels[4].ForeColor = upToDate ? Color.FromArgb(16, 124, 16) : SystemColors.ControlText;

            chkUninstall.Visible = (s.Adk != null || s.Pe != null);
            installedAdkVersion = s.Adk != null ? s.Adk.Version : (s.Pe != null ? s.Pe.Version : null);
            FillReleases();
            UpdateUninstallDefault();
        }

        // checked when the installed version is not the selected one
        void UpdateUninstallDefault()
        {
            Release r = Selected;
            chkUninstall.Checked = chkUninstall.Visible && installedAdkVersion != null && r != null &&
                                   !SameVersion(installedAdkVersion, r.Version);
        }

        // ---------- releases ----------

        class Release
        {
            public string Version, Name, AdkFolder, PeFolder, AdkFile, PeFile;
            public bool Latest, Installed;
            public override string ToString()
            {
                string t = Version + "   " + Name;
                if (Latest) t += "   [" + L.T("adk.release_latest") + "]";
                if (Installed) t += "   [" + L.T("adk.release_installed") + "]";
                return t;
            }
        }

        void LoadReleases()
        {
            releases.Clear();
            if (data == null) return;
            foreach (KeyValuePair<string, List<KeyValuePair<string, string>>> sec in data)
            {
                if (!sec.Key.StartsWith("release ", StringComparison.OrdinalIgnoreCase)) continue;
                string sk = sec.Key;
                Release r = new Release();
                r.Version = sk.Substring(8).Trim();
                r.Name = L.Value(data, sk, "name");
                r.AdkFolder = L.Value(data, sk, "adk_folder");
                r.PeFolder = L.Value(data, sk, "pe_folder");
                r.AdkFile = L.Value(data, sk, "adk_file");
                r.PeFile = L.Value(data, sk, "pe_file");
                r.Latest = L.Value(data, sk, "latest").Trim() == "1";
                if ((r.AdkFolder.Length == 0 && r.AdkFile.Length == 0) || (r.PeFolder.Length == 0 && r.PeFile.Length == 0)) continue;
                releases.Add(r);
            }
            // newest first
            releases.Sort(delegate(Release a, Release b)
            {
                if (SameVersion(a.Version, b.Version)) return 0;
                return SameOrNewer(a.Version, b.Version) ? -1 : 1;
            });
        }

        void FillReleases()
        {
            Release keep = Selected;
            int sel = 0;
            cboRelease.BeginUpdate();
            cboRelease.Items.Clear();
            for (int n = 0; n < releases.Count; n++)
            {
                Release r = releases[n];
                r.Installed = installedAdkVersion != null && SameVersion(installedAdkVersion, r.Version);
                cboRelease.Items.Add(r);
                if (keep != null && r.Version == keep.Version) sel = n;
            }
            if (cboRelease.Items.Count > 0) cboRelease.SelectedIndex = sel;
            cboRelease.EndUpdate();
        }

        Release Selected
        {
            get { return cboRelease == null ? null : cboRelease.SelectedItem as Release; }
        }

        void SetLine(int n, bool ok, string text)
        {
            statusLabels[n].Text = (ok ? "\u2714 " : "\u2716 ") + text;
            statusLabels[n].ForeColor = ok ? Color.FromArgb(16, 124, 16) : Ui.ColorDanger;
        }

        string LatestKnown()
        {
            string best = "";
            if (data == null) return best;
            foreach (KeyValuePair<string, List<KeyValuePair<string, string>>> sec in data)
            {
                string v = AdkCore.SectionVersion(sec.Key);
                if (v == null) continue;
                if (best.Length == 0 || !SameOrNewer(best, v)) best = v;
            }
            return best;
        }

        // true when version a >= version b
        static bool SameOrNewer(string a, string b)
        {
            Version va, vb;
            try { va = new Version(a); vb = new Version(b); }
            catch (Exception) { return string.Equals(a, b, StringComparison.OrdinalIgnoreCase); }
            return va >= vb;
        }

        // ---------- download (background) ----------

        class DownloadResult
        {
            public string AdkSetup, PeSetup;
            public string AdkHash, PeHash, AdkKnown, PeKnown, AdkSig, PeSig, AdkFileVersion;
            public string Error;
        }

        void StartDownload(string mode, string layoutDir)
        {
            if (Busy) return;
            if (data == null) { Ui.Info(L.T("adk.no_data"), MessageBoxIcon.Error); return; }
            Release rel = Selected;
            if (rel == null) { Ui.Info(L.T("adk.no_release"), MessageBoxIcon.Error); return; }
            if (mode == "install" && !Ui.YesNo(L.F("adk.confirm_install", rel.Version, rel.Name), MessageBoxIcon.Question)) return;
            pendingMode = mode;
            pendingLayoutDir = layoutDir;
            pendingRelease = rel;
            log.Clear();
            Log(L.F("adk.log_release", rel.Version, rel.Name));
            SetBusy(true);
            string[] folders = { rel.AdkFolder, rel.PeFolder };
            string[] direct = { rel.AdkFile, rel.PeFile };

            worker = new BackgroundWorker();
            worker.WorkerReportsProgress = true;
            worker.DoWork += delegate(object s, DoWorkEventArgs e)
            {
                DownloadResult r = new DownloadResult();
                e.Result = r;
                try
                {
                    Directory.CreateDirectory(workDir);
                    ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                    r.AdkSetup = Path.Combine(workDir, "adksetup.exe");
                    r.PeSetup = Path.Combine(workDir, "adkwinpesetup.exe");
                    string[] files = { "adksetup.exe", "adkwinpesetup.exe" };
                    string[] dests = { r.AdkSetup, r.PeSetup };
                    for (int n = 0; n < 2; n++)
                    {
                        try { if (File.Exists(dests[n])) File.Delete(dests[n]); } catch (Exception) { }
                        string url = null;
                        if (folders[n].Length > 0)
                        {
                            try
                            {
                                worker.ReportProgress(-1, L.F("adk.log_resolve", folders[n]));
                                url = ResolveRoot(folders[n]) + files[n];
                                worker.ReportProgress(-1, L.F("adk.log_download", url));
                                Download(url, dests[n], n);
                                continue;
                            }
                            catch (Exception ex)
                            {
                                if (direct[n].Length == 0) throw;
                                worker.ReportProgress(-1, L.F("adk.log_try_direct", ex.Message));
                            }
                        }
                        // direct link to the setup file (redirects are followed)
                        worker.ReportProgress(-1, L.F("adk.log_download", direct[n]));
                        Download(direct[n], dests[n], n);
                    }
                    worker.ReportProgress(-1, L.T("adk.log_verify"));
                    r.AdkHash = AdkCore.Sha256(r.AdkSetup);
                    r.PeHash = AdkCore.Sha256(r.PeSetup);
                    r.AdkKnown = AdkCore.KnownVersion(data, "adksetup", r.AdkHash);
                    r.PeKnown = AdkCore.KnownVersion(data, "adkwinpesetup", r.PeHash);
                    r.AdkSig = AdkCore.CheckMicrosoftSignature(r.AdkSetup);
                    r.PeSig = AdkCore.CheckMicrosoftSignature(r.PeSetup);
                    r.AdkFileVersion = AdkCore.FileVersion(r.AdkSetup);
                }
                catch (Exception ex)
                {
                    r.Error = ex.Message;
                }
            };
            worker.ProgressChanged += delegate(object s, ProgressChangedEventArgs e)
            {
                string text = e.UserState as string;
                if (e.ProgressPercentage < 0) { if (text != null) Log(text); return; }
                progress.Style = ProgressBarStyle.Blocks;
                progress.Value = Math.Min(100, e.ProgressPercentage);
                if (text != null) lblProgress.Text = text;
            };
            worker.RunWorkerCompleted += delegate(object s, RunWorkerCompletedEventArgs e)
            {
                DownloadResult r = e.Result as DownloadResult;
                worker = null;
                if (r == null || r.Error != null)
                {
                    string err = r == null ? "?" : r.Error;
                    Log(L.F("adk.log_failed", err));
                    lblProgress.Text = L.T("adk.state_failed");
                    SetBusy(false);
                    Ui.Info(L.F("adk.download_failed", err), MessageBoxIcon.Error);
                    return;
                }
                if (!Approve(r.AdkSetup, r.AdkHash, r.AdkKnown, r.AdkSig, pendingRelease.Version) ||
                    !Approve(r.PeSetup, r.PeHash, r.PeKnown, r.PeSig, pendingRelease.Version))
                {
                    SetBusy(false);
                    lblProgress.Text = L.T("adk.state_cancelled");
                    return;
                }
                StartHelper(pendingMode, r.AdkSetup, r.PeSetup, pendingLayoutDir);
            };
            worker.RunWorkerAsync();
        }

        static string ResolveRoot(string link)
        {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(link);
            req.AllowAutoRedirect = false;
            req.UserAgent = "DVT-GUI";
            req.Proxy = WebRequest.DefaultWebProxy;
            if (req.Proxy != null) req.Proxy.Credentials = CredentialCache.DefaultCredentials;
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            {
                int code = (int)resp.StatusCode;
                string loc = resp.Headers["Location"];
                if (code < 300 || code > 399 || string.IsNullOrEmpty(loc))
                    throw new InvalidOperationException(L.F("adk.no_redirect", link, code));
                Uri u = new Uri(loc, UriKind.RelativeOrAbsolute);
                if (!u.IsAbsoluteUri) u = new Uri(new Uri(link), u);
                if (!u.Host.EndsWith(".microsoft.com", StringComparison.OrdinalIgnoreCase) || u.Scheme != "https")
                    throw new InvalidOperationException(L.F("adk.bad_host", u.ToString()));
                string s = u.ToString();
                return s.EndsWith("/") ? s : s + "/";
            }
        }

        void Download(string url, string dest, int index)
        {
            string part = dest + ".part";
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
            req.UserAgent = "DVT-GUI";
            req.Proxy = WebRequest.DefaultWebProxy;
            if (req.Proxy != null) req.Proxy.Credentials = CredentialCache.DefaultCredentials;
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            {
                if (!resp.ResponseUri.Host.EndsWith(".microsoft.com", StringComparison.OrdinalIgnoreCase) || resp.ResponseUri.Scheme != "https")
                    throw new InvalidOperationException(L.F("adk.bad_host", resp.ResponseUri.ToString()));
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
                        worker.ReportProgress(index * 50 + pct / 2,
                            L.F("adk.progress_download", Path.GetFileName(dest), done / 1024, total > 0 ? total / 1024 : 0));
                    }
                }
            }
            if (File.Exists(dest)) File.Delete(dest);
            File.Move(part, dest);
        }

        // Signature must be valid; an unknown hash or a file of another
        // release than the selected one (expected; null = any) needs the user's OK
        bool Approve(string file, string hash, string known, string sigError, string expected)
        {
            string name = Path.GetFileName(file);
            if (sigError != null)
            {
                Log(L.F("adk.log_bad_signature", name, sigError));
                Ui.Info(L.F("adk.bad_signature", name, sigError), MessageBoxIcon.Error);
                return false;
            }
            if (known.Length > 0)
            {
                Log(L.F("adk.log_known", name, known, hash));
                if (expected == null || SameVersion(known, expected)) return true;
                return Ui.YesNo(L.F("adk.wrong_release", name, known, expected), MessageBoxIcon.Warning);
            }
            string ver = AdkCore.FileVersion(file);
            Log(L.F("adk.log_unknown", name, ver, hash));
            return Ui.YesNo(L.F("adk.unknown_hash", name, ver, hash, expected ?? "-"), MessageBoxIcon.Warning);
        }

        // ---------- offline package ----------

        void CreateOffline()
        {
            if (Busy) return;
            using (FolderBrowserDialog dlg = new FolderBrowserDialog())
            {
                dlg.Description = L.T("adk.select_offline_target");
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                if (!Ui.YesNo(L.F("adk.confirm_offline", dlg.SelectedPath), MessageBoxIcon.Question)) return;
                StartDownload("layout", dlg.SelectedPath);
            }
        }

        void InstallFromFolder()
        {
            if (Busy) return;
            using (FolderBrowserDialog dlg = new FolderBrowserDialog())
            {
                dlg.Description = L.T("adk.select_offline_source");
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                string adk = FindFile(dlg.SelectedPath, "adksetup.exe");
                string pe = FindFile(dlg.SelectedPath, "adkwinpesetup.exe");
                if (adk == null || pe == null)
                {
                    Ui.Info(L.F("adk.offline_missing", dlg.SelectedPath), MessageBoxIcon.Warning);
                    return;
                }
                log.Clear();
                pendingRelease = null;
                Log(L.F("adk.log_offline", adk, pe));
                Cursor = Cursors.WaitCursor;
                string ah = AdkCore.Sha256(adk), ph = AdkCore.Sha256(pe);
                bool ok = Approve(adk, ah, AdkCore.KnownVersion(data, "adksetup", ah), AdkCore.CheckMicrosoftSignature(adk), null) &&
                          Approve(pe, ph, AdkCore.KnownVersion(data, "adkwinpesetup", ph), AdkCore.CheckMicrosoftSignature(pe), null);
                Cursor = Cursors.Default;
                if (!ok) return;
                if (!Ui.YesNo(L.T("adk.confirm_offline_install"), MessageBoxIcon.Question)) return;
                SetBusy(true);
                StartHelper("install", adk, pe, null);
            }
        }

        // <folder>\name, <folder>\ADK|WinPE\name, or one level deeper
        static string FindFile(string folder, string name)
        {
            string f = Path.Combine(folder, name);
            if (File.Exists(f)) return f;
            foreach (string sub in new[] { "ADK", "WinPE" })
            {
                f = Path.Combine(Path.Combine(folder, sub), name);
                if (File.Exists(f)) return f;
            }
            try
            {
                foreach (string d in Directory.GetDirectories(folder))
                {
                    f = Path.Combine(d, name);
                    if (File.Exists(f)) return f;
                }
            }
            catch (Exception) { }
            return null;
        }

        // ---------- elevated helper ----------

        void StartHelper(string mode, string adkSetup, string peSetup, string layoutDir)
        {
            if (mode == "install" && !CheckOlderKit(adkSetup)) { SetBusy(false); lblProgress.Text = L.T("adk.state_cancelled"); return; }
            Directory.CreateDirectory(workDir);
            string extra = mode == "layout" ? "\"" + layoutDir + "\"" : (chkUninstall.Visible && chkUninstall.Checked ? "uninstall" : "");
            string args = "--adk-helper " + mode + " \"" + adkSetup + "\" \"" + peSetup + "\" \"" + workDir + "\" " + extra;
            ProcessStartInfo psi = new ProcessStartInfo(Application.ExecutablePath, args.Trim());
            psi.UseShellExecute = true;
            psi.Verb = "runas";
            psi.WorkingDirectory = workDir;
            helperStatusFile = Path.Combine(workDir, "status.txt");
            try { if (File.Exists(helperStatusFile)) File.Delete(helperStatusFile); } catch (Exception) { }
            try
            {
                helper = Process.Start(psi);
            }
            catch (Win32Exception ex)
            {
                helper = null;
                Log(ex.NativeErrorCode == 1223 ? L.T("adk.log_uac_cancelled") : ex.Message);
                lblProgress.Text = L.T("adk.state_cancelled");
                SetBusy(false);
                return;
            }
            if (helper == null) { SetBusy(false); return; }
            if (mode == "layout") pendingLayoutCopy = new[] { adkSetup, peSetup, layoutDir };
            else pendingLayoutCopy = null;
            helperLinesShown = 0;
            helperStarted = DateTime.Now;
            progress.Style = ProgressBarStyle.Marquee;
            Log(L.T(mode == "layout" ? "adk.log_layout_start" : "adk.log_install_start"));
            timer.Start();
        }

        string[] pendingLayoutCopy;

        // The ADK setup cannot replace another installed version (exit code
        // 2008, "MSI replacement servicing is not supported"): that version
        // has to be uninstalled first. False = cancelled by the user.
        bool CheckOlderKit(string adkSetup)
        {
            if (chkUninstall.Checked) return true;
            AdkState s = AdkCore.Detect();
            string target = AdkCore.FileVersion(adkSetup);
            if (string.IsNullOrEmpty(target) && pendingRelease != null) target = pendingRelease.Version;
            List<string> other = new List<string>();
            if (s.Adk != null && !SameVersion(s.Adk.Version, target)) other.Add(s.Adk.Name + " " + s.Adk.Version);
            if (s.Pe != null && !SameVersion(s.Pe.Version, target)) other.Add(s.Pe.Name + " " + s.Pe.Version);
            if (other.Count == 0) return true;
            if (!Ui.YesNo(L.F("adk.need_uninstall", string.Join("\r\n", other.ToArray()), target), MessageBoxIcon.Warning))
                return false;
            chkUninstall.Visible = true;
            chkUninstall.Checked = true;
            Log(L.T("adk.log_uninstall_first"));
            return true;
        }

        static bool SameVersion(string a, string b)
        {
            Version va, vb;
            try { va = new Version(a); vb = new Version(b); }
            catch (Exception) { return string.Equals(a, b, StringComparison.OrdinalIgnoreCase); }
            return va.Major == vb.Major && va.Minor == vb.Minor && va.Build == vb.Build && va.Revision == vb.Revision;
        }

        void PollHelper()
        {
            if (helper == null) { timer.Stop(); return; }
            ShowHelperLines();
            TimeSpan t = DateTime.Now - helperStarted;
            bool exited;
            try { exited = helper.HasExited; } catch (Exception) { exited = true; }
            if (!exited)
            {
                lblProgress.Text = L.F("adk.state_running", (int)t.TotalMinutes, t.Seconds);
                return;
            }
            timer.Stop();
            int code = -1;
            try { code = helper.ExitCode; } catch (Exception) { }
            helper.Dispose();
            helper = null;
            ShowHelperLines();
            SetBusy(false);

            if (code == 0 || code == 3010)
            {
                if (pendingLayoutCopy != null)
                {
                    // keep the two setup files with the offline package
                    try
                    {
                        File.Copy(pendingLayoutCopy[0], Path.Combine(Path.Combine(pendingLayoutCopy[2], "ADK"), "adksetup.exe"), true);
                        File.Copy(pendingLayoutCopy[1], Path.Combine(Path.Combine(pendingLayoutCopy[2], "WinPE"), "adkwinpesetup.exe"), true);
                    }
                    catch (Exception) { }
                    lblProgress.Text = L.T("adk.state_layout_done");
                    Log(L.F("adk.log_layout_done", pendingLayoutCopy[2]));
                    Ui.Info(L.F("adk.layout_done", pendingLayoutCopy[2]));
                }
                else
                {
                    lblProgress.Text = L.T("adk.state_done");
                    Log(L.T("adk.log_done"));
                    Ui.Info(code == 3010 ? L.T("adk.done_restart") : L.T("adk.done"));
                }
            }
            else
            {
                lblProgress.Text = L.T("adk.state_failed");
                Log(L.F("adk.log_exit", code));
                string hint = code == 2008 ? "\r\n\r\n" + L.T("adk.err_2008") : "";
                if (code == 2008) Log(L.T("adk.err_2008"));
                Ui.Info(L.F("adk.failed", code, workDir) + hint, MessageBoxIcon.Error);
            }
            pendingLayoutCopy = null;
            RefreshStatus();
            Ui.Status(lblProgress.Text);
        }

        void ShowHelperLines()
        {
            try
            {
                if (helperStatusFile == null || !File.Exists(helperStatusFile)) return;
                string[] lines;
                using (FileStream fs = new FileStream(helperStatusFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                using (StreamReader r = new StreamReader(fs))
                    lines = r.ReadToEnd().Replace("\r\n", "\n").Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
                for (; helperLinesShown < lines.Length; helperLinesShown++)
                    Log(lines[helperLinesShown]);
            }
            catch (Exception) { }
        }
    }
}
