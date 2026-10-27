// ============================================================
//  DVT GUI - MediaPanels.cs
//  IpPanel    : ip.txt of the media (static IP base)
//  FilesPanel : DVT_backup.torrent and the aria2 profiles of the media
//  Both work on a config folder given by GetConfigDir: the build
//  folder (data\Media\config) or <USB>:\config.
// ============================================================
using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace Dvt
{
    public class IpPanel : UserControl
    {
        public Func<string> GetConfigDir;
        public string FilePath = "";
        public bool Dirty;
        public event EventHandler DirtyChanged;

        bool loading;
        readonly CheckBox check;
        readonly TextBox[] boxes = new TextBox[5];
        readonly Button btnSave;
        readonly Label pathLabel;

        public IpPanel(Func<string> getConfigDir)
        {
            GetConfigDir = getConfigDir;
            TableLayoutPanel rows = Ui.NewRows(30, 180, 34, 0);

            check = new CheckBox();
            check.Text = L.T("ip.use_static");
            check.AutoSize = true;
            rows.Controls.Add(check, 0, 0);

            TableLayoutPanel tbl = new TableLayoutPanel();
            tbl.Dock = DockStyle.Fill;
            tbl.ColumnCount = 3;
            tbl.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Ui.S(150)));
            tbl.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Ui.S(170)));
            tbl.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            string[] labels = new string[5];
            string[] hints = new string[5];
            for (int n = 0; n < 5; n++)
            {
                labels[n] = L.T("ip.label" + (n + 1));
                hints[n] = L.T("ip.hint" + (n + 1));
            }
            tbl.RowCount = 5;
            for (int n = 0; n < 5; n++)
            {
                tbl.RowStyles.Add(new RowStyle(SizeType.Absolute, Ui.S(34)));
                tbl.Controls.Add(Ui.NewLabel(labels[n]), 0, n);
                TextBox tb = new TextBox();
                tb.Width = Ui.S(150);
                tb.Anchor = AnchorStyles.Left;
                tb.TextChanged += delegate { if (!loading) SetDirty(true); };
                tbl.Controls.Add(tb, 1, n);
                tbl.Controls.Add(Ui.NewHint(hints[n]), 2, n);
                boxes[n] = tb;
            }
            rows.Controls.Add(tbl, 0, 1);

            FlowLayoutPanel bar = Ui.NewFlow();
            btnSave = Ui.NewButton(L.T("btn.save_ip"), 100);
            Button btnReload = Ui.NewButton(L.T("btn.reload"), 80);
            pathLabel = Ui.NewFlowLabel("");
            bar.Controls.Add(btnSave);
            bar.Controls.Add(btnReload);
            bar.Controls.Add(pathLabel);
            rows.Controls.Add(bar, 0, 2);

            Label note = Ui.NewHint(L.T("ip.note"));
            note.TextAlign = ContentAlignment.TopLeft;
            rows.Controls.Add(note, 0, 3);

            Controls.Add(rows);
            Dock = DockStyle.Fill;

            check.CheckedChanged += delegate
            {
                foreach (TextBox b in boxes) b.Enabled = check.Checked;
                if (!loading) SetDirty(true);
            };
            btnSave.Click += delegate { SaveFile(); };
            btnReload.Click += delegate
            {
                if (Dirty && !Ui.YesNo(L.T("ip.discard"), MessageBoxIcon.Warning)) return;
                LoadFile();
            };
        }

        void SetDirty(bool dirty)
        {
            bool changed = (Dirty != dirty);
            Dirty = dirty;
            if (changed && DirtyChanged != null) DirtyChanged(this, EventArgs.Empty);
            btnSave.Enabled = dirty;
            pathLabel.Text = (dirty ? L.T("editor.unsaved") + "   " : "") + FilePath;
        }

        public void LoadFile()
        {
            FilePath = Path.Combine(GetConfigDir(), "ip.txt");
            loading = true;
            try
            {
                bool exists = File.Exists(FilePath);
                string[] vals = DvtUtil.ReadIpFile(FilePath);
                for (int n = 0; n < 5; n++) { boxes[n].Text = vals[n]; boxes[n].Enabled = exists; }
                check.Checked = exists;
            }
            finally { loading = false; }
            SetDirty(false);
        }

        public bool SaveFile()
        {
            if (!Dirty) return true;
            string dir = Path.GetDirectoryName(FilePath);
            if (!Directory.Exists(dir))
            {
                Ui.Info(L.F("msg.config_missing", dir), MessageBoxIcon.Error);
                return false;
            }
            try
            {
                if (!check.Checked)
                {
                    if (File.Exists(FilePath))
                    {
                        if (!Ui.YesNo(L.F("ip.delete_confirm", FilePath), MessageBoxIcon.Warning)) return false;
                        DvtUtil.BackupFile(FilePath, Ui.Main.BackupDir);
                        File.Delete(FilePath);
                    }
                    SetDirty(false);
                    Ui.Status(L.F("status.ip_deleted", FilePath));
                    return true;
                }
                string[] vals = new string[5];
                for (int n = 0; n < 5; n++) vals[n] = boxes[n].Text.Trim();
                string err = DvtUtil.TestIpValues(vals);
                if (err != null) { Ui.Info(err, MessageBoxIcon.Warning); return false; }
                if (File.Exists(FilePath)) DvtUtil.BackupFile(FilePath, Ui.Main.BackupDir);
                DvtUtil.WriteIpFile(FilePath, vals);
                LoadFile();
                Ui.Status(L.F("status.saved_file", FilePath));
                return true;
            }
            catch (Exception ex)
            {
                Ui.Info(L.F("msg.save_failed", ex.Message), MessageBoxIcon.Error);
                return false;
            }
        }
    }


    public class FilesPanel : UserControl
    {
        public Func<string> GetConfigDir;
        readonly Label torrentLabel;
        readonly Label conf1GLabel;
        readonly Label conf100Label;

        public FilesPanel(Func<string> getConfigDir)
        {
            GetConfigDir = getConfigDir;
            TableLayoutPanel rows = Ui.NewRows(30, 36, 30, 36, 36, 36, 0);

            rows.Controls.Add(Ui.NewBoldLabel(L.T("files.torrent_title")), 0, 0);
            FlowLayoutPanel f1 = Ui.NewFlow();
            Button btnTorrent = Ui.NewButton(L.T("btn.select_torrent"), 160);
            torrentLabel = Ui.NewFlowLabel("");
            f1.Controls.Add(btnTorrent);
            f1.Controls.Add(torrentLabel);
            rows.Controls.Add(f1, 0, 1);

            rows.Controls.Add(Ui.NewBoldLabel(L.T("files.aria_title")), 0, 2);
            FlowLayoutPanel f2 = Ui.NewFlow();
            Button btn1G = Ui.NewButton(L.T("btn.edit_aria_1g"), 150);
            conf1GLabel = Ui.NewFlowLabel("");
            f2.Controls.Add(btn1G);
            f2.Controls.Add(conf1GLabel);
            rows.Controls.Add(f2, 0, 3);
            FlowLayoutPanel f3 = Ui.NewFlow();
            Button btn100 = Ui.NewButton(L.T("btn.edit_aria_100"), 150);
            conf100Label = Ui.NewFlowLabel("");
            f3.Controls.Add(btn100);
            f3.Controls.Add(conf100Label);
            rows.Controls.Add(f3, 0, 4);

            FlowLayoutPanel f4 = Ui.NewFlow();
            Button btnOpen = Ui.NewButton(L.T("btn.open_config"), 150);
            f4.Controls.Add(btnOpen);
            rows.Controls.Add(f4, 0, 5);

            Controls.Add(rows);
            Dock = DockStyle.Fill;

            btnTorrent.Click += delegate { SelectTorrent(); };
            btn1G.Click += delegate { Ui.OpenInNotepad(Path.Combine(GetConfigDir(), "aria2.conf.1G")); };
            btn100.Click += delegate { Ui.OpenInNotepad(Path.Combine(GetConfigDir(), "aria2.conf.100")); };
            btnOpen.Click += delegate { Ui.OpenFolder(GetConfigDir()); };
        }

        void SelectTorrent()
        {
            using (OpenFileDialog dlg = new OpenFileDialog())
            {
                dlg.Filter = L.T("dlg.torrent_filter");
                dlg.Title = L.T("dlg.torrent_title");
                if (dlg.ShowDialog(Ui.Main) != DialogResult.OK) return;
                string dest = Path.Combine(GetConfigDir(), "DVT_backup.torrent");
                try
                {
                    if (File.Exists(dest)) DvtUtil.BackupFile(dest, Ui.Main.BackupDir);
                    File.Copy(dlg.FileName, dest, true);
                    Ui.Status(L.F("status.copied", dlg.FileName, dest));
                }
                catch (Exception ex)
                {
                    Ui.Info(L.F("msg.copy_failed", ex.Message), MessageBoxIcon.Error);
                }
            }
            RefreshStatus();
        }

        public void RefreshStatus()
        {
            string dir = GetConfigDir();
            string t = Path.Combine(dir, "DVT_backup.torrent");
            if (File.Exists(t))
            {
                FileInfo i = new FileInfo(t);
                torrentLabel.Text = L.F("files.torrent_info", t, i.LastWriteTime.ToString("yyyy-MM-dd HH:mm"), i.Length);
                torrentLabel.ForeColor = SystemColors.ControlText;
            }
            else
            {
                torrentLabel.Text = L.F("files.torrent_missing", t);
                torrentLabel.ForeColor = Ui.ColorDanger;
            }
            SetFileLabel(conf1GLabel, Path.Combine(dir, "aria2.conf.1G"));
            SetFileLabel(conf100Label, Path.Combine(dir, "aria2.conf.100"));
        }

        static void SetFileLabel(Label l, string path)
        {
            bool ok = File.Exists(path);
            l.Text = ok ? path : L.F("msg.not_found", path);
            l.ForeColor = ok ? SystemColors.ControlText : Ui.ColorDanger;
        }
    }
}
