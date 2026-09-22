using System.Windows.Interop;
using Forms = System.Windows.Forms;

namespace TeachingFocus.Windows;

internal sealed class SettingsWindow : Window {
    readonly Controller owner;
    readonly List<Action> refreshers = [];
    readonly List<EffectPreview> previews = [];
    readonly TextBlock status;
    readonly Button pause;
    bool refreshing;
    public SettingsWindow(Controller owner) {
        this.owner = owner; Title = "教學聚光燈設定"; Icon = Ui.AppIcon(); Width = 590;
        Height = Math.Min(820, SystemParameters.WorkArea.Height - 50); MinWidth = 550; MinHeight = 420;
        WindowStartupLocation = WindowStartupLocation.CenterScreen; Topmost = true;
        Background = Painting.Brush(Color.FromRgb(247, 249, 252)); Foreground = Ui.Ink; FontFamily = new FontFamily("Microsoft JhengHei UI"); FontSize = 13;
        var stack = new StackPanel { Margin = new Thickness(22) }; Content = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        AddSlider(stack, "聚光燈半徑", 40, 400, 1, s => s.Radius, (s, v) => s.Radius = v, "0 點");
        AddSlider(stack, "背景遮暗", .1, .9, .05, s => s.Dim, (s, v) => s.Dim = v, "percent");
        AddSlider(stack, "外框粗細", 1, 10, .5, s => s.BorderWidth, (s, v) => s.BorderWidth = v, "0.# 點");
        AddSlider(stack, "發光強度", 0, 30, 1, s => s.Glow, (s, v) => s.Glow = v, "0");
        var options = Ui.EqualRow(2);
        Ui.Add(options, Toggle("螢光外框", s => s.Border, (s, v) => s.Border = v), 0);
        Ui.Add(options, Toggle("聚光燈收縮動畫", s => s.Animate, (s, v) => s.Animate = v), 1); stack.Children.Add(options);
        EffectPreview? spotlightPreview = null;
        AddSlider(stack, "動畫時間", .1, 1, .05, s => s.AnimationSeconds, (s, v) => s.AnimationSeconds = v, "0.00 秒", Ui.Button("預覽", () => spotlightPreview?.Play()));
        options = Ui.EqualRow(2); Ui.Add(options, Toggle("游標光圈", s => s.Halo, (s, v) => s.Halo = v), 0); Ui.Add(options, Toggle("點擊波紋", s => s.Ripples, (s, v) => s.Ripples = v), 1); stack.Children.Add(options);
        var particles = FormRow();
        Ui.Add(particles, Toggle("點擊粒子", s => s.Particles, (s, v) => s.Particles = v), 0);
        var particleOptions = new StackPanel();
        var kind = new ComboBox { ItemsSource = new[] { "光點擴散", "短線火花", "小星芒" }, Margin = new Thickness(3), MinHeight = 27 };
        kind.SelectionChanged += (_, _) => { if (!refreshing && kind.SelectedIndex >= 0) owner.UpdateSettings(s => s.ParticleStyle = (ParticleKind)kind.SelectedIndex); };
        refreshers.Add(() => kind.SelectedIndex = (int)owner.Settings.ParticleStyle); particleOptions.Children.Add(kind);
        var intensity = new Slider { Minimum = 1, Maximum = 5, TickFrequency = 1, IsSnapToTickEnabled = true, TickPlacement = System.Windows.Controls.Primitives.TickPlacement.BottomRight, Margin = new Thickness(3), ToolTip = "粒子強度 1～5" };
        var intensityLabel = new TextBlock { FontSize = 11, Margin = new Thickness(3, 0, 0, 0) };
        intensity.ValueChanged += (_, _) => { if (!refreshing) owner.UpdateSettings(s => s.ParticleIntensity = (int)intensity.Value); };
        refreshers.Add(() => { intensity.Value = owner.Settings.ParticleIntensity; intensityLabel.Text = $"強度 {owner.Settings.ParticleIntensity}"; });
        particleOptions.Children.Add(intensity); particleOptions.Children.Add(intensityLabel);
        Ui.Add(particles, particleOptions, 1);
        var particlePreview = new EffectPreview(owner, PreviewKind.Particle) { Height = 76, Margin = new Thickness(10, 2, 0, 2), Cursor = Cursors.Hand }; previews.Add(particlePreview); Ui.Add(particles, particlePreview, 2); stack.Children.Add(particles);
        stack.Children.Add(Toggle("雙按 Ctrl 切換聚光燈", s => s.DoubleControl, (s, v) => s.DoubleControl = v));
        spotlightPreview = AddColorRow(stack, "外框顏色", false);
        AddColorRow(stack, "光圈顏色", true);
        AddSlider(stack, "光圈半徑", 6, 80, 1, s => s.HaloRadius, (s, v) => s.HaloRadius = v, "0 點");
        AddShortcut(stack, "凍結快捷鍵", Command.Freeze); AddShortcut(stack, "聚光燈快捷鍵", Command.Spotlight);
        AddSlider(stack, "長按 Esc", .5, 10, .5, s => s.EscapeSeconds, (s, v) => s.EscapeSeconds = v, "0.# 秒");
        var state = new Grid { Margin = new Thickness(0, 8, 0, 4) }; state.ColumnDefinitions.Add(new() { Width = new GridLength(86) }); state.ColumnDefinitions.Add(new());
        pause = Ui.Button("暫停", owner.TogglePause); Ui.Add(state, pause, 0);
        status = new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = 11, Foreground = Brushes.DimGray, Margin = new Thickness(9, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center }; Ui.Add(state, status, 1); stack.Children.Add(state);
        var actions = Ui.EqualRow(4);
        Ui.Add(actions, Ui.Button("試用聚光燈", owner.ToggleSpotlight), 0); Ui.Add(actions, Ui.Button("凍結並畫圖", () => _ = owner.FreezeAsync()), 1);
        Ui.Add(actions, Ui.Button("使用說明", () => MessageBox.Show(this, "雙按 Ctrl：聚光燈\n自訂快捷鍵：在設定點錄製\n凍結後點懸浮球選工具，拖曳可移動\n短按 Esc 收起面板，長按依設定結束講解\n\n只有光圈或點擊效果時不會攔截 Esc。\n暫停後從通知區選單繼續。\n\n設定存於 %LOCALAPPDATA%\\TeachingFocus\\settings.json。\n本版尚待 Windows 實機驗收。", "TeachingFocus")), 2);
        Ui.Add(actions, Ui.Button("還原預設設定", owner.RestoreDefaults), 3); stack.Children.Add(actions);
        stack.Children.Add(new TextBlock { Text = "設定會自動儲存。只有凍結畫面或聚光燈啟用時，長按 Esc 才會結束講解。", TextWrapping = TextWrapping.Wrap, FontSize = 11, Foreground = Brushes.DimGray, Margin = new Thickness(3, 10, 3, 2) });
        owner.SettingsChanged += Refresh; owner.StateChanged += RefreshStatus;
        IsVisibleChanged += (_, _) => { if (!IsVisible) foreach (var preview in previews) preview.Stop(); };
        Closed += (_, _) => { owner.SettingsChanged -= Refresh; owner.StateChanged -= RefreshStatus; foreach (var preview in previews) preview.Stop(); };
        Refresh();
    }
    static Grid FormRow() {
        var grid = new Grid { Margin = new Thickness(0, 6, 0, 6) };
        grid.ColumnDefinitions.Add(new() { Width = new GridLength(125) }); grid.ColumnDefinitions.Add(new() { Width = new GridLength(150) }); grid.ColumnDefinitions.Add(new()); return grid;
    }
    CheckBox Toggle(string label, Func<Settings, bool> read, Action<Settings, bool> write) {
        var box = new CheckBox { Content = label, Margin = new Thickness(3, 8, 3, 8), VerticalAlignment = VerticalAlignment.Center };
        box.Click += (_, _) => { if (!refreshing) owner.UpdateSettings(s => write(s, box.IsChecked == true)); };
        refreshers.Add(() => box.IsChecked = read(owner.Settings)); return box;
    }
    void AddSlider(Panel parent, string label, double min, double max, double step, Func<Settings, double> read, Action<Settings, double> write, string format, FrameworkElement? extra = null) {
        var grid = new Grid { Margin = new Thickness(0, 5, 0, 5) };
        grid.ColumnDefinitions.Add(new() { Width = new GridLength(125) }); grid.ColumnDefinitions.Add(new()); grid.ColumnDefinitions.Add(new() { Width = new GridLength(extra == null ? 68 : 108) });
        Ui.Add(grid, new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(3) }, 0);
        var slider = new Slider { Minimum = min, Maximum = max, TickFrequency = step, IsSnapToTickEnabled = true, Margin = new Thickness(3, 4, 8, 4), VerticalAlignment = VerticalAlignment.Center };
        var value = new TextBlock { VerticalAlignment = VerticalAlignment.Center, FontSize = 11, Margin = new Thickness(3) };
        slider.ValueChanged += (_, _) => { if (!refreshing) owner.UpdateSettings(s => write(s, slider.Value)); };
        refreshers.Add(() => { slider.Value = read(owner.Settings); value.Text = format == "percent" ? $"{read(owner.Settings):P0}" : read(owner.Settings).ToString(format); });
        Ui.Add(grid, slider, 1);
        if (extra == null) Ui.Add(grid, value, 2);
        else { var row = Ui.Row(); row.Children.Add(value); row.Children.Add(extra); Ui.Add(grid, row, 2); }
        parent.Children.Add(grid);
    }
    EffectPreview AddColorRow(Panel parent, string label, bool halo) {
        var row = FormRow(); Ui.Add(row, new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(3) }, 0);
        var values = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var swatch = Ui.Button("", () => {
            owner.ColorDialogOpen = true;
            try {
                var color = Painting.Parse(halo ? owner.Settings.HaloColor : owner.Settings.BorderColor);
                using var dialog = new Forms.ColorDialog { FullOpen = true, Color = System.Drawing.Color.FromArgb(color.R, color.G, color.B) };
                if (dialog.ShowDialog(new DialogOwner(new WindowInteropHelper(this).Handle)) == Forms.DialogResult.OK) {
                    string hex = $"#{dialog.Color.R:X2}{dialog.Color.G:X2}{dialog.Color.B:X2}";
                    owner.UpdateSettings(s => { if (halo) s.HaloColor = hex; else s.BorderColor = hex; });
                }
            } finally { owner.ColorDialogOpen = false; }
        });
        swatch.Width = 56; swatch.Height = 28; swatch.HorizontalAlignment = HorizontalAlignment.Left;
        refreshers.Add(() => swatch.Background = Painting.Brush(Painting.Parse(halo ? owner.Settings.HaloColor : owner.Settings.BorderColor))); values.Children.Add(swatch);
        if (halo) {
            var opacity = new Slider { Minimum = 0, Maximum = 1, TickFrequency = .01, IsSnapToTickEnabled = true, Width = 128, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(3, 2, 3, 1) };
            var amount = new TextBlock { FontSize = 10, Margin = new Thickness(3) };
            opacity.ValueChanged += (_, _) => { if (!refreshing) owner.UpdateSettings(s => s.HaloOpacity = opacity.Value); };
            refreshers.Add(() => { opacity.Value = owner.Settings.HaloOpacity; amount.Text = $"不透明度 {owner.Settings.HaloOpacity:P0}"; }); values.Children.Add(opacity); values.Children.Add(amount);
        }
        Ui.Add(row, values, 1);
        var preview = new EffectPreview(owner, halo ? PreviewKind.Halo : PreviewKind.Spotlight) { Height = 76, Margin = new Thickness(10, 2, 0, 2), Cursor = Cursors.Hand }; previews.Add(preview); Ui.Add(row, preview, 2); parent.Children.Add(row); return preview;
    }
    void AddShortcut(Panel parent, string label, Command command) {
        var row = FormRow(); Ui.Add(row, new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(3) }, 0);
        var value = new TextBlock { VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(3) }; Ui.Add(row, value, 1);
        var record = Ui.Button("錄製…", () => owner.RecordShortcut(command)); record.HorizontalAlignment = HorizontalAlignment.Left; record.Margin = new Thickness(10, 3, 3, 3); Ui.Add(row, record, 2);
        refreshers.Add(() => value.Text = (command == Command.Freeze ? owner.Settings.FreezeShortcut : owner.Settings.SpotlightShortcut).ToString()); parent.Children.Add(row);
    }
    void Refresh() { refreshing = true; try { foreach (var refresh in refreshers) refresh(); foreach (var preview in previews) preview.InvalidateVisual(); RefreshStatus(); } finally { refreshing = false; } }
    void RefreshStatus() { status.Text = owner.Status; pause.Content = owner.State.Paused ? "繼續使用" : "暫停"; }
    sealed class DialogOwner(nint handle) : Forms.IWin32Window { public nint Handle => handle; }
}

internal enum PreviewKind { Spotlight, Halo, Particle }
internal sealed class EffectPreview : FrameworkElement {
    readonly Controller owner;
    readonly PreviewKind kind;
    readonly BurstBuffer bursts = new();
    readonly DispatcherTimer timer;
    double started = double.NegativeInfinity, duration = .25;
    public EffectPreview(Controller owner, PreviewKind kind) {
        this.owner = owner; this.kind = kind; ClipToBounds = true;
        timer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(16) };
        timer.Tick += (_, _) => { if (owner.ReduceMotion) bursts.Clear(); else bursts.Expire(Controller.Now); InvalidateVisual(); if (bursts.Items.Count == 0 && !FocusAnimation.Sample(Controller.Now, started, duration, owner.ReduceMotion).Active) timer.Stop(); };
        MouseLeftButtonDown += (_, e) => { Play(); e.Handled = true; };
        Unloaded += (_, _) => Stop();
    }
    public void Play() {
        if (kind == PreviewKind.Halo) return;
        if (kind == PreviewKind.Particle) bursts.Add(new(new(ActualWidth / 2, ActualHeight / 2), Controller.Now, owner.Settings.ParticleStyle, owner.Settings.ParticleIntensity, "preview"), owner.ReduceMotion);
        else { started = Controller.Now; duration = owner.Settings.AnimationSeconds; }
        InvalidateVisual(); if (!owner.ReduceMotion) timer.Start();
    }
    public void Stop() { timer.Stop(); bursts.Clear(); started = double.NegativeInfinity; }
    protected override void OnRender(DrawingContext context) {
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight); var center = new Point(ActualWidth / 2, ActualHeight / 2);
        context.PushClip(new RectangleGeometry(bounds, 10, 10));
        if (kind == PreviewKind.Particle) {
            context.DrawRectangle(Painting.Brush(Color.FromRgb(34, 38, 43)), null, bounds);
            if (bursts.Items.Count == 0) Painting.Text(context, owner.ReduceMotion ? "已減少動態效果" : "點擊預覽", new(Math.Max(4, center.X - 35), center.Y - 9), 11, Colors.White, VisualTreeHelper.GetDpi(this).PixelsPerDip);
            Painting.Particles(context, bursts.Items, "preview", Painting.Parse(owner.Settings.BorderColor), Controller.Now);
        } else {
            context.DrawRectangle(Painting.Brush(Color.FromRgb(239, 242, 246)), null, bounds); context.DrawRectangle(Painting.Brush(Color.FromRgb(38, 41, 46)), null, new(center.X, 0, ActualWidth / 2, ActualHeight));
            if (kind == PreviewKind.Halo) context.DrawEllipse(Painting.Brush(Painting.Parse(owner.Settings.HaloColor), owner.Settings.HaloOpacity), null, center, Math.Min(33, owner.Settings.HaloRadius * .7), Math.Min(33, owner.Settings.HaloRadius * .7));
            else {
                var sample = FocusAnimation.Sample(Controller.Now, started, duration, owner.ReduceMotion || !owner.Settings.Animate);
                double radius = 20 * sample.Scale;
                var shade = new CombinedGeometry(GeometryCombineMode.Exclude, new RectangleGeometry(bounds), new EllipseGeometry(center, radius, radius));
                context.DrawGeometry(Painting.Brush(Colors.Black, owner.Settings.Dim * sample.Opacity), null, shade);
                Painting.GlowRing(context, center, radius, Painting.Parse(owner.Settings.BorderColor), owner.Settings.BorderWidth, Math.Min(14, owner.Settings.Glow), sample.Opacity);
            }
            Painting.Cursor(context, center);
        }
        context.Pop();
    }
}
