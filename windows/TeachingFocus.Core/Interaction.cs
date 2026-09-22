namespace TeachingFocus.Core;

[Flags]
public enum Modifiers : uint { None = 0, Alt = 1, Control = 2, Shift = 4, Windows = 8 }
public enum Command { Spotlight, Freeze }
public readonly record struct Shortcut(Modifiers Modifiers, int Key) {
    public string? ValidationError() {
        if ((Modifiers & Modifiers.Windows) != 0) return "Windows 鍵組合保留給系統，請改用 Ctrl、Alt 或 Shift。";
        if ((Modifiers & ~(Modifiers.Control | Modifiers.Alt | Modifiers.Shift)) != 0 || (Modifiers & (Modifiers.Control | Modifiers.Alt)) == 0)
            return "請至少搭配 Ctrl 或 Alt，也可以加上 Shift。";
        if (Key == 0x7B) return "F12 保留給系統偵錯器，請選其他按鍵。";
        if (!((Key >= 0x30 && Key <= 0x39) || (Key >= 0x41 && Key <= 0x5A) || (Key >= 0x70 && Key <= 0x7A)))
            return "請搭配字母、數字或 F1–F11；Esc 用來取消錄製。";
        if (Key == 0x73 && (Modifiers & Modifiers.Alt) != 0) return "Alt＋F4 是系統關閉視窗快捷鍵，請選其他組合。";
        return null;
    }
    public override string ToString() {
        var parts = new List<string>();
        if (Modifiers.HasFlag(Modifiers.Control)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(Modifiers.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(Modifiers.Shift)) parts.Add("Shift");
        if (Modifiers.HasFlag(Modifiers.Windows)) parts.Add("Win");
        parts.Add(Key >= 0x70 && Key <= 0x7B ? $"F{Key - 0x6F}" : ((char)Key).ToString());
        return string.Join(" + ", parts);
    }
}

public sealed class DoubleControl {
    double? down, previous;
    bool blocked;
    public void Reset() { down = previous = null; blocked = false; }
    public void Invalidate() { down = previous = null; blocked = true; }
    public bool Change(bool pressed, bool clean, double now) {
        if (!clean) { Invalidate(); if (!pressed) blocked = false; return false; }
        if (blocked) { if (!pressed) blocked = false; return false; }
        if (pressed) { down ??= now; return false; }
        if (down is not double start) return false;
        down = null;
        if (now - start > .35) { previous = null; return false; }
        if (previous is double last && now - last <= .35) { previous = null; return true; }
        previous = now;
        return false;
    }
}

public sealed class EscapeHold {
    double? started;
    bool consumed, fired;
    double duration = 3;
    public bool Holding => started != null;
    public double Progress(double now) => started is double start ? Math.Clamp((now - start) / duration, 0, 1) : 0;
    public bool KeyDown(bool lessonActive, double now, double seconds = 3) {
        if (!lessonActive && !consumed) return false;
        consumed = true;
        if (lessonActive && !fired && started == null) { started = now; duration = double.IsFinite(seconds) ? Math.Clamp(seconds, .5, 10) : 3; }
        return true;
    }
    public bool KeyUp() { bool wasConsumed = consumed; Reset(); return wasConsumed; }
    public bool Tick(double now) {
        if (started == null || fired || Progress(now) < 1) return false;
        fired = true; started = null;
        return true;
    }
    // Preserve ownership of the current key press after exiting; eat repeats until key-up.
    public void EndLesson() { started = null; fired = consumed; }
    public void Reset() { started = null; consumed = fired = false; }
}

public sealed class SessionState {
    public bool Paused { get; private set; }
    public bool Spotlight { get; private set; }
    public bool Frozen { get; private set; }
    public bool Capturing { get; private set; }
    int generation;
    public bool LessonActive => !Paused && (Spotlight || Frozen);
    public void ToggleSpotlight() { if (!Paused) Spotlight = !Spotlight; }
    public int? BeginCapture() { if (Paused || Frozen || Capturing) return null; Capturing = true; return ++generation; }
    public bool IsCurrentCapture(int token) => token == generation && Capturing && !Paused;
    public bool FinishCapture(int token, bool success) {
        if (token != generation || !Capturing || Paused) return false;
        Capturing = false; Frozen = success; return success;
    }
    public void EndLesson() { ++generation; Capturing = Frozen = Spotlight = false; }
    public void Pause() { EndLesson(); Paused = true; }
    public void Resume() { Paused = false; }
}

public sealed class History<T> {
    readonly List<T> items = []; readonly Stack<T> redo = [];
    public IReadOnlyList<T> Items => items;
    public bool CanUndo => items.Count > 0;
    public bool CanRedo => redo.Count > 0;
    public void Add(T value) { items.Add(value); redo.Clear(); }
    public void Undo() { if (items.Count > 0) { redo.Push(items[^1]); items.RemoveAt(items.Count - 1); } }
    public void Redo() { if (redo.TryPop(out var item)) items.Add(item); }
    public void Clear() { items.Clear(); redo.Clear(); }
}

public static class Coordinates {
    public static (double X, double Y) Local(double x, double y, double left, double top, double scaleX, double scaleY) {
        if (scaleX <= 0 || scaleY <= 0) throw new ArgumentOutOfRangeException(nameof(scaleX));
        return ((x - left) / scaleX, (y - top) / scaleY);
    }
}
