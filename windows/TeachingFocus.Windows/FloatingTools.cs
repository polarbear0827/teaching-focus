using System.Windows.Interop;
using System.Windows.Media.Effects;

namespace TeachingFocus.Windows;

internal sealed class FloatingTools : IDisposable {
    readonly Controller owner;
    readonly DisplayInfo display;
    readonly Window ball, panel;
    readonly FrameworkElement ballGraphic;
    readonly List<Button> tools = [], colors = [], widths = [];
    readonly Button undo, redo, spot;
    readonly TextBlock hint;
    Area ballArea;
    Position press, original;
    bool pressed, dragged, disposed;
    public bool Expanded { get; private set; }
    public FloatingTools(Controller owner, DisplayInfo display) {
        this.owner = owner; this.display = display;
        BallPosition saved = owner.Settings.BallPositions.GetValueOrDefault(display.Id) ?? new();
        ballArea = FloatingLayout.Ball(display.Width, display.Height, saved);
        ball = CreateWindow("講解工具懸浮球", 44, 44, true);
        ballGraphic = new BallGraphic(owner); ball.Content = ballGraphic;
        ballGraphic.MouseLeftButtonDown += (_, e) => {
            press = LocalCursor(); original = new(ballArea.X, ballArea.Y); pressed = true; dragged = false; ballGraphic.CaptureMouse(); e.Handled = true;
        };
        ballGraphic.MouseMove += (_, e) => {
            if (!pressed) return;
            Position point = LocalCursor(); dragged |= FloatingLayout.IsDrag(press, point);
            if (dragged) { Collapse(); ballArea = FloatingLayout.Clamp(new(original.X + point.X - press.X, original.Y + point.Y - press.Y), display.Width, display.Height); Displays.Place(ball, display, ballArea); }
            e.Handled = true;
        };
        ballGraphic.MouseLeftButtonUp += (_, e) => {
            if (!pressed) return;
            pressed = false; ballGraphic.ReleaseMouseCapture();
            if (dragged) {
                var position = FloatingLayout.Snap(ballArea, display.Width, display.Height);
                ballArea = FloatingLayout.Ball(display.Width, display.Height, position); Displays.Place(ball, display, ballArea);
                owner.UpdateSettings(s => s.BallPositions[display.Id] = position);
            } else Toggle();
            e.Handled = true;
        };
        ballGraphic.LostMouseCapture += (_, _) => pressed = false;
        panel = CreateWindow("講解工具", 320, 310, false);
        var content = new StackPanel { Margin = new Thickness(14) };
        var header = Ui.Row(); header.Children.Add(new TextBlock { Text = "畫面已凍結", FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
        var collapse = Ui.Button("收起", Collapse); collapse.HorizontalAlignment = HorizontalAlignment.Right;
        var headerGrid = new Grid(); headerGrid.ColumnDefinitions.Add(new()); headerGrid.ColumnDefinitions.Add(new() { Width = GridLength.Auto }); headerGrid.Children.Add(header); Grid.SetColumn(collapse, 1); headerGrid.Children.Add(collapse); content.Children.Add(headerGrid);
        string[] names = ["畫筆", "直線", "箭頭", "矩形", "橢圓", "雷射筆"];
        for (int row = 0; row < 2; row++) {
            var grid = Ui.EqualRow(3);
            for (int col = 0; col < 3; col++) { int index = row * 3 + col; var button = Ui.Button(names[index], () => { owner.Tool = (PaintTool)index; Sync(); }); tools.Add(button); Ui.Add(grid, button, col); }
            content.Children.Add(grid);
        }
        var colorGrid = Ui.EqualRow(5);
        for (int i = 0; i < 5; i++) {
            int index = i; string name = new[] { "紅", "藍", "綠", "黑", "白" }[i];
            var button = Ui.Button(name, () => { owner.ColorIndex = index; Sync(); });
            var row = Ui.Row(); row.HorizontalAlignment = HorizontalAlignment.Center;
            row.Children.Add(new Border { Background = Painting.Brush(Painting.Palette[i]), BorderBrush = Brushes.Gray, BorderThickness = new Thickness(.5), Width = 9, Height = 9, CornerRadius = new CornerRadius(5), Margin = new Thickness(0, 0, 4, 0) });
            row.Children.Add(new TextBlock { Text = name }); button.Content = row; colors.Add(button); Ui.Add(colorGrid, button, i);
        }
        content.Children.Add(colorGrid);
        var penGrid = Ui.EqualRow(5); Ui.Add(penGrid, new TextBlock { Text = "粗細", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4) }, 0);
        for (int i = 0; i < 4; i++) { double value = new[] { 2d, 4, 8, 12 }[i]; var button = Ui.Button(value.ToString(), () => { owner.UpdateSettings(s => s.PenWidth = value); Sync(); }); widths.Add(button); Ui.Add(penGrid, button, i + 1); }
        content.Children.Add(penGrid);
        var history = Ui.EqualRow(3); undo = Ui.Button("復原", owner.Undo); redo = Ui.Button("重做", owner.Redo);
        Ui.Add(history, undo, 0); Ui.Add(history, redo, 1); Ui.Add(history, Ui.Button("清除", owner.ClearDrawing), 2); content.Children.Add(history);
        var actions = Ui.EqualRow(2); spot = Ui.Button("聚光燈", owner.ToggleSpotlight); Ui.Add(actions, spot, 0); Ui.Add(actions, Ui.Button("結束講解", owner.EndLesson), 1); content.Children.Add(actions);
        hint = new TextBlock { FontSize = 11, Foreground = Brushes.DimGray, Margin = new Thickness(3, 6, 0, 0) }; content.Children.Add(hint);
        panel.Content = new Border { Background = Painting.Brush(Color.FromRgb(245, 247, 250)), BorderBrush = Painting.Brush(Color.FromRgb(190, 200, 214)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(14), Child = content };
        ((FrameworkElement)panel.Content).Measure(new Size(320, double.PositiveInfinity));
        panel.Height = Math.Ceiling(((FrameworkElement)panel.Content).DesiredSize.Height);
        panel.PreviewKeyDown += (_, e) => { if (!owner.KeyboardHookAvailable && e.Key == Key.Escape) e.Handled = owner.HandleKey(new(0x1B, true, e.IsRepeat, 0)); };
        panel.PreviewKeyUp += (_, e) => { if (!owner.KeyboardHookAvailable && e.Key == Key.Escape) e.Handled = owner.HandleKey(new(0x1B, false, false, 0)); };
        ball.Show(); Displays.Place(ball, display, ballArea); Sync();
    }
    Position LocalCursor() { var p = display.Local(Native.Cursor()); return new(p.X, p.Y); }
    static Window CreateWindow(string title, double width, double height, bool noActivate) {
        var window = new Window { Title = title, Width = width, Height = height, WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, AllowsTransparency = true, Background = Brushes.Transparent, ShowInTaskbar = false, Topmost = true, ShowActivated = false };
        window.SourceInitialized += (_, _) => {
            nint h = new WindowInteropHelper(window).Handle;
            long style = Native.GetWindowLong(h, Native.ExStyle).ToInt64() | Native.ToolWindow;
            if (noActivate) style |= Native.NoActivate;
            Native.SetWindowLong(h, Native.ExStyle, new nint(style));
        };
        return window;
    }
    public bool Contains(Position point) => (ball.IsVisible && Native.Contains(new WindowInteropHelper(ball).Handle, point)) || (Expanded && panel.IsVisible && Native.Contains(new WindowInteropHelper(panel).Handle, point));
    public void Toggle() { if (Expanded) Collapse(); else Expand(); }
    public void Expand() {
        if (disposed || owner.State.Paused || !owner.State.Frozen) return;
        Expanded = true; Sync(); panel.Show(); Displays.Place(panel, display, FloatingLayout.Panel(ballArea, display.Width, display.Height, panel.Height), true); panel.Activate();
        owner.RefreshOverlays(); BringForward();
    }
    public void Collapse() {
        if (disposed) return;
        Expanded = false; panel.Hide(); owner.RefreshOverlays(); owner.FrozenOverlay?.Focus();
    }
    public void BringForward() {
        if (disposed) return;
        if (Expanded) Displays.Place(panel, display, FloatingLayout.Panel(ballArea, display.Width, display.Height, panel.Height));
        Displays.Place(ball, display, ballArea);
    }
    public void Sync() {
        for (int i = 0; i < tools.Count; i++) Ui.Selected(tools[i], (int)owner.Tool == i);
        for (int i = 0; i < colors.Count; i++) Ui.Selected(colors[i], owner.ColorIndex == i);
        for (int i = 0; i < widths.Count; i++) Ui.Selected(widths[i], owner.Settings.PenWidth == new[] { 2d, 4, 8, 12 }[i]);
        undo.IsEnabled = owner.FrozenOverlay?.Canvas.History.CanUndo == true; redo.IsEnabled = owner.FrozenOverlay?.Canvas.History.CanRedo == true;
        Ui.Selected(spot, owner.State.Spotlight); hint.Text = $"長按 Esc {owner.Settings.EscapeSeconds:0.##} 秒結束講解"; ballGraphic.InvalidateVisual();
    }
    public void Dispose() { if (disposed) return; disposed = true; Expanded = false; ball.Close(); panel.Close(); }
    sealed class BallGraphic(Controller owner) : FrameworkElement {
        protected override void OnRender(DrawingContext context) {
            context.DrawEllipse(Brushes.White, Painting.Pen(Painting.Parse(owner.Settings.BorderColor), 2), new(22, 22), 21, 21);
            context.DrawEllipse(null, Painting.Pen(Colors.Black, 1), new(21, 21), 10, 10);
            context.DrawEllipse(null, Painting.Pen(Colors.Black, 1), new(21, 21), 6, 6); Painting.Cursor(context, new(23, 23), 16);
        }
    }
}
