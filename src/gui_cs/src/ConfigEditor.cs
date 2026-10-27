// ============================================================
//  DVT GUI - ConfigEditor.cs
//  Grid editor for one config.cmd file: one row per setting with a
//  short description, grouped by the "rem ---------- section ----------"
//  headers. Below the grid: the full help of the selected setting
//  (built-in description, choices and the comment of the file).
//  Advanced settings are hidden until "Show advanced" is checked.
// ============================================================
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace Dvt
{
    public class ConfigEditor : UserControl
    {
        public string FilePath;
        public string Note;
        public readonly string FileKey;      // host, pe, media, mediape, test
        public DvtConfig Config;
        public event EventHandler DirtyChanged;

        DateTime loadedTime;
        bool loading;
        bool lastDirty;
        readonly DataGridView grid;
        readonly RichTextBox help;
        readonly Label pathLabel;
        readonly Button btnSave;
        readonly CheckBox chkAdvanced;

        public ConfigEditor(string fileKey, string path, string note)
        {
            FileKey = fileKey;
            FilePath = path;
            Note = note;

            TableLayoutPanel rows = Ui.NewRows(36, 0, 170);

            // -- top bar --
            FlowLayoutPanel bar = Ui.NewFlow();
            btnSave = Ui.NewButton(L.T("btn.save"), 80);
            btnSave.Font = Ui.FontBold;
            Button btnReload = Ui.NewButton(L.T("btn.reload"), 80);
            Button btnNotepad = Ui.NewButton(L.T("btn.notepad"), 120);
            chkAdvanced = new CheckBox();
            chkAdvanced.AutoSize = true;
            chkAdvanced.Margin = new Padding(Ui.S(8), Ui.S(7), Ui.S(8), 0);
            pathLabel = Ui.NewFlowLabel("");
            pathLabel.ForeColor = SystemColors.GrayText;
            bar.Controls.AddRange(new Control[] { btnSave, btnReload, btnNotepad, chkAdvanced, pathLabel });

            // -- grid --
            grid = new DataGridView();
            grid.Dock = DockStyle.Fill;
            grid.AllowUserToAddRows = false;
            grid.AllowUserToDeleteRows = false;
            grid.AllowUserToResizeRows = false;
            grid.RowHeadersVisible = false;
            grid.SelectionMode = DataGridViewSelectionMode.CellSelect;
            grid.MultiSelect = false;
            grid.EditMode = DataGridViewEditMode.EditOnEnter;
            grid.BackgroundColor = SystemColors.Window;
            grid.BorderStyle = BorderStyle.FixedSingle;
            grid.ShowCellToolTips = true;
            grid.RowTemplate.Height = Ui.S(26);
            grid.ColumnHeadersHeight = Ui.S(28);
            grid.ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.DisableResizing;
            grid.EnableHeadersVisualStyles = false;
            grid.ColumnHeadersDefaultCellStyle.Font = Ui.FontBold;
            grid.ColumnHeadersDefaultCellStyle.BackColor = Palette.TabIdle;
            grid.DefaultCellStyle.SelectionBackColor = Color.FromArgb(204, 228, 247);
            grid.DefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
            grid.GridColor = Color.FromArgb(225, 228, 233);
            // the section titles are drawn across the whole row (RowPostPaint);
            // without double buffering, scrolling and rebuilding the rows can
            // leave stale pixels of the previous rows on the screen
            try
            {
                typeof(DataGridView).GetProperty("DoubleBuffered",
                    System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
                    .SetValue(grid, true, null);
            }
            catch (Exception) { }
            grid.Scroll += delegate { grid.Invalidate(); };

            DataGridViewTextBoxColumn colName = new DataGridViewTextBoxColumn();
            colName.HeaderText = L.T("grid.setting");
            colName.ReadOnly = true;
            colName.Width = Ui.S(210);
            colName.SortMode = DataGridViewColumnSortMode.NotSortable;
            DataGridViewTextBoxColumn colValue = new DataGridViewTextBoxColumn();
            colValue.HeaderText = L.T("grid.value");
            colValue.AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill;
            colValue.FillWeight = 45;
            colValue.SortMode = DataGridViewColumnSortMode.NotSortable;
            DataGridViewTextBoxColumn colDesc = new DataGridViewTextBoxColumn();
            colDesc.HeaderText = L.T("grid.description");
            colDesc.ReadOnly = true;
            colDesc.AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill;
            colDesc.FillWeight = 55;
            colDesc.SortMode = DataGridViewColumnSortMode.NotSortable;
            colDesc.DefaultCellStyle.ForeColor = Color.FromArgb(80, 86, 96);
            grid.Columns.Add(colName);
            grid.Columns.Add(colValue);
            grid.Columns.Add(colDesc);

            // -- help of the selected setting --
            help = new RichTextBox();
            help.Dock = DockStyle.Fill;
            help.ReadOnly = true;
            help.BorderStyle = BorderStyle.FixedSingle;
            help.BackColor = Color.FromArgb(255, 252, 235);
            help.ScrollBars = RichTextBoxScrollBars.Vertical;
            help.DetectUrls = false;

            rows.Controls.Add(bar, 0, 0);
            rows.Controls.Add(grid, 0, 1);
            rows.Controls.Add(help, 0, 2);
            Controls.Add(rows);
            Dock = DockStyle.Fill;

            // -- events --
            btnSave.Click += delegate { SaveFile(); };
            btnReload.Click += delegate
            {
                if (Dirty && !Ui.YesNo(L.F("editor.discard", FilePath), MessageBoxIcon.Warning)) return;
                LoadFile();
            };
            btnNotepad.Click += delegate
            {
                if (Dirty)
                {
                    Ui.Info(L.T("editor.notepad_dirty"));
                    return;
                }
                Ui.OpenInNotepad(FilePath);
            };
            chkAdvanced.CheckedChanged += delegate
            {
                if (!EndEditing()) return;
                BuildRows();
            };
            grid.DataError += delegate(object s, DataGridViewDataErrorEventArgs e) { e.ThrowException = false; };
            grid.CurrentCellDirtyStateChanged += delegate
            {
                if (grid.IsCurrentCellDirty && grid.CurrentCell is DataGridViewComboBoxCell)
                    grid.CommitEdit(DataGridViewDataErrorContexts.Commit);
            };
            // section rows: no cell text, the title is drawn across the whole row
            grid.CellPainting += delegate(object s, DataGridViewCellPaintingEventArgs e)
            {
                if (e.RowIndex < 0 || grid.Rows[e.RowIndex].Tag != null) return;
                e.Paint(e.ClipBounds, DataGridViewPaintParts.Background);
                e.Handled = true;
            };
            grid.RowPostPaint += delegate(object s, DataGridViewRowPostPaintEventArgs e)
            {
                DataGridViewRow row = grid.Rows[e.RowIndex];
                if (row.Tag != null) return;
                Rectangle r = e.RowBounds;
                using (SolidBrush b = new SolidBrush(Ui.ColorSectionBar))
                    e.Graphics.FillRectangle(b, r.X, r.Y, Ui.S(4), r.Height);
                r.X += Ui.S(10);
                r.Width -= Ui.S(10);
                TextRenderer.DrawText(e.Graphics, Convert.ToString(row.Cells[0].Value), Ui.FontBold, r,
                    Ui.ColorSectionText, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            };
            grid.CellValidating += OnCellValidating;
            grid.CellValueChanged += OnCellValueChanged;
            grid.SelectionChanged += delegate { ShowHelp(); };

            LoadFile();
        }

        public bool Dirty
        {
            get { return Config != null && Config.ChangedEntries().Count > 0; }
        }

        // Ends an open cell edit. False when the typed value is invalid.
        public bool EndEditing()
        {
            if (grid.IsCurrentCellInEditMode && !grid.EndEdit()) return false;
            UpdateDirty();
            return true;
        }

        public ConfigEntry Find(string name)
        {
            return Config == null ? null : Config.Find(name);
        }

        SettingInfo InfoOf(ConfigEntry e)
        {
            return Descriptions.Get(FileKey, e.Name);
        }

        public void LoadFile()
        {
            loading = true;
            try
            {
                grid.CancelEdit();
                try { grid.CurrentCell = null; } catch (Exception) { }
                grid.Rows.Clear();
                Config = null;
                help.Clear();
                if (string.IsNullOrEmpty(FilePath) || !File.Exists(FilePath))
                {
                    pathLabel.Text = L.F("editor.not_found", FilePath);
                    pathLabel.ForeColor = Ui.ColorDanger;
                    chkAdvanced.Text = L.T("editor.show_advanced");
                    return;
                }
                try
                {
                    Config = DvtConfig.Read(FilePath);
                }
                catch (Exception ex)
                {
                    pathLabel.Text = L.F("editor.cannot_read", FilePath, ex.Message);
                    pathLabel.ForeColor = Ui.ColorDanger;
                    return;
                }
                pathLabel.ForeColor = SystemColors.GrayText;
                loadedTime = File.GetLastWriteTimeUtc(FilePath);
            }
            finally
            {
                loading = false;
            }
            BuildRows();
        }

        // (Re)builds the grid rows from Config, keeping the edited values
        void BuildRows()
        {
            if (Config == null) { UpdateDirty(); return; }
            loading = true;
            try
            {
                string keepName = null;
                if (grid.CurrentRow != null && grid.CurrentRow.Tag is ConfigEntry) keepName = ((ConfigEntry)grid.CurrentRow.Tag).Name;
                try { grid.CurrentCell = null; } catch (Exception) { }
                grid.Rows.Clear();

                int hidden = 0;
                string section = null;
                DataGridViewRow keepRow = null;
                foreach (ConfigEntry entry in Config.Entries)
                {
                    if (!entry.Visible) continue;
                    SettingInfo info = InfoOf(entry);
                    bool advanced = info != null && info.Advanced;
                    // an advanced setting with an unsaved change stays visible
                    if (advanced && !chkAdvanced.Checked && !entry.Changed) { hidden++; continue; }

                    if (entry.Section != section)
                    {
                        section = entry.Section;
                        int si = grid.Rows.Add(L.Section(section), "", "");
                        DataGridViewRow sr = grid.Rows[si];
                        sr.ReadOnly = true;
                        sr.DefaultCellStyle.BackColor = Ui.ColorSection;
                        sr.DefaultCellStyle.SelectionBackColor = Ui.ColorSection;
                    }
                    string summary = info != null ? info.Summary : FirstLine(entry.Description);
                    string descText = (advanced ? L.T("editor.advanced_tag") + "  " : "") + summary;
                    int i = grid.Rows.Add(entry.Name, entry.Value, descText);
                    DataGridViewRow r = grid.Rows[i];
                    List<ChoiceItem> choices = ChoicesOf(entry, info);
                    if (choices != null)
                    {
                        DataGridViewComboBoxCell cb = new DataGridViewComboBoxCell();
                        cb.DisplayMember = "Text";
                        cb.ValueMember = "Value";
                        foreach (ChoiceItem c in choices) cb.Items.Add(c);
                        cb.FlatStyle = FlatStyle.Flat;
                        r.Cells[1] = cb;
                        // set every value again after the cell was replaced
                        r.Cells[0].Value = entry.Name;
                        r.Cells[1].Value = entry.Value;
                        r.Cells[2].Value = descText;
                    }
                    r.Tag = entry;
                    r.Cells[0].Style.Padding = new Padding(Ui.S(12), 0, 0, 0);
                    r.Cells[0].ToolTipText = summary;
                    if (advanced) r.Cells[0].Style.ForeColor = SystemColors.GrayText;
                    else r.Cells[0].Style.Font = Ui.FontBold;
                    if (entry.Changed) r.Cells[1].Style.BackColor = Ui.ColorChanged;
                    if (entry.Name == keepName) keepRow = r;
                }
                chkAdvanced.Text = chkAdvanced.Checked ? L.T("editor.show_advanced") : L.F("editor.show_advanced_hidden", hidden);
                chkAdvanced.Visible = hidden > 0 || chkAdvanced.Checked;
                // the rows changed: start at the top and repaint everything
                if (keepRow == null && grid.Rows.Count > 0)
                {
                    try { grid.FirstDisplayedScrollingRowIndex = 0; } catch (Exception) { }
                }
                if (keepRow != null)
                {
                    try { grid.CurrentCell = keepRow.Cells[0]; } catch (Exception) { }
                }
            }
            finally
            {
                loading = false;
            }
            grid.Invalidate();
            UpdateDirty();
            ShowHelp();
        }

        // Drop-down choices: built-in choices plus those read from the
        // comments, only when the current value is one of them
        List<ChoiceItem> ChoicesOf(ConfigEntry entry, SettingInfo info)
        {
            List<ChoiceItem> list = new List<ChoiceItem>();
            List<string> seen = new List<string>();
            if (info != null)
            {
                foreach (ChoiceItem c in info.Choices) { list.Add(c); seen.Add(c.Value); }
            }
            foreach (string o in entry.Options)
            {
                if (!seen.Contains(o)) { list.Add(new ChoiceItem(o, o)); seen.Add(o); }
            }
            if (list.Count < 2 || !seen.Contains(entry.Value)) return null;
            return list;
        }

        static string FirstLine(string text)
        {
            if (string.IsNullOrEmpty(text)) return "";
            int n = text.IndexOf('\r');
            return n < 0 ? text : text.Substring(0, n);
        }

        void UpdateDirty()
        {
            bool dirty = Dirty;
            if (Config != null)
            {
                pathLabel.Text = FilePath + (string.IsNullOrEmpty(Note) ? "" : "   (" + Note + ")");
                pathLabel.ForeColor = dirty ? Color.FromArgb(160, 100, 0) : SystemColors.GrayText;
                if (dirty) pathLabel.Text = L.T("editor.unsaved") + "   " + pathLabel.Text;
            }
            btnSave.Enabled = dirty;
            btnSave.BackColor = dirty ? Palette.Unsaved : SystemColors.Control;
            btnSave.UseVisualStyleBackColor = !dirty;
            if (dirty != lastDirty)
            {
                lastDirty = dirty;
                if (DirtyChanged != null) DirtyChanged(this, EventArgs.Empty);
            }
        }

        // True when saved (or nothing to save)
        public bool SaveFile()
        {
            if (Config == null) return true;
            if (!EndEditing()) return false;
            if (!Dirty) return true;
            if (!File.Exists(FilePath))
            {
                Ui.Info(L.F("editor.file_gone", FilePath), MessageBoxIcon.Error);
                return false;
            }
            if (File.GetLastWriteTimeUtc(FilePath) != loadedTime)
            {
                if (!Ui.YesNo(L.F("editor.changed_outside", FilePath), MessageBoxIcon.Warning))
                    return false;
                // apply the changes to the current file content
                Dictionary<string, string> changes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (ConfigEntry c in Config.ChangedEntries()) changes[c.Name] = c.Value;
                Config = DvtConfig.Read(FilePath);
                foreach (ConfigEntry e in Config.Entries)
                {
                    string v;
                    if (e.Visible && !e.ReadOnly && changes.TryGetValue(e.Name, out v)) e.Value = v;
                }
            }
            try
            {
                List<string> names = new List<string>();
                foreach (ConfigEntry c in Config.ChangedEntries()) names.Add(c.Name);
                Config.Save(Ui.Main.BackupDir);
                LoadFile();
                Ui.Status(L.F("status.saved_settings", FilePath, string.Join(", ", names.ToArray())));
                return true;
            }
            catch (Exception ex)
            {
                Ui.Info(L.F("msg.save_failed", ex.Message), MessageBoxIcon.Error);
                return false;
            }
        }

        void OnCellValidating(object sender, DataGridViewCellValidatingEventArgs e)
        {
            if (e.ColumnIndex != 1 || e.RowIndex < 0) return;
            DataGridViewRow row = grid.Rows[e.RowIndex];
            if (row.Tag == null || row.ReadOnly) return;
            if (row.Cells[1] is DataGridViewComboBoxCell) { row.ErrorText = ""; return; }
            string err = DvtUtil.TestValue(Convert.ToString(e.FormattedValue));
            if (err != null)
            {
                row.ErrorText = err;
                Ui.Status(((ConfigEntry)row.Tag).Name + ": " + err);
                e.Cancel = true;
            }
            else
            {
                row.ErrorText = "";
            }
        }

        void OnCellValueChanged(object sender, DataGridViewCellEventArgs e)
        {
            if (loading || e.RowIndex < 0 || e.ColumnIndex != 1) return;
            DataGridViewRow row = grid.Rows[e.RowIndex];
            ConfigEntry entry = row.Tag as ConfigEntry;
            if (entry == null) return;
            entry.Value = Convert.ToString(row.Cells[1].Value) ?? "";
            row.Cells[1].Style.BackColor = entry.Changed ? Ui.ColorChanged : Color.Empty;
            UpdateDirty();
            ShowHelp();
        }

        // ---------- help panel ----------
        void ShowHelp()
        {
            DataGridViewRow row = grid.CurrentRow;
            ConfigEntry entry = row == null ? null : row.Tag as ConfigEntry;
            help.Clear();
            if (entry == null)
            {
                Append(L.T("help.select"), Ui.FontUI, SystemColors.GrayText);
                return;
            }
            SettingInfo info = InfoOf(entry);

            Append(entry.Name, Ui.FontHelpTitle, SystemColors.ControlText);
            if (info != null && info.Advanced) Append("   " + L.T("help.advanced"), Ui.FontUI, SystemColors.GrayText);
            Append("\n", Ui.FontUI, SystemColors.ControlText);
            if (info != null)
            {
                Append(info.Summary + "\n", Ui.FontBold, SystemColors.ControlText);
                if (info.Details.Length > 0) Append(info.Details.Replace("\r\n", "\n") + "\n", Ui.FontUI, SystemColors.ControlText);
                if (info.Choices.Count > 0)
                {
                    Append("\n" + L.T("help.choices") + "\n", Ui.FontBold, SystemColors.ControlText);
                    foreach (ChoiceItem c in info.Choices)
                        Append("   " + c.Text + (c.Value == entry.Value ? "   <- " + L.T("help.current") : "") + "\n", Ui.FontUI, SystemColors.ControlText);
                }
            }
            if (entry.Changed)
                Append("\n" + L.F("help.saved_value", entry.Original.Length == 0 ? L.T("help.empty") : entry.Original) + "\n", Ui.FontBold, Color.FromArgb(160, 100, 0));
            // a comment shared from the setting above is shown only when
            // there is no built-in description
            bool inherited = entry.Description != null && entry.Description.StartsWith("(comment above ");
            if (!string.IsNullOrEmpty(entry.Description) && !(inherited && info != null))
            {
                Append("\n" + L.F("help.file_comment", Path.GetFileName(FilePath)) + "\n", Ui.FontBold, SystemColors.GrayText);
                Append(entry.Description.Replace("\r\n", "\n") + "\n", Ui.FontMono, Color.FromArgb(70, 76, 86));
            }
            help.SelectionStart = 0;
            help.ScrollToCaret();
        }

        void Append(string text, Font font, Color color)
        {
            help.SelectionStart = help.TextLength;
            help.SelectionLength = 0;
            help.SelectionFont = font;
            help.SelectionColor = color;
            help.SelectedText = text;
        }
    }
}
