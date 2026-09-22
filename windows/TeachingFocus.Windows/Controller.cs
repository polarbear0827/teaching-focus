using Microsoft.Win32;
using System.Windows.Interop;
using Forms = System.Windows.Forms;
using Drawing = System.Drawing;

namespace TeachingFocus.Windows;

internal sealed record Ripple(string DisplayId, Point Point, double Born);
internal sealed class Controller : IDisposable {
    public static double Now => Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency;
    public Settings Settings { get; private set; }
    public SessionState State { get; } = new();
    public EscapeHold Escape { get; } = new();
    public BurstBuffer Particles { get; } = new();
    public List<Ripple> Ripples { get; } = [];
    public Position Cursor { get; private set; }
    public PaintTool Tool { get; set; }
    public int ColorIndex { get; set; }
    public FloatingTools? Floating { get; private set; }
    public OverlayWindow? FrozenOverlay => overlays.FirstOrDefault(x => x.Canvas.Snapshot != null);
    public bool KeyboardHookAvailable => input.KeyboardAvailable;
    public bool Recording { get; private set; }
    public bool ColorDialogOpen { get; set; }
    public bool ReduceMotion => !SystemParameters.ClientAreaAnimation;
    public event Action? SettingsChanged, StateChanged;
    readonly SettingsStore store = new();
    readonly InputService input = new();
    readonly DoubleControl doubleControl = new();
    readonly HashSet<int> suppressedButtons = [];
    readonly List<OverlayWindow> overlays = [];
    readonly Forms.NotifyIcon tray;
    readonly Forms.ContextMenuStrip menu;
    readonly Forms.ToolStripMenuItem pauseItem;
    readonly DispatcherTimer frameTimer, saveTimer, displayTimer;
    readonly Dispatcher dispatcher;
    SettingsWindow? settingsWindow;
    RecorderWindow? recorder;
    Drawing.Icon? trayImage;
    nint previousExternal;
    double entranceStart, entranceDuration = .25, nextHealth;
    bool dirtySettings, disposed, lastAnimating, sleeping, sessionLocked;
    string? error;
    public (double Scale, double Opacity, bool Active) Entrance => FocusAnimation.Sample(Now, entranceStart, entranceDuration, ReduceMotion || !Settings.Animate);
    public string Status => State.Paused ? "已暫停：效果與快捷鍵均停止。" : error ?? input.ShortcutError ?? input.HookError ?? "輸入監聽已啟動。雙按 Ctrl 或使用自訂快捷鍵。";
    public Controller(Dispatcher dispatcher) {
        this.dispatcher = dispatcher; Settings = store.Load(); error = store.Warning;
        input.Key = HandleKey; input.Mouse = HandleMouse;
        input.CommandPressed = command => { if (State.Paused || Recording) return; if (command == Command.Spotlight) ToggleSpotlight(); else _ = FreezeAsync(); };
        input.Fault = message => { if (disposed) return; error = message; Pause(); };
        menu = new Forms.ContextMenuStrip();
        menu.Items.Add("聚光燈", null, (_, _) => ToggleSpotlight());
        menu.Items.Add("凍結與畫筆", null, (_, _) => _ = FreezeAsync());
        menu.Items.Add("結束講解", null, (_, _) => EndLesson());
        menu.Items.Add(new Forms.ToolStripSeparator());
        pauseItem = new("暫停（清除畫布）", null, (_, _) => TogglePause()); menu.Items.Add(pauseItem);
        menu.Items.Add("設定…", null, (_, _) => OpenSettings());
        menu.Items.Add(new Forms.ToolStripSeparator()); menu.Items.Add("結束工具", null, (_, _) => Quit());
        tray = new Forms.NotifyIcon { ContextMenuStrip = menu, Text = "TeachingFocus 教學聚光燈", Visible = false };
        tray.DoubleClick += (_, _) => OpenSettings(); SetTrayIcon(); tray.Visible = true;
        frameTimer = new DispatcherTimer(DispatcherPriority.Render, dispatcher) { Interval = TimeSpan.FromMilliseconds(16) }; frameTimer.Tick += (_, _) => Tick();
        saveTimer = new DispatcherTimer(DispatcherPriority.Background, dispatcher) { Interval = TimeSpan.FromMilliseconds(350) }; saveTimer.Tick += (_, _) => FlushSettings();
        displayTimer = new DispatcherTimer(DispatcherPriority.Background, dispatcher) { Interval = TimeSpan.FromMilliseconds(150) };
        displayTimer.Tick += (_, _) => { displayTimer.Stop(); if (disposed) return; EndLesson(); RebuildOverlays(); };
        RebuildOverlays(); StartInput(); frameTimer.Start();
        SystemEvents.DisplaySettingsChanged += DisplayChanged;
        SystemEvents.PowerModeChanged += PowerChanged;
        SystemEvents.SessionSwitch += SessionChanged;
        OpenSettings();
    }
    void StartInput() { input.StartHooks(); input.TrySetHotkeys(Settings, out _); StateChanged?.Invoke(); }
    void SetTrayIcon() {
        using var bitmap = new Drawing.Bitmap(32, 32);
        using (var g = Drawing.Graphics.FromImage(bitmap)) {
            g.SmoothingMode = Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using var pen = new Drawing.Pen(State.Paused ? Drawing.Color.Gray : Drawing.Color.FromArgb(0, 184, 230), 2);
            g.DrawEllipse(pen, 3, 3, 24, 24); g.DrawEllipse(pen, 8, 8, 14, 14);
            Drawing.PointF[] arrow = [new(15, 9), new(29, 20), new(23, 21), new(20, 29), new(16, 27), new(19, 20), new(14, 21)];
            using var outline = new Drawing.Pen(Drawing.Color.White, 3); g.DrawPolygon(outline, arrow); g.FillPolygon(Drawing.Brushes.Black, arrow);
        }
        nint handle = bitmap.GetHicon();
        try { using var temporary = Drawing.Icon.FromHandle(handle); var icon = (Drawing.Icon)temporary.Clone(); tray.Icon = icon; trayImage?.Dispose(); trayImage = icon; }
        finally { Native.DestroyIcon(handle); }
        tray.Text = State.Paused ? "TeachingFocus：已暫停" : "TeachingFocus 教學聚光燈";
    }
    public void OpenSettings() {
        if (disposed) return;
        Floating?.Collapse();
        if (settingsWindow == null) { settingsWindow = new(this); settingsWindow.Closed += (_, _) => settingsWindow = null; }
        settingsWindow.Show(); settingsWindow.WindowState = WindowState.Normal; settingsWindow.Activate();
    }
    public void ToggleSpotlight() {
        if (disposed || State.Paused || Recording || sleeping || sessionLocked) return;
        State.ToggleSpotlight();
        if (State.Spotlight) { entranceStart = Now; entranceDuration = Settings.AnimationSeconds; }
        else if (!State.LessonActive) Escape.EndLesson();
        InvalidateAll(); SyncTools();
    }
    public async Task FreezeAsync() {
        if (disposed || Recording || sleeping || sessionLocked) return;
        int? token = State.BeginCapture(); if (token == null) return;
        var display = overlays.FirstOrDefault(x => x.Display.Contains(Native.Cursor()))?.Display;
        if (display == null) { State.FinishCapture(token.Value, false); error = "找不到游標所在螢幕。"; StateChanged?.Invoke(); return; }
        bool restoreSettings = settingsWindow?.IsVisible == true;
        foreach (var window in overlays) window.Hide(); settingsWindow?.Hide(); Ripples.Clear(); Particles.Clear();
        try {
            await Dispatcher.Yield(DispatcherPriority.Render); Native.DwmFlush();
            var snapshot = await Task.Run(() => Displays.Capture(display)).WaitAsync(TimeSpan.FromSeconds(3));
            if (disposed || !State.IsCurrentCapture(token.Value)) return;
            var overlay = overlays.FirstOrDefault(x => x.Display.Id == display.Id);
            if (overlay == null) throw new IOException("螢幕配置已改變，請重新凍結。");
            if (!State.FinishCapture(token.Value, true)) return;
            overlay.Canvas.Clear(); overlay.Canvas.Snapshot = snapshot; overlay.Input(true); overlay.Show(); overlay.Place(); overlay.Activate(); overlay.Canvas.Focus();
            Floating?.Dispose(); Floating = new(this, display); RefreshOverlays();
        } catch (Exception captureError) {
            if (disposed || !State.IsCurrentCapture(token.Value)) return;
            State.FinishCapture(token.Value, false); error = "無法凍結畫面：" + captureError.Message;
            if (restoreSettings) OpenSettings(); else tray.ShowBalloonTip(4000, "TeachingFocus", error, Forms.ToolTipIcon.Warning);
        } finally { if (!disposed) { RefreshOverlays(); StateChanged?.Invoke(); } }
    }
    public void EndLesson() {
        State.EndLesson(); Escape.EndLesson(); Floating?.Dispose(); Floating = null;
        foreach (var window in overlays) { window.Canvas.Reset(); window.Input(false); }
        Ripples.Clear(); Particles.Clear(); InvalidateAll();
        if (previousExternal != 0 && !Native.IsOwn(previousExternal)) Native.SetForegroundWindow(previousExternal);
        StateChanged?.Invoke();
    }
    public void TogglePause() { if (State.Paused) Resume(); else Pause(); }
    void Pause() {
        State.Pause(); recorder?.Close(); Recording = false; EndLesson(); Escape.Reset(); doubleControl.Reset(); suppressedButtons.Clear(); input.Stop();
        foreach (var window in overlays) window.Hide(); pauseItem.Text = "繼續使用"; SetTrayIcon(); StateChanged?.Invoke();
    }
    void Resume() { State.Resume(); error = null; doubleControl.Reset(); StartInput(); pauseItem.Text = "暫停（清除畫布）"; SetTrayIcon(); InvalidateAll(); StateChanged?.Invoke(); }
    public void UpdateSettings(Action<Settings> update) {
        var next = Settings.Clone(); update(next); next.Normalize(); Settings = next;
        dirtySettings = true; saveTimer.Stop(); saveTimer.Start();
        if (!Settings.Particles) Particles.Clear(); if (!Settings.Ripples) Ripples.Clear(); if (!Settings.DoubleControl) doubleControl.Reset();
        InvalidateAll(); SyncTools(); SettingsChanged?.Invoke();
    }
    void FlushSettings() {
        saveTimer.Stop(); if (!dirtySettings) return;
        try { store.Save(Settings); dirtySettings = false; }
        catch (Exception saveError) when (saveError is IOException or UnauthorizedAccessException) { error = "設定寫入失敗，變更暫時只在本次執行生效：" + saveError.Message; StateChanged?.Invoke(); }
    }
    public bool ApplyShortcut(Command command, Shortcut shortcut, out string? message) {
        var next = Settings.Clone();
        if (command == Command.Freeze) next.FreezeShortcut = shortcut; else next.SpotlightShortcut = shortcut;
        return ApplyConfiguration(next, out message);
    }
    bool ApplyConfiguration(Settings next, out string? message) {
        message = next.FreezeShortcut.ValidationError() ?? next.SpotlightShortcut.ValidationError(); if (message != null) return false;
        if (next.FreezeShortcut == next.SpotlightShortcut) { message = "兩項功能不可使用同一組快捷鍵。"; return false; }
        if (!input.TrySetHotkeys(next, out message)) { if (State.Paused || Recording) input.SuspendHotkeys(); return false; }
        try { store.Save(next); }
        catch (Exception saveError) when (saveError is IOException or UnauthorizedAccessException) { input.TrySetHotkeys(Settings, out _); if (State.Paused || Recording) input.SuspendHotkeys(); message = "設定未儲存：" + saveError.Message; return false; }
        Settings = next; dirtySettings = false; saveTimer.Stop(); if (State.Paused) input.SuspendHotkeys(); error = null;
        SettingsChanged?.Invoke(); StateChanged?.Invoke(); return true;
    }
    public void RecordShortcut(Command command) {
        if (Recording) { recorder?.Activate(); return; }
        EndLesson(); Escape.Reset(); doubleControl.Reset(); Recording = true; input.SuspendHotkeys();
        recorder = new(this, command) { Owner = settingsWindow };
        try { recorder.ShowDialog(); }
        finally {
            recorder = null; Recording = false; doubleControl.Reset(); Escape.Reset();
            if (!State.Paused && !disposed) input.TrySetHotkeys(Settings, out _);
            else input.SuspendHotkeys();
            StateChanged?.Invoke();
        }
    }
    public void RestoreDefaults() {
        if (MessageBox.Show(settingsWindow, "還原顏色、大小、效果、快捷鍵及時間，並清除目前畫布？暫停狀態會保留。", "還原預設設定", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
        if (!ApplyConfiguration(new Settings(), out var message)) { error = message; StateChanged?.Invoke(); return; }
        EndLesson(); Tool = PaintTool.Pen; ColorIndex = 0; Escape.Reset(); doubleControl.Reset(); SettingsChanged?.Invoke();
    }
    public void Undo() { FrozenOverlay?.Canvas.History.Undo(); FrozenOverlay?.Canvas.InvalidateVisual(); SyncTools(); }
    public void Redo() { FrozenOverlay?.Canvas.History.Redo(); FrozenOverlay?.Canvas.InvalidateVisual(); SyncTools(); }
    public void ClearDrawing() { FrozenOverlay?.Canvas.Clear(); SyncTools(); }
    public void SyncTools() => Floating?.Sync();
    public bool HandleKey(KeyInput key) {
        if (State.Paused || Recording || sleeping || sessionLocked || disposed) return false;
        bool isControl = key.Key is 0x11 or 0xA2 or 0xA3;
        if (isControl && !key.Repeat) {
            bool control = key.Modifiers.HasFlag(Modifiers.Control);
            if (doubleControl.Change(control, (key.Modifiers & ~Modifiers.Control) == 0, Now) && Settings.DoubleControl) dispatcher.BeginInvoke(ToggleSpotlight);
        } else if (key.Down) { if (key.Modifiers.HasFlag(Modifiers.Control)) doubleControl.Invalidate(); else doubleControl.Reset(); }
        if (key.Key == 0x1B) {
            if (key.Down) {
                bool consume = Escape.KeyDown(State.LessonActive, Now, Settings.EscapeSeconds);
                if (consume && Floating?.Expanded == true) dispatcher.BeginInvoke(() => Floating?.Collapse());
                return consume;
            }
            bool result = Escape.KeyUp(); dispatcher.BeginInvoke(InvalidateAll); return result;
        }
        if (State.Frozen && key.Down) {
            if (key.Key == 0x5A && key.Modifiers.HasFlag(Modifiers.Control)) { dispatcher.BeginInvoke(key.Modifiers.HasFlag(Modifiers.Shift) ? Redo : Undo); return true; }
            if (key.Modifiers == 0 && key.Key >= 0x31 && key.Key <= 0x35) { int color = key.Key - 0x31; dispatcher.BeginInvoke(() => { ColorIndex = color; SyncTools(); }); return true; }
        }
        return false;
    }
    bool HandleMouse(MouseInput mouse) {
        if (mouse.Up && suppressedButtons.Remove(mouse.Button)) return true;
        if (mouse.Move) return suppressedButtons.Count != 0;
        if (State.Paused || Recording || sleeping || sessionLocked || disposed) return false;
        if (mouse.Down && Floating?.Expanded == true && !Floating.Contains(mouse.Point)) {
            suppressedButtons.Add(mouse.Button); dispatcher.BeginInvoke(() => Floating?.Collapse()); return true;
        }
        if (mouse.Down && mouse.Button < 2 && !State.Frozen && !State.Capturing && !OwnControlAt(mouse.Point)) {
            Position point = mouse.Point;
            dispatcher.BeginInvoke(() => {
                if (disposed || State.Paused || State.Frozen || State.Capturing || Recording) return;
                var display = overlays.FirstOrDefault(x => x.Display.Contains(point))?.Display; if (display == null) return;
                Point local = display.Local(point);
                if (Settings.Ripples) { Ripples.Add(new(display.Id, local, Now)); if (Ripples.Count > 32) Ripples.RemoveAt(0); }
                if (Settings.Particles) Particles.Add(new(new(local.X, local.Y), Now, Settings.ParticleStyle, Settings.ParticleIntensity, display.Id), ReduceMotion);
            });
        }
        return false;
    }
    bool OwnControlAt(Position point) => ColorDialogOpen || menu.Visible || (settingsWindow?.IsVisible == true && Native.Contains(new WindowInteropHelper(settingsWindow).Handle, point)) || (recorder?.IsVisible == true && Native.Contains(new WindowInteropHelper(recorder).Handle, point)) || Floating?.Contains(point) == true;
    void Tick() {
        if (disposed) return;
        if (Now >= nextHealth) { nextHealth = Now + 2; StateChanged?.Invoke(); }
        if (State.Paused || Recording || State.Capturing || sleeping || sessionLocked) return;
        nint foreground = Native.GetForegroundWindow(); if (foreground != 0 && !Native.IsOwn(foreground) && !State.Frozen) previousExternal = foreground;
        bool hadEffects = Ripples.Count > 0 || Particles.Items.Count > 0;
        Ripples.RemoveAll(x => Now - x.Born >= .6); Particles.Expire(Now); if (ReduceMotion) Particles.Clear();
        if (!State.LessonActive) Escape.EndLesson();
        if (Escape.Tick(Now)) { EndLesson(); return; }
        Position previous = Cursor; Cursor = Native.Cursor();
        bool moving = Cursor != previous, animating = State.Spotlight && Entrance.Active;
        foreach (var window in overlays) {
            bool hadLaser = window.Canvas.HasLasers; window.Canvas.Expire(Now);
            bool dirty = (moving && (State.Spotlight || Settings.Halo)) || hadEffects || hadLaser || Escape.Holding || animating || lastAnimating;
            if (dirty) window.Canvas.InvalidateVisual();
        }
        lastAnimating = animating; RefreshOverlays();
    }
    public void RefreshOverlays() {
        if (disposed) return;
        bool raised = false;
        foreach (var window in overlays) {
            bool shield = Floating?.Expanded == true || window.Canvas.SuppressedGesture;
            bool visible = !State.Paused && !Recording && !State.Capturing && !sleeping && !sessionLocked && (window.Canvas.Snapshot != null || shield || (window.Display.Contains(Cursor) && (State.Spotlight || (Settings.Halo && Settings.HaloOpacity > 0) || Escape.Holding)) || Ripples.Any(x => x.DisplayId == window.Display.Id) || Particles.Items.Any(x => x.DisplayId == window.Display.Id));
            window.Input(!State.Paused && (window.Canvas.Snapshot != null || shield));
            if (visible && !window.IsVisible) { window.Show(); window.Place(); window.Canvas.InvalidateVisual(); raised = true; }
            else if (!visible && window.IsVisible) window.Hide();
        }
        if (raised) Floating?.BringForward();
    }
    void InvalidateAll() { foreach (var window in overlays) window.Canvas.InvalidateVisual(); RefreshOverlays(); }
    void RebuildOverlays() {
        foreach (var window in overlays) window.Close(); overlays.Clear();
        foreach (var display in Displays.Read()) overlays.Add(new(this, display));
    }
    public void RequestDisplayRefresh() => dispatcher.BeginInvoke(() => { if (disposed) return; displayTimer.Stop(); displayTimer.Start(); });
    void DisplayChanged(object? sender, EventArgs e) => RequestDisplayRefresh();
    void PowerChanged(object sender, PowerModeChangedEventArgs e) => dispatcher.BeginInvoke(() => {
        if (disposed) return;
        if (e.Mode == PowerModes.Suspend) { sleeping = true; EndLesson(); RefreshOverlays(); }
        else if (e.Mode == PowerModes.Resume) { sleeping = false; if (!State.Paused) input.StartHooks(); RefreshOverlays(); }
    });
    void SessionChanged(object sender, SessionSwitchEventArgs e) => dispatcher.BeginInvoke(() => {
        if (disposed) return;
        if (e.Reason == SessionSwitchReason.SessionLock) { sessionLocked = true; EndLesson(); RefreshOverlays(); }
        else if (e.Reason == SessionSwitchReason.SessionUnlock) { sessionLocked = false; if (!State.Paused) input.StartHooks(); RefreshOverlays(); }
    });
    public void Quit() { FlushSettings(); Dispose(); Application.Current.Shutdown(); }
    public void Dispose() {
        if (disposed) return;
        disposed = true; frameTimer.Stop(); saveTimer.Stop(); displayTimer.Stop(); input.Dispose();
        SystemEvents.DisplaySettingsChanged -= DisplayChanged; SystemEvents.PowerModeChanged -= PowerChanged; SystemEvents.SessionSwitch -= SessionChanged;
        Floating?.Dispose(); Floating = null; foreach (var overlay in overlays) { overlay.Canvas.Reset(); overlay.Close(); } overlays.Clear();
        recorder?.Close(); settingsWindow?.Close(); tray.Visible = false; tray.Dispose(); trayImage?.Dispose(); menu.Dispose();
    }
}
