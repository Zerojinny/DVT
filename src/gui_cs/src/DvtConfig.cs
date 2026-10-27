// ============================================================
//  DVT GUI - DvtConfig.cs
//  Reads and writes the DVT settings files (config.cmd and the
//  ip.txt of the media). No user interface here.
//
//  config.cmd files are changed ONLY on the lines of the form
//      set "NAME=VALUE"
//  that start at the beginning of a line (not inside an if / for
//  block). Comments, other lines, the line order and the line ends
//  stay exactly as they are.
//  C# 5 (the csc.exe of the .NET Framework 4.x).
// ============================================================
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace Dvt
{
    public class ConfigEntry
    {
        public string Name;
        public string Value;
        public string Original;
        public int Line;
        public string Section;
        public string Description;
        public List<string> Options = new List<string>();
        public bool ReadOnly;
        public bool Visible;

        public bool Changed
        {
            get { return !ReadOnly && !string.Equals(Value, Original, StringComparison.Ordinal); }
        }
    }

    public class DvtConfig
    {
        public string Path;
        public List<string> Lines = new List<string>();
        public bool EndsWithNewLine;
        public string LineEnd = "\r\n";
        public Encoding FileEncoding;
        public List<ConfigEntry> Entries = new List<ConfigEntry>();

        // Choices offered in a drop-down list for some settings, in
        // addition to the choices read from the comments.
        static readonly Dictionary<string, string[]> KnownOptions =
            new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            { "USB_FS",        new[] { "fat32", "exfat" } },
            { "FTP_CLIENT",    new[] { "auto", "curl", "ftp" } },
            { "FTP_PASSIVE",   new[] { "1", "0" } },
            { "LINK_FALLBACK", new[] { "1G", "100" } },
            { "MEDIA_CONFIRM", new[] { "1", "0" } },
        };

        const RegexOptions RO = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;
        static readonly Regex ReHeader  = new Regex(@"^\s*rem\s+={3,}", RO);
        static readonly Regex ReSection = new Regex(@"^\s*rem\s+-{3,}\s*(.*?)\s*-{3,}\s*$", RO);
        static readonly Regex ReComment = new Regex(@"^\s*rem(?:\s(.*))?$", RO);
        static readonly Regex ReSet     = new Regex(@"^set\s+""([A-Za-z_][A-Za-z0-9_]*)=(.*)""\s*$", RO);
        static readonly Regex ReOption  = new Regex(@"^\s*([^\s=:]{1,8})(?:\s+or\s+empty)?\s+[=:]\s+\S", RO);
        static readonly Regex ReVersion = new Regex(@"^version\b", RO);

        public static DvtConfig Read(string path)
        {
            DvtConfig cfg = new DvtConfig();
            cfg.Path = path;

            byte[] bytes = File.ReadAllBytes(path);
            Encoding enc = Encoding.Default;
            int offset = 0;
            if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
            {
                enc = new UTF8Encoding(true);
                offset = 3;
            }
            cfg.FileEncoding = enc;
            string text = enc.GetString(bytes, offset, bytes.Length - offset);
            cfg.EndsWithNewLine = text.EndsWith("\n");
            if (text.Length > 0 && !text.Contains("\r\n") && text.Contains("\n")) cfg.LineEnd = "\n";

            cfg.Lines.AddRange(Regex.Split(text, "\r?\n"));
            if (cfg.EndsWithNewLine && cfg.Lines.Count > 0) cfg.Lines.RemoveAt(cfg.Lines.Count - 1);

            Dictionary<string, int> counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            string section = "General";
            List<string> buf = new List<string>();
            bool prevWasSet = false;
            string lastDesc = "";
            string lastOwner = "";
            List<string> lastOpts = new List<string>();

            for (int i = 0; i < cfg.Lines.Count; i++)
            {
                string l = cfg.Lines[i];
                Match m;
                if (ReHeader.IsMatch(l))
                {
                    buf.Clear(); prevWasSet = false;
                }
                else if ((m = ReSection.Match(l)).Success)
                {
                    section = m.Groups[1].Value;
                    buf.Clear(); prevWasSet = false;
                }
                else if ((m = ReComment.Match(l)).Success)
                {
                    buf.Add(m.Groups[1].Success ? m.Groups[1].Value.TrimEnd() : "");
                }
                else if ((m = ReSet.Match(l)).Success)
                {
                    ConfigEntry e = new ConfigEntry();
                    e.Name = m.Groups[1].Value;
                    e.Value = m.Groups[2].Value;
                    e.Original = e.Value;
                    e.Line = i;
                    e.Section = section;
                    if (buf.Count == 0 && prevWasSet)
                    {
                        // a group of set lines shares the comment above the first one
                        e.Description = lastDesc.Length == 0 ? "" :
                            "(comment above " + lastOwner + ")\r\n" + lastDesc;
                        e.Options.AddRange(lastOpts);
                    }
                    else
                    {
                        e.Description = string.Join("\r\n", buf.ToArray()).Trim('\r', '\n');
                        e.Options.AddRange(OptionsFromComment(buf));
                    }
                    string[] known;
                    if (KnownOptions.TryGetValue(e.Name, out known))
                    {
                        foreach (string o in known) if (!e.Options.Contains(o)) e.Options.Add(o);
                    }
                    int c;
                    counts.TryGetValue(e.Name, out c);
                    counts[e.Name] = c + 1;
                    e.Visible = (c == 0);
                    cfg.Entries.Add(e);
                    if (!(buf.Count == 0 && prevWasSet)) { lastDesc = e.Description; lastOwner = e.Name; }
                    lastOpts = new List<string>(e.Options);
                    buf.Clear(); prevWasSet = true;
                }
                else
                {
                    buf.Clear(); prevWasSet = false;
                }
            }

            foreach (ConfigEntry e in cfg.Entries)
            {
                // values the script computes itself are not edited:
                // a name set more than once, or a value with %~ (%~dp0 ...)
                if (counts[e.Name] > 1 || e.Value.Contains("%~"))
                {
                    e.ReadOnly = true;
                    e.Visible = false;
                }
                // the settings after the version block belong to the files section
                if (ReVersion.IsMatch(e.Section)) e.Section = "files";
                // a drop-down list only when the current value is one of the choices
                if (e.Options.Count < 2 || !e.Options.Contains(e.Value)) e.Options.Clear();
            }
            return cfg;
        }

        // "  1 = suspend ...", "  auto = curl.exe first", "  0 or empty : ..." -> 1, auto, 0
        static List<string> OptionsFromComment(List<string> lines)
        {
            List<string> result = new List<string>();
            foreach (string c in lines)
            {
                Match m = ReOption.Match(c);
                if (m.Success && !result.Contains(m.Groups[1].Value)) result.Add(m.Groups[1].Value);
            }
            return result;
        }

        public ConfigEntry Find(string name)
        {
            foreach (ConfigEntry e in Entries)
                if (e.Visible && string.Equals(e.Name, name, StringComparison.OrdinalIgnoreCase)) return e;
            return null;
        }

        public List<ConfigEntry> ChangedEntries()
        {
            List<ConfigEntry> list = new List<ConfigEntry>();
            foreach (ConfigEntry e in Entries) if (e.Changed) list.Add(e);
            return list;
        }

        // Writes the changed set lines back (after a backup copy).
        // Throws on an invalid value.
        public void Save(string backupDir)
        {
            List<ConfigEntry> changed = ChangedEntries();
            foreach (ConfigEntry e in changed)
            {
                string err = DvtUtil.TestValue(e.Value);
                if (err != null) throw new InvalidOperationException(e.Name + ": " + err);
            }
            if (!string.IsNullOrEmpty(backupDir)) DvtUtil.BackupFile(Path, backupDir);

            foreach (ConfigEntry e in changed)
                Lines[e.Line] = "set \"" + e.Name + "=" + e.Value + "\"";
            string text = string.Join(LineEnd, Lines.ToArray());
            if (EndsWithNewLine) text += LineEnd;
            File.WriteAllText(Path, text, FileEncoding);
            foreach (ConfigEntry e in changed) e.Original = e.Value;
        }
    }

    public static class DvtUtil
    {
        // Returns an error message, or null when the value can be written
        // into a set "NAME=VALUE" line of a batch file.
        public static string TestValue(string v)
        {
            if (v == null) return null;
            if (v.Contains("\"")) return L.T("val.quote");
            if (v.Contains("!")) return L.T("val.bang");
            foreach (char ch in v)
                if (ch < 0x20 || ch > 0x7E) return L.T("val.ascii");
            int pct = 0;
            foreach (char ch in v) if (ch == '%') pct++;
            if (pct % 2 != 0) return L.T("val.percent");
            return null;
        }

        static readonly Regex ReIPv4 = new Regex(@"^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$");

        public static bool TestIPv4(string text)
        {
            Match m = ReIPv4.Match(text ?? "");
            if (!m.Success) return false;
            for (int n = 1; n <= 4; n++) if (int.Parse(m.Groups[n].Value) > 255) return false;
            return true;
        }

        // Same rules as the WinPE scripts: lines starting with # and empty
        // lines are skipped, the first word of each other line is used.
        // Returns ip, subnet, gateway, dns1, dns2.
        public static string[] ReadIpFile(string path)
        {
            string[] vals = new string[] { "", "", "", "", "" };
            if (!File.Exists(path)) return vals;
            int n = 0;
            foreach (string l in File.ReadAllLines(path, Encoding.Default))
            {
                string t = l.Trim();
                if (t.Length == 0 || t.StartsWith("#")) continue;
                if (n < 5) vals[n] = Regex.Split(t, @"\s+")[0];
                n++;
            }
            return vals;
        }

        // Values are positional (the WinPE scripts skip empty lines), so
        // no gap is allowed.
        public static string TestIpValues(string[] v)
        {
            string[] names = new string[5];
            for (int n = 0; n < 5; n++) names[n] = L.T("ip.name" + (n + 1));
            if (string.IsNullOrEmpty(v[0])) return L.T("ip.required");
            int last = -1;
            for (int n = 0; n < 5; n++) if (!string.IsNullOrEmpty(v[n])) last = n;
            for (int n = 0; n <= last; n++)
            {
                if (string.IsNullOrEmpty(v[n]))
                    return L.F("ip.gap", names[n]);
                if (!TestIPv4(v[n])) return L.F("ip.invalid", names[n], v[n]);
            }
            return null;
        }

        public static void WriteIpFile(string path, string[] v)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("# DVT media - static IP settings (saved by DVT_GUI)\r\n");
            sb.Append("# One value per line: line 1 = ip (only the first three octets are\r\n");
            sb.Append("# used), line 2 = subnet, line 3 = gateway, lines 4-5 = DNS servers.\r\n");
            sb.Append("# Lines starting with # are ignored. Save the file as ANSI / ASCII.\r\n");
            foreach (string s in v) if (!string.IsNullOrEmpty(s)) sb.Append(s).Append("\r\n");
            File.WriteAllText(path, sb.ToString(), Encoding.ASCII);
        }

        // Expands %NAME% with the map first, then with the environment.
        // Used only to show and open output folders.
        public static string Resolve(string text, Dictionary<string, string> map)
        {
            string result = text;
            for (int pass = 0; pass < 10; pass++)
            {
                string before = result;
                result = Regex.Replace(result, "%([^%]+)%", delegate(Match m)
                {
                    string k = m.Groups[1].Value;
                    string v;
                    if (map.TryGetValue(k, out v)) return v;
                    v = Environment.GetEnvironmentVariable(k);
                    return v ?? m.Value;
                });
                if (result == before) break;
            }
            return result;
        }

        // Copies a file to <backupDir>\<yyyyMMdd-HHmmss>_<path with _>
        public static string BackupFile(string path, string backupDir)
        {
            Directory.CreateDirectory(backupDir);
            string flat = Regex.Replace(path, @"^([A-Za-z]):\\", "$1_");
            flat = Regex.Replace(flat, @"[\\/:]", "_");
            string dest = System.IO.Path.Combine(backupDir, DateTime.Now.ToString("yyyyMMdd-HHmmss") + "_" + flat);
            File.Copy(path, dest, true);
            return dest;
        }

        public static string FileText(string path)
        {
            if (!File.Exists(path)) return "not found";
            FileInfo i = new FileInfo(path);
            return string.Format("{0}   {1:0.0} MB", i.LastWriteTime.ToString("yyyy-MM-dd HH:mm"), i.Length / 1048576.0);
        }
    }
}
