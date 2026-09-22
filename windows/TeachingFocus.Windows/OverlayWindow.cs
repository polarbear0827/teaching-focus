using System.Windows.Interop;
using System.Windows.Media.Imaging;

namespace TeachingFocus.Windows;

internal sealed class OverlayWindow : Window {
    public DisplayInfo Display { get; }
    public CanvasView Canvas { get; }
    public bool AcceptsInput { get; private set; }
    public nint Handle { get; private set; }
    readonly Controller owner;
    public OverlayWindow(Controller owner, DisplayInfo display) {
        this.owner = owner; Display = display;
        Title = "TeachingFocus 畫布"; Width = display.Width; Height = display.Height;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; AllowsTransparency = true;
        Background = Brushes.Transparent; ShowInTaskbar = false; Topmost = true; ShowActivated = false;
        Canvas = new(owner, this); Content = Canvas;
        SourceInitialized += (_, _) => {
            Handle = new WindowInteropHelper(this).Handle;
            Native.SetWindowLong(Handle, Native.ExStyle, new nint(Native.GetWindowLong(Handle, Native.ExStyle).ToInt64() | Native.ToolWindow | Native.Transparent | Native.NoActivate));
            HwndSource.FromHwnd(Handle)?.AddHook((nint h, int message, nint w, nint l, ref bool handled) => {
                if (message == 0x02E0 && Math.Abs(((long)w & 0xffff) / 96d - Display.Scale) > .01) owner.RequestDisplayRefresh();
                return 0;
            });
            Place();
        };
        Loaded += (_, _) => Place();
        PreviewKeyDown += (_, e) => LocalEscape(e, true);
        PreviewKeyUp += (_, e) => LocalEscape(e, false);
    }
    void LocalEscape(KeyEventArgs e, bool down) {
        if (!owner.KeyboardHookAvailable && e.Key == Key.Escape) e.Handled = owner.HandleKey(new(0x1B, down, e.IsRepeat, 0));
    }
    public void Place() => Displays.Place(this, Display, new(0, 0, Display.Width, Display.Height));
    public void Input(bool enabled) {
        if (AcceptsInput == enabled && Handle != 0) return;
        AcceptsInput = enabled;
        nint handle = new WindowInteropHelper(this).EnsureHandle();
        long style = Native.GetWindowLong(handle, Native.ExStyle).ToInt64() | Native.ToolWindow;
        style = enabled ? style & ~(Native.Transparent | Native.NoActivate) : style | Native.Transparent | Native.NoActivate;
        Native.SetWindowLong(handle, Native.ExStyle, new nint(style));
    }
}

internal sealed class CanvasView : FrameworkElement {
    readonly Controller owner;
    readonly OverlayWindow window;
    public BitmapSource? Snapshot { get; set; }
    public History<Stroke> History { get; } = new();
    public Stroke? Live { get; private set; }
    readonly List<Stroke> lasers = [];
    public bool SuppressedGesture { get; private set; }
    public bool HasLasers => lasers.Count != 0;
    public CanvasView(Controller owner, OverlayWindow window) { this.owner = owner; this.window = window; Focusable = true; ClipToBounds = true; }
    public void Clear() { History.Clear(); Live = null; lasers.Clear(); InvalidateVisual(); owner.SyncTools(); }
    public void Reset() { Snapshot = null; Clear(); SuppressedGesture = false; if (IsMouseCaptured) ReleaseMouseCapture(); }
    public void Expire(double now) { lasers.RemoveAll(x => now - x.Born >= 1); }
    protected override void OnRender(DrawingContext context) {
        base.OnRender(context);
        var size = new Rect(0, 0, ActualWidth, ActualHeight);
        // A nearly transparent surface catches the dismissal click even if the global mouse hook is unavailable.
        if (window.AcceptsInput) context.DrawRectangle(Painting.Brush(Color.FromArgb(1, 0, 0, 0)), null, size);
        if (Snapshot != null) context.DrawImage(Snapshot, size);
        foreach (var stroke in History.Items) Painting.Stroke(context, stroke);
        if (Live != null) Painting.Stroke(context, Live);
        foreach (var stroke in lasers) Painting.Stroke(context, stroke, Math.Max(0, 1 - (Controller.Now - stroke.Born)));
        var settings = owner.Settings;
        Point cursor = window.Display.Local(owner.Cursor);
        if (owner.State.Spotlight && window.Display.Contains(owner.Cursor)) {
            var transition = owner.Entrance;
            double radius = settings.Radius * transition.Scale;
            var shade = new CombinedGeometry(GeometryCombineMode.Exclude, new RectangleGeometry(size), new EllipseGeometry(cursor, radius, radius)); shade.Freeze();
            context.DrawGeometry(Painting.Brush(Colors.Black, settings.Dim * transition.Opacity), null, shade);
            if (settings.Border) Painting.GlowRing(context, cursor, radius, Painting.Parse(settings.BorderColor), settings.BorderWidth, settings.Glow, transition.Opacity);
        } else if (settings.Halo && window.Display.Contains(owner.Cursor)) context.DrawEllipse(Painting.Brush(Painting.Parse(settings.HaloColor), settings.HaloOpacity), null, cursor, settings.HaloRadius, settings.HaloRadius);
        foreach (var ripple in owner.Ripples.Where(r => r.DisplayId == window.Display.Id)) {
            double age = Controller.Now - ripple.Born;
            context.DrawEllipse(null, Painting.Pen(Colors.Cyan, 3, 1 - age / .6), ripple.Point, 12 + age * 65, 12 + age * 65);
        }
        Painting.Particles(context, owner.Particles.Items, window.Display.Id, Painting.Parse(settings.BorderColor), Controller.Now);
        if (owner.Escape.Holding && window.Display.Contains(owner.Cursor)) {
            double progress = owner.Escape.Progress(Controller.Now);
            var box = new Rect(Math.Max(0, (ActualWidth - 330) / 2), Math.Max(0, ActualHeight - 104), 330, 76);
            context.DrawRoundedRectangle(Painting.Brush(Colors.Black, .85), null, box, 12, 12);
            Painting.Text(context, $"持續按住 Esc · {settings.EscapeSeconds:0.##} 秒結束講解", new(box.X + 18, box.Y + 14), 14, Colors.White, VisualTreeHelper.GetDpi(this).PixelsPerDip);
            context.DrawRoundedRectangle(Painting.Brush(Colors.Cyan), null, new(box.X + 18, box.Y + 48, 294 * progress, 5), 2, 2);
        }
    }
    protected override void OnMouseDown(MouseButtonEventArgs e) {
        base.OnMouseDown(e);
        if (owner.Floating?.Expanded == true) {
            SuppressedGesture = true; CaptureMouse(); owner.Floating.Collapse(); e.Handled = true; return;
        }
        if (Snapshot == null || e.ChangedButton != MouseButton.Left) return;
        Focus(); CaptureMouse(); Live = new(owner.Tool, Painting.Palette[owner.ColorIndex], owner.Settings.PenWidth, e.GetPosition(this)); e.Handled = true; InvalidateVisual();
    }
    protected override void OnMouseMove(MouseEventArgs e) {
        if (Live != null && e.LeftButton == MouseButtonState.Pressed) { Live.Points.Add(e.GetPosition(this)); InvalidateVisual(); e.Handled = true; }
        if (SuppressedGesture) e.Handled = true;
        base.OnMouseMove(e);
    }
    protected override void OnMouseUp(MouseButtonEventArgs e) {
        if (SuppressedGesture) { SuppressedGesture = false; ReleaseMouseCapture(); e.Handled = true; owner.RefreshOverlays(); return; }
        if (Live != null && e.ChangedButton == MouseButton.Left) {
            Live.Points.Add(e.GetPosition(this)); Live.Born = Controller.Now;
            if (Live.Tool == PaintTool.Laser) lasers.Add(Live); else History.Add(Live);
            Live = null; ReleaseMouseCapture(); InvalidateVisual(); owner.SyncTools(); e.Handled = true;
        }
        base.OnMouseUp(e);
    }
    protected override void OnLostMouseCapture(MouseEventArgs e) { Live = null; SuppressedGesture = false; InvalidateVisual(); base.OnLostMouseCapture(e); }
}
