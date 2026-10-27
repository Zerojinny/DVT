// ============================================================
//  DVT GUI - Descriptions.cs
//  Help of the settings. The text is in the language files
//  (gui_cs\lang\<code>.ini, sections [setting file:NAME] and
//  [setting NAME]); see Lang.cs.
//    summary  : one line, shown in the grid
//    details  : shown below the grid (with the comment of the file)
//    advanced : 1 = usually left as it is (hidden until "Show advanced")
//    choice X : meaning of value X, offered in a drop-down list
//  A key "file:NAME" (host, pe, media, mediape, test) is used before
//  the plain "NAME", for settings that mean different things in
//  different files.
// ============================================================
using System.Collections.Generic;

namespace Dvt
{
    public class ChoiceItem
    {
        public string Value { get; set; }
        public string Text { get; set; }
        public ChoiceItem(string value, string text) { Value = value; Text = text; }
        public override string ToString() { return Text; }
    }

    public class SettingInfo
    {
        public string Summary = "";
        public string Details = "";
        public bool Advanced;
        public List<ChoiceItem> Choices = new List<ChoiceItem>();
    }

    public static class Descriptions
    {
        public static SettingInfo Get(string fileKey, string name)
        {
            return L.Setting(fileKey, name);
        }
    }
}
