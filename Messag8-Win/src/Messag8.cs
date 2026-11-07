// Messag8 - Envoie du texte en plein écran sur un 2e moniteur, en temps réel.
// Compilation : voir build.bat (utilise le compilateur C# inclus dans Windows / .NET Framework 4).
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Windows.Forms;

static class Program
{
    [DllImport("user32.dll")]
    static extern bool SetProcessDPIAware();

    [STAThread]
    static void Main()
    {
        try { SetProcessDPIAware(); } catch { }
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new ControlForm());
    }
}

// ---------------------------------------------------------------- Réglages
class Settings
{
    public string FontName = "Arial";
    public float Size = 120;
    public bool Bold = true;
    public bool AutoFit = false; // taille fixe : les caractères gardent toujours la même grosseur
    public Color Fore = Color.White;
    public Color Back = Color.Black;
    public int Align = 1; // 0 gauche, 1 centre, 2 droite
    public bool Live = true;
    public int FlashCount = 4;
    public int FlashSpeed = 120;
    public bool Beep = false;
    public string ScreenName = "";

    public string LogoPath = "";

    public static string Dir
    {
        get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Messag8"); }
    }

    static string FilePath
    {
        get { return Path.Combine(Dir, "reglages.txt"); }
    }

    public static Settings Load()
    {
        Settings s = new Settings();
        try
        {
            if (!File.Exists(FilePath)) return s;
            foreach (string line in File.ReadAllLines(FilePath))
            {
                int i = line.IndexOf('=');
                if (i < 0) continue;
                string k = line.Substring(0, i), v = line.Substring(i + 1);
                try
                {
                    switch (k)
                    {
                        case "FontName": s.FontName = v; break;
                        case "Size": s.Size = float.Parse(v, System.Globalization.CultureInfo.InvariantCulture); break;
                        case "Bold": s.Bold = v == "1"; break;
                        case "AutoFit": break; // taille toujours fixe
                        case "Fore": s.Fore = Color.FromArgb(int.Parse(v)); break;
                        case "Back": s.Back = Color.FromArgb(int.Parse(v)); break;
                        case "Align": s.Align = int.Parse(v); break;
                        case "Live": s.Live = v == "1"; break;
                        case "FlashCount": s.FlashCount = int.Parse(v); break;
                        case "FlashSpeed": s.FlashSpeed = int.Parse(v); break;
                        case "Beep": s.Beep = v == "1"; break;
                        case "ScreenName": s.ScreenName = v; break;
                        case "LogoPath": s.LogoPath = v; break;
                    }
                }
                catch { }
            }
        }
        catch { }
        return s;
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath));
            List<string> l = new List<string>();
            l.Add("FontName=" + FontName);
            l.Add("Size=" + Size.ToString(System.Globalization.CultureInfo.InvariantCulture));
            l.Add("Bold=" + (Bold ? "1" : "0"));
            l.Add("AutoFit=" + (AutoFit ? "1" : "0"));
            l.Add("Fore=" + Fore.ToArgb());
            l.Add("Back=" + Back.ToArgb());
            l.Add("Align=" + Align);
            l.Add("Live=" + (Live ? "1" : "0"));
            l.Add("FlashCount=" + FlashCount);
            l.Add("FlashSpeed=" + FlashSpeed);
            l.Add("Beep=" + (Beep ? "1" : "0"));
            l.Add("ScreenName=" + ScreenName);
            l.Add("LogoPath=" + LogoPath);
            File.WriteAllLines(FilePath, l.ToArray());
        }
        catch { }
    }
}

// ---------------------------------------------------------------- Rendu (partagé entre aperçu et écran participant)
static class Renderer
{
    public static Font MakeFont(string name, float px, bool bold)
    {
        FontStyle st = bold ? FontStyle.Bold : FontStyle.Regular;
        try
        {
            FontFamily ff = new FontFamily(name);
            if (!ff.IsStyleAvailable(st))
            {
                FontStyle[] all = { FontStyle.Regular, FontStyle.Bold, FontStyle.Italic, FontStyle.Bold | FontStyle.Italic };
                foreach (FontStyle a in all) if (ff.IsStyleAvailable(a)) { st = a; break; }
            }
            return new Font(ff, Math.Max(1f, px), st, GraphicsUnit.Pixel);
        }
        catch
        {
            return new Font(FontFamily.GenericSansSerif, Math.Max(1f, px), st, GraphicsUnit.Pixel);
        }
    }

    static StringFormat MakeFormat(int align)
    {
        StringFormat sf = new StringFormat();
        sf.Alignment = align == 0 ? StringAlignment.Near : (align == 2 ? StringAlignment.Far : StringAlignment.Center);
        sf.LineAlignment = StringAlignment.Center;
        sf.Trimming = StringTrimming.None;
        return sf;
    }

    static bool Fits(Graphics g, string text, Settings s, float size, RectangleF inner, StringFormat sf)
    {
        using (Font f = MakeFont(s.FontName, size, s.Bold))
        {
            SizeF sz = g.MeasureString(text, f, (int)inner.Width, sf);
            if (sz.Height > inner.Height) return false;
            foreach (string w in text.Split(new char[] { ' ', '\n', '\r', '\t' }, StringSplitOptions.RemoveEmptyEntries))
                if (g.MeasureString(w, f).Width > inner.Width) return false;
        }
        return true;
    }

    public static void Draw(Graphics g, RectangleF area, string text, Settings s, float scale, bool inverted, bool hidden)
    {
        Color back = inverted ? s.Fore : s.Back;
        Color fore = inverted ? s.Back : s.Fore;
        using (SolidBrush b = new SolidBrush(back)) g.FillRectangle(b, area);
        if (hidden || string.IsNullOrEmpty(text) || text.Trim().Length == 0) return;

        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        g.SmoothingMode = SmoothingMode.HighQuality;

        RectangleF inner = RectangleF.Inflate(area, -area.Width * 0.04f, -area.Height * 0.05f);
        if (inner.Width < 4 || inner.Height < 4) return;

        using (StringFormat sf = MakeFormat(s.Align))
        {
            // Taille fixe choisie par l'utilisateur ; si le texte dépasse l'écran,
            // on réduit la police juste assez pour qu'il rentre.
            float size = s.Size * scale;
            if (!Fits(g, text, s, size, inner, sf))
            {
                float lo = 2, hi = size;
                for (int i = 0; i < 14; i++)
                {
                    float mid = (lo + hi) / 2;
                    if (Fits(g, text, s, mid, inner, sf)) lo = mid; else hi = mid;
                }
                size = lo;
            }

            using (Font f = MakeFont(s.FontName, size, s.Bold))
            using (SolidBrush fb = new SolidBrush(fore))
                g.DrawString(text, f, fb, inner, sf);
        }
    }
}

// ---------------------------------------------------------------- Écran participant
class DisplayForm : Form
{
    public Action<Graphics, RectangleF> Painter;
    Cursor blankCursor;

    public DisplayForm()
    {
        DoubleBuffered = true;
        ResizeRedraw = true;
        BackColor = Color.Black;
        ShowInTaskbar = false;
        Text = "Écran participant";
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
        try
        {
            Bitmap bmp = new Bitmap(16, 16);
            using (Graphics g = Graphics.FromImage(bmp)) g.Clear(Color.Transparent);
            blankCursor = new Cursor(bmp.GetHicon());
        }
        catch { }
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    public void PlaceOn(Screen scr, bool windowed)
    {
        if (windowed)
        {
            FormBorderStyle = FormBorderStyle.Sizable;
            TopMost = false;
            Cursor = Cursors.Default;
            Text = "Écran participant (mode fenêtre - un seul moniteur détecté)";
            StartPosition = FormStartPosition.Manual;
            Bounds = new Rectangle(scr.WorkingArea.X + 60, scr.WorkingArea.Y + 60, 960, 540);
        }
        else
        {
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            WindowState = FormWindowState.Normal;
            Bounds = scr.Bounds;
            TopMost = true;
            if (blankCursor != null) Cursor = blankCursor;
        }
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        if (Painter != null) Painter(e.Graphics, ClientRectangle);
    }
}

// ---------------------------------------------------------------- Aperçu
class PreviewPanel : Panel
{
    public PreviewPanel() { DoubleBuffered = true; ResizeRedraw = true; }
}

// ---------------------------------------------------------------- Fenêtre de contrôle
class ControlForm : Form
{
    Settings s;
    string shown = "";
    bool inverted = false;
    bool hiddenText = false;
    int flashTicks = 0;
    Timer flashTimer = new Timer();
    DisplayForm display;
    Screen[] screens = new Screen[0];
    bool loading = true;

    TextBox txt;
    PreviewPanel preview;
    ComboBox cbScreen, cbFont, cbAlign;
    NumericUpDown nudSize, nudFlashCount, nudFlashSpeed;
    CheckBox chkBold, chkLive, chkBeep, chkHide;
    Button btnShow, btnSend, btnFlash, btnClear, btnFore, btnBack;
    Label lblStatus;

    public ControlForm()
    {
        s = Settings.Load();
        Text = "Messag8";
        Font = new Font("Segoe UI", 10f);
        Size = new Size(1150, 760);
        MinimumSize = new Size(900, 600);
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        int fw = Math.Min(1150, wa.Width), fh = Math.Min(860, wa.Height);
        MinimumSize = new Size(Math.Min(900, wa.Width), Math.Min(600, wa.Height));
        StartPosition = FormStartPosition.Manual;
        Bounds = new Rectangle(wa.X + (wa.Width - fw) / 2, wa.Y + (wa.Height - fh) / 2, fw, fh);
        KeyPreview = true;
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
        BuildUi();
        ApplySettingsToUi();
        RefreshScreens();
        loading = false;

        flashTimer.Tick += FlashTick;
        KeyDown += OnKey;
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += OnDisplayChanged;
        Shown += delegate { ShowDisplay(); txt.Focus(); };
        FormClosing += delegate
        {
            Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= OnDisplayChanged;
            s.Save();
            if (display != null && !display.IsDisposed) display.Close();
        };
    }

    // ---------- Construction de l'interface
    void BuildUi()
    {
        TableLayoutPanel root = new TableLayoutPanel();
        root.Dock = DockStyle.Fill;
        root.ColumnCount = 2;
        root.RowCount = 1;
        root.Padding = new Padding(8);
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 360));
        Controls.Add(root);

        // Colonne gauche : texte + aperçu
        TableLayoutPanel left = new TableLayoutPanel();
        left.Dock = DockStyle.Fill;
        left.ColumnCount = 1;
        left.RowCount = 4;
        left.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        left.RowStyles.Add(new RowStyle(SizeType.Percent, 45));
        left.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        left.RowStyles.Add(new RowStyle(SizeType.Percent, 55));
        root.Controls.Add(left, 0, 0);

        left.Controls.Add(Header("Message à envoyer"), 0, 0);
        txt = new TextBox();
        txt.Multiline = true;
        txt.AcceptsReturn = true;
        txt.ScrollBars = ScrollBars.Vertical;
        txt.Dock = DockStyle.Fill;
        txt.Font = new Font("Segoe UI", 18f);
        txt.TextChanged += delegate { if (chkLive.Checked) SendText(); };
        txt.KeyDown += delegate(object o, KeyEventArgs e)
        {
            if (e.Control && e.KeyCode == Keys.A) { txt.SelectAll(); e.SuppressKeyPress = true; }
        };
        left.Controls.Add(txt, 0, 1);

        left.Controls.Add(Header("Aperçu de l'écran participant"), 0, 2);
        preview = new PreviewPanel();
        preview.Dock = DockStyle.Fill;
        preview.BackColor = Color.FromArgb(45, 45, 48);
        preview.Paint += PaintPreview;
        left.Controls.Add(preview, 0, 3);

        // Colonne droite : options
        FlowLayoutPanel right = new FlowLayoutPanel();
        right.Dock = DockStyle.Fill;
        right.FlowDirection = FlowDirection.TopDown;
        right.WrapContents = false;
        right.AutoScroll = true;
        right.Padding = new Padding(6, 0, 0, 0);
        int W = 295;
        TableLayoutPanel rightWrap = new TableLayoutPanel();
        rightWrap.Dock = DockStyle.Fill;
        rightWrap.Margin = new Padding(0);
        rightWrap.ColumnCount = 1;
        rightWrap.RowCount = 2;
        rightWrap.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        rightWrap.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        rightWrap.Controls.Add(right, 0, 0);
        root.Controls.Add(rightWrap, 1, 0);

        right.Controls.Add(Header("Écran participant"));
        cbScreen = new ComboBox(); cbScreen.DropDownStyle = ComboBoxStyle.DropDownList; cbScreen.Width = W;
        cbScreen.SelectedIndexChanged += delegate
        {
            if (loading) return;
            if (cbScreen.SelectedIndex >= 0 && cbScreen.SelectedIndex < screens.Length) s.ScreenName = screens[cbScreen.SelectedIndex].DeviceName;
            if (display != null && !display.IsDisposed && display.Visible) PlaceDisplay();
            preview.Invalidate();
        };
        right.Controls.Add(cbScreen);
        btnShow = Btn("Masquer l'écran participant", W, 36, Color.FromArgb(230, 230, 230));
        btnShow.Click += delegate
        {
            if (display != null && !display.IsDisposed && display.Visible) { display.Hide(); UpdateShowButton(); }
            else ShowDisplay();
        };
        right.Controls.Add(btnShow);

        right.Controls.Add(Header("Police"));
        cbFont = new ComboBox(); cbFont.DropDownStyle = ComboBoxStyle.DropDownList; cbFont.Width = W; cbFont.DropDownHeight = 400;
        using (InstalledFontCollection ifc = new InstalledFontCollection())
            foreach (FontFamily ff in ifc.Families) cbFont.Items.Add(ff.Name);
        cbFont.SelectedIndexChanged += delegate { if (cbFont.SelectedItem != null) { s.FontName = (string)cbFont.SelectedItem; Changed(); } };
        right.Controls.Add(cbFont);

        FlowLayoutPanel rowSize = Row();
        rowSize.Controls.Add(Lbl("Taille :"));
        nudSize = new NumericUpDown(); nudSize.Minimum = 8; nudSize.Maximum = 1500; nudSize.Increment = 10; nudSize.Width = 80;
        nudSize.ValueChanged += delegate { s.Size = (float)nudSize.Value; Changed(); };
        rowSize.Controls.Add(nudSize);
        chkBold = new CheckBox(); chkBold.Text = "Gras"; chkBold.AutoSize = true; chkBold.Margin = new Padding(10, 5, 0, 0);
        chkBold.CheckedChanged += delegate { s.Bold = chkBold.Checked; Changed(); };
        rowSize.Controls.Add(chkBold);
        right.Controls.Add(rowSize);

        FlowLayoutPanel rowAlign = Row();
        rowAlign.Controls.Add(Lbl("Alignement :"));
        cbAlign = new ComboBox(); cbAlign.DropDownStyle = ComboBoxStyle.DropDownList; cbAlign.Width = 150;
        cbAlign.Items.AddRange(new object[] { "Gauche", "Centre", "Droite" });
        cbAlign.SelectedIndexChanged += delegate { s.Align = cbAlign.SelectedIndex; Changed(); };
        rowAlign.Controls.Add(cbAlign);
        right.Controls.Add(rowAlign);

        right.Controls.Add(Header("Couleur du fond"));
        FlowLayoutPanel rowBack = Row();
        backChecks.Add(ColorCheck("Noir", Color.Black, true));
        backChecks.Add(ColorCheck("Blanc", Color.White, true));
        backChecks.Add(ColorCheck("Vert", GreenScreen, true));
        foreach (CheckBox cb in backChecks) rowBack.Controls.Add(cb);
        btnBack = Btn("Autre…", 80, 28, Color.White);
        btnBack.Click += delegate { Color c; if (PickColor(s.Back, out c)) { s.Back = c; Changed(); } };
        rowBack.Controls.Add(btnBack);
        right.Controls.Add(rowBack);

        right.Controls.Add(Header("Couleur du texte"));
        FlowLayoutPanel rowFore = Row();
        foreChecks.Add(ColorCheck("Blanc", Color.White, false));
        foreChecks.Add(ColorCheck("Noir", Color.Black, false));
        foreChecks.Add(ColorCheck("Jaune", Color.FromArgb(255, 220, 0), false));
        foreach (CheckBox cb in foreChecks) rowFore.Controls.Add(cb);
        btnFore = Btn("Autre…", 80, 28, Color.White);
        btnFore.Click += delegate { Color c; if (PickColor(s.Fore, out c)) { s.Fore = c; Changed(); } };
        rowFore.Controls.Add(btnFore);
        right.Controls.Add(rowFore);

        right.Controls.Add(Header("Envoi"));
        chkLive = new CheckBox(); chkLive.Text = "Temps réel (apparaît en tapant)"; chkLive.AutoSize = true;
        chkLive.CheckedChanged += delegate
        {
            s.Live = chkLive.Checked;
            btnSend.Enabled = !chkLive.Checked;
            if (chkLive.Checked) SendText();
        };
        right.Controls.Add(chkLive);
        btnSend = Btn("ENVOYER  (Ctrl+Entrée)", W, 44, Color.FromArgb(60, 140, 230));
        btnSend.ForeColor = Color.White;
        btnSend.Click += delegate { SendText(); };
        right.Controls.Add(btnSend);

        right.Controls.Add(Header("Flash"));
        btnFlash = Btn("⚡  FLASH  (F5)", W, 60, Color.FromArgb(255, 170, 0));
        btnFlash.Font = new Font("Segoe UI", 16f, FontStyle.Bold);
        btnFlash.Click += delegate { Flash(); };
        right.Controls.Add(btnFlash);
        FlowLayoutPanel rowFlash = Row();
        rowFlash.Controls.Add(Lbl("Nombre :"));
        nudFlashCount = new NumericUpDown(); nudFlashCount.Minimum = 1; nudFlashCount.Maximum = 30; nudFlashCount.Width = 55;
        nudFlashCount.ValueChanged += delegate { s.FlashCount = (int)nudFlashCount.Value; };
        rowFlash.Controls.Add(nudFlashCount);
        rowFlash.Controls.Add(Lbl("Vitesse (ms) :"));
        nudFlashSpeed = new NumericUpDown(); nudFlashSpeed.Minimum = 40; nudFlashSpeed.Maximum = 1000; nudFlashSpeed.Increment = 20; nudFlashSpeed.Width = 65;
        nudFlashSpeed.ValueChanged += delegate { s.FlashSpeed = (int)nudFlashSpeed.Value; };
        rowFlash.Controls.Add(nudFlashSpeed);
        right.Controls.Add(rowFlash);
        chkBeep = new CheckBox(); chkBeep.Text = "Son avec le flash"; chkBeep.AutoSize = true;
        chkBeep.CheckedChanged += delegate { s.Beep = chkBeep.Checked; };
        right.Controls.Add(chkBeep);

        right.Controls.Add(Header("Écran"));
        chkHide = new CheckBox(); chkHide.Text = "Masquer le texte (écran vide)  (F8)"; chkHide.AutoSize = true;
        chkHide.CheckedChanged += delegate { hiddenText = chkHide.Checked; RefreshAll(); };
        right.Controls.Add(chkHide);
        btnClear = Btn("EFFACER  (F9)", W, 40, Color.FromArgb(220, 70, 70));
        btnClear.ForeColor = Color.White;
        btnClear.Click += delegate { ClearAll(); };
        right.Controls.Add(btnClear);

        // Logo en bas à droite (modifiable)
        rightWrap.RowCount = 3;
        rightWrap.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        logoBox = new PictureBox();
        logoBox.SizeMode = PictureBoxSizeMode.Zoom;
        logoBox.Width = W;
        logoBox.Height = W * 9 / 16;
        logoBox.Margin = new Padding(6, 8, 6, 0);
        logoBox.Cursor = Cursors.Hand;
        logoBox.Click += delegate { ChooseLogo(); };
        new ToolTip().SetToolTip(logoBox, "Cliquer pour changer le logo");
        rightWrap.Controls.Add(logoBox, 0, 1);
        FlowLayoutPanel rowLogo = Row();
        rowLogo.Margin = new Padding(6, 2, 0, 0);
        LinkLabel lnkChange = new LinkLabel(); lnkChange.Text = "Changer le logo…"; lnkChange.AutoSize = true;
        lnkChange.LinkClicked += delegate { ChooseLogo(); };
        LinkLabel lnkDefault = new LinkLabel(); lnkDefault.Text = "Logo par défaut"; lnkDefault.AutoSize = true;
        lnkDefault.Margin = new Padding(16, 0, 0, 0);
        lnkDefault.LinkClicked += delegate { s.LogoPath = ""; s.Save(); LoadLogo(); };
        rowLogo.Controls.Add(lnkChange); rowLogo.Controls.Add(lnkDefault);
        rightWrap.Controls.Add(rowLogo, 0, 2);
        LoadLogo();

        lblStatus = new Label(); lblStatus.AutoSize = false; lblStatus.Width = W; lblStatus.Height = 60;
        lblStatus.ForeColor = Color.DimGray; lblStatus.Font = new Font("Segoe UI", 8.5f);
        right.Controls.Add(lblStatus);
    }

    Label Header(string t)
    {
        Label l = new Label();
        l.Text = t;
        l.AutoSize = true;
        l.Font = new Font("Segoe UI", 10.5f, FontStyle.Bold);
        l.Margin = new Padding(0, 7, 0, 2);
        return l;
    }
    Label Lbl(string t) { Label l = new Label(); l.Text = t; l.AutoSize = true; l.Margin = new Padding(0, 6, 4, 0); return l; }
    FlowLayoutPanel Row()
    {
        FlowLayoutPanel p = new FlowLayoutPanel();
        p.AutoSize = true; p.WrapContents = false; p.Margin = new Padding(0, 3, 0, 3);
        return p;
    }
    Button Btn(string t, int w, int h, Color back)
    {
        Button b = new Button();
        b.Text = t; b.Width = w; b.Height = h;
        b.BackColor = back; b.FlatStyle = FlatStyle.Flat;
        b.FlatAppearance.BorderColor = Color.Gray;
        b.Margin = new Padding(0, 3, 6, 3);
        b.Cursor = Cursors.Hand;
        return b;
    }

    // ---------- Logo
    PictureBox logoBox;

    static Image ReadImage(Stream st)
    {
        // Copie en mémoire pour ne pas verrouiller le fichier
        MemoryStream ms = new MemoryStream();
        st.CopyTo(ms);
        ms.Position = 0;
        return Image.FromStream(ms);
    }

    void LoadLogo()
    {
        Image img = null;
        try
        {
            if (!string.IsNullOrEmpty(s.LogoPath) && File.Exists(s.LogoPath))
                using (FileStream fs = File.OpenRead(s.LogoPath)) img = ReadImage(fs);
        }
        catch { img = null; }
        if (img == null)
        {
            try
            {
                using (Stream st = typeof(ControlForm).Assembly.GetManifestResourceStream("logo.png"))
                    if (st != null) img = ReadImage(st);
            }
            catch { }
        }
        Image old = logoBox.Image;
        logoBox.Image = img;
        if (old != null) old.Dispose();
    }

    void ChooseLogo()
    {
        using (OpenFileDialog d = new OpenFileDialog())
        {
            d.Title = "Choisir un logo";
            d.Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif|Tous les fichiers|*.*";
            if (d.ShowDialog(this) != DialogResult.OK) return;
            try
            {
                using (FileStream fs = File.OpenRead(d.FileName)) ReadImage(fs).Dispose(); // vérifie que c'est une image
                Directory.CreateDirectory(Settings.Dir);
                // Copie dans le dossier de Messag8 pour que le logo reste même si l'original est déplacé
                string dest = Path.Combine(Settings.Dir, "logo_perso" + Path.GetExtension(d.FileName).ToLowerInvariant());
                foreach (string old in Directory.GetFiles(Settings.Dir, "logo_perso.*"))
                    if (!string.Equals(old, dest, StringComparison.OrdinalIgnoreCase)) File.Delete(old);
                File.Copy(d.FileName, dest, true);
                s.LogoPath = dest;
                s.Save();
                LoadLogo();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Impossible d'utiliser cette image :\n" + ex.Message, "Messag8", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }

    void ApplySettingsToUi()
    {
        int fi = cbFont.Items.IndexOf(s.FontName);
        if (fi < 0) fi = cbFont.Items.IndexOf("Arial");
        if (fi < 0 && cbFont.Items.Count > 0) fi = 0;
        cbFont.SelectedIndex = fi;
        nudSize.Value = Math.Max(nudSize.Minimum, Math.Min(nudSize.Maximum, (decimal)s.Size));
        chkBold.Checked = s.Bold;
        cbAlign.SelectedIndex = Math.Max(0, Math.Min(2, s.Align));
        chkLive.Checked = s.Live;
        btnSend.Enabled = !s.Live;
        nudFlashCount.Value = Math.Max(1, Math.Min(30, s.FlashCount));
        nudFlashSpeed.Value = Math.Max(40, Math.Min(1000, s.FlashSpeed));
        chkBeep.Checked = s.Beep;
        UpdateColorButtons();
    }

    static readonly Color GreenScreen = Color.FromArgb(0, 177, 64);
    List<CheckBox> backChecks = new List<CheckBox>();
    List<CheckBox> foreChecks = new List<CheckBox>();
    bool syncingColors = false;

    // Case à cocher de couleur : une seule cochée à la fois (comme des boutons radio)
    CheckBox ColorCheck(string text, Color color, bool isBack)
    {
        CheckBox cb = new CheckBox();
        cb.Text = text; cb.AutoSize = true; cb.Tag = color;
        cb.Margin = new Padding(0, 6, 8, 0);
        cb.CheckedChanged += delegate
        {
            if (syncingColors) return;
            if (!cb.Checked) { syncingColors = true; cb.Checked = true; syncingColors = false; return; }
            if (isBack) s.Back = color; else s.Fore = color;
            if (loading) UpdateColorButtons(); else Changed();
        };
        return cb;
    }

    void UpdateColorButtons()
    {
        btnFore.BackColor = s.Fore; btnFore.ForeColor = Contrast(s.Fore);
        btnBack.BackColor = s.Back; btnBack.ForeColor = Contrast(s.Back);
        syncingColors = true;
        foreach (CheckBox cb in backChecks) cb.Checked = ((Color)cb.Tag).ToArgb() == s.Back.ToArgb();
        foreach (CheckBox cb in foreChecks) cb.Checked = ((Color)cb.Tag).ToArgb() == s.Fore.ToArgb();
        syncingColors = false;
    }
    static Color Contrast(Color c) { return (c.R * 0.3 + c.G * 0.59 + c.B * 0.11) > 140 ? Color.Black : Color.White; }

    bool PickColor(Color current, out Color result)
    {
        using (ColorDialog d = new ColorDialog())
        {
            d.Color = current; d.FullOpen = true;
            if (d.ShowDialog(this) == DialogResult.OK) { result = d.Color; return true; }
        }
        result = current; return false;
    }

    // ---------- Écrans
    void OnDisplayChanged(object sender, EventArgs e)
    {
        if (IsHandleCreated) BeginInvoke((MethodInvoker)delegate
        {
            RefreshScreens();
            if (display != null && !display.IsDisposed && display.Visible) PlaceDisplay();
        });
    }

    void RefreshScreens()
    {
        bool wasLoading = loading;
        loading = true;
        screens = Screen.AllScreens;
        cbScreen.Items.Clear();
        int sel = -1, firstSecondary = -1;
        for (int i = 0; i < screens.Length; i++)
        {
            Screen sc = screens[i];
            cbScreen.Items.Add(string.Format("Écran {0}{1}  -  {2}x{3}", i + 1, sc.Primary ? " (principal)" : "", sc.Bounds.Width, sc.Bounds.Height));
            if (sc.DeviceName == s.ScreenName) sel = i;
            if (!sc.Primary && firstSecondary < 0) firstSecondary = i;
        }
        // Par défaut : premier écran secondaire ; si l'écran mémorisé est le principal mais qu'un 2e existe, on prend le 2e.
        if (sel < 0 || (screens[sel].Primary && firstSecondary >= 0)) sel = firstSecondary >= 0 ? firstSecondary : 0;
        cbScreen.SelectedIndex = sel;
        loading = wasLoading;
        lblStatus.Text = screens.Length < 2
            ? "Un seul moniteur détecté : l'écran participant s'ouvre en fenêtre de test. Branchez le 2e moniteur (mode « Étendre ») et il sera utilisé automatiquement."
            : screens.Length + " moniteurs détectés.";
    }

    Screen TargetScreen()
    {
        int i = cbScreen.SelectedIndex;
        if (i >= 0 && i < screens.Length) return screens[i];
        return Screen.PrimaryScreen;
    }

    void ShowDisplay()
    {
        if (display == null || display.IsDisposed)
        {
            display = new DisplayForm();
            display.Painter = delegate(Graphics g, RectangleF r) { Renderer.Draw(g, r, shown, s, 1f, inverted, hiddenText); };
            display.VisibleChanged += delegate { UpdateShowButton(); };
            display.FormClosed += delegate { UpdateShowButton(); };
            display.Resize += delegate { preview.Invalidate(); };
        }
        PlaceDisplay();
        display.Show();
        PlaceDisplay();
        UpdateShowButton();
    }

    void PlaceDisplay()
    {
        Screen scr = TargetScreen();
        bool windowed = scr.Primary; // jamais en plein écran sur l'écran de contrôle
        display.PlaceOn(scr, windowed);
        preview.Invalidate();
    }

    void UpdateShowButton()
    {
        bool vis = display != null && !display.IsDisposed && display.Visible;
        btnShow.Text = vis ? "Masquer l'écran participant" : "Afficher l'écran participant";
    }

    // ---------- Actions
    void Changed()
    {
        if (loading) return;
        UpdateColorButtons();
        RefreshAll();
    }

    void SendText()
    {
        shown = txt.Text;
        RefreshAll();
    }

    void ClearAll()
    {
        txt.Clear();
        shown = "";
        RefreshAll();
        txt.Focus();
    }

    void Flash()
    {
        if (display == null || display.IsDisposed || !display.Visible) ShowDisplay();
        if (!chkLive.Checked) SendText();
        if (s.Beep) SystemSounds.Exclamation.Play();
        flashTimer.Stop();
        flashTicks = s.FlashCount * 2;
        inverted = true;
        flashTicks--;
        flashTimer.Interval = s.FlashSpeed;
        flashTimer.Start();
        RefreshAll();
    }

    void FlashTick(object sender, EventArgs e)
    {
        if (flashTicks <= 0)
        {
            flashTimer.Stop();
            inverted = false;
        }
        else
        {
            inverted = !inverted;
            flashTicks--;
        }
        RefreshAll();
    }

    void RefreshAll()
    {
        preview.Invalidate();
        if (display != null && !display.IsDisposed && display.Visible)
        {
            display.Invalidate();
            display.Update();
        }
    }

    void OnKey(object sender, KeyEventArgs e)
    {
        if (e.KeyCode == Keys.F5) { Flash(); e.Handled = true; e.SuppressKeyPress = true; }
        else if (e.KeyCode == Keys.F8) { chkHide.Checked = !chkHide.Checked; e.Handled = true; e.SuppressKeyPress = true; }
        else if (e.KeyCode == Keys.F9) { ClearAll(); e.Handled = true; e.SuppressKeyPress = true; }
        else if (e.Control && e.KeyCode == Keys.Enter) { SendText(); e.Handled = true; e.SuppressKeyPress = true; }
    }

    // ---------- Aperçu
    void PaintPreview(object sender, PaintEventArgs e)
    {
        Rectangle target = (display != null && !display.IsDisposed && display.Visible)
            ? new Rectangle(0, 0, display.ClientSize.Width, display.ClientSize.Height)
            : TargetScreen().Bounds;
        if (target.Width <= 0 || target.Height <= 0) return;
        Rectangle pane = preview.ClientRectangle;
        pane.Inflate(-8, -8);
        if (pane.Width <= 0 || pane.Height <= 0) return;
        float scale = Math.Min(pane.Width / (float)target.Width, pane.Height / (float)target.Height);
        float w = target.Width * scale, h = target.Height * scale;
        RectangleF r = new RectangleF(pane.X + (pane.Width - w) / 2, pane.Y + (pane.Height - h) / 2, w, h);
        Renderer.Draw(e.Graphics, r, shown, s, scale, inverted, hiddenText);
        using (Pen p = new Pen(Color.Gray)) e.Graphics.DrawRectangle(p, r.X, r.Y, r.Width, r.Height);
    }
}
