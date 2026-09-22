using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace TeachingFocus.Windows;

internal readonly record struct KeyInput(int Key, bool Down, bool Repeat, Modifiers Modifiers);
internal readonly record struct MouseInput(int Button, bool Down, bool Up, bool Move, Position Point);

internal sealed class InputService : IDisposable {
    readonly Native.Hook keyboardCallback, mouseCallback;
    readonly HwndSource source;
    readonly HashSet<int> pressed = [];
    readonly List<int> ids = [];
    Dictionary<Command, Shortcut> bindings = [];
    nint keyboard, mouse;
    int nextId = 100;
    readonly Dictionary<int, Command> commands = [];
    public Func<KeyInput, bool>? Key;
    public Func<MouseInput, bool>? Mouse;
    public Action<Command>? CommandPressed;
    public Action<string>? Fault;
    public bool KeyboardAvailable => keyboard != 0;
    public string? HookError { get; private set; }
    public string? ShortcutError { get; private set; }
    public InputService() {
        source = new HwndSource(new HwndSourceParameters("TeachingFocus hotkeys") { ParentWindow = new nint(-3), WindowStyle = 0, Width = 0, Height = 0 });
        source.AddHook(WindowMessage);
        keyboardCallback = KeyboardHook; mouseCallback = MouseHook;
    }
    public void StartHooks() {
        StopHooks(); HookError = null;
        foreach (int key in new[] { 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C }) if ((Native.GetAsyncKeyState(key) & 0x8000) != 0) pressed.Add(key);
        keyboard = Native.SetWindowsHookExW(13, keyboardCallback, Native.GetModuleHandleW(null), 0);
        int keyboardError = keyboard == 0 ? Marshal.GetLastWin32Error() : 0;
        mouse = Native.SetWindowsHookExW(14, mouseCallback, Native.GetModuleHandleW(null), 0);
        int mouseError = mouse == 0 ? Marshal.GetLastWin32Error() : 0;
        if (keyboard == 0 || mouse == 0) HookError = $"輸入監聽未完整啟動（鍵盤 {keyboardError}、滑鼠 {mouseError}）。可暫停後再繼續重試。";
    }
    public void StopHooks() {
        if (keyboard != 0) Native.UnhookWindowsHookEx(keyboard);
        if (mouse != 0) Native.UnhookWindowsHookEx(mouse);
        keyboard = mouse = 0; pressed.Clear();
    }
    public void SuspendHotkeys() { foreach (int id in ids) Native.UnregisterHotKey(source.Handle, id); ids.Clear(); commands.Clear(); }
    bool Register(Dictionary<Command, Shortcut> pair, out string? error) {
        foreach (var (command, shortcut) in pair) {
            int id = ++nextId;
            if (nextId >= 0xBFFE) nextId = 100;
            if (!Native.RegisterHotKey(source.Handle, id, (uint)shortcut.Modifiers | 0x4000, (uint)shortcut.Key)) {
                error = $"{shortcut} 無法註冊，可能已被其他程式占用（{Marshal.GetLastWin32Error()}）。";
                SuspendHotkeys(); return false;
            }
            ids.Add(id); commands[id] = command;
        }
        error = null; return true;
    }
    public bool TrySetHotkeys(Settings settings, out string? error) {
        var candidate = new Dictionary<Command, Shortcut> { [Command.Spotlight] = settings.SpotlightShortcut, [Command.Freeze] = settings.FreezeShortcut };
        if (candidate.Values.Distinct().Count() != 2) { error = "兩項功能不可使用同一組快捷鍵。"; return false; }
        foreach (var value in candidate.Values) if ((error = value.ValidationError()) != null) return false;
        var previous = new Dictionary<Command, Shortcut>(bindings);
        SuspendHotkeys();
        if (Register(candidate, out error)) { bindings = candidate; ShortcutError = null; return true; }
        ShortcutError = error;
        if (previous.Count > 0 && !Register(previous, out var restoreError)) ShortcutError += " 原快捷鍵也未恢復：" + restoreError;
        return false;
    }
    public void Stop() { StopHooks(); SuspendHotkeys(); }
    nint WindowMessage(nint window, int message, nint w, nint l, ref bool handled) {
        if (message == 0x312 && commands.TryGetValue((int)w, out var command)) {
            handled = true;
            Application.Current.Dispatcher.BeginInvoke(() => CommandPressed?.Invoke(command));
        }
        return 0;
    }
    Modifiers CurrentModifiers() {
        Modifiers value = 0;
        if (pressed.Overlaps([0x11, 0xA2, 0xA3])) value |= Modifiers.Control;
        if (pressed.Overlaps([0x12, 0xA4, 0xA5])) value |= Modifiers.Alt;
        if (pressed.Overlaps([0x10, 0xA0, 0xA1])) value |= Modifiers.Shift;
        if (pressed.Overlaps([0x5B, 0x5C])) value |= Modifiers.Windows;
        return value;
    }
    nint KeyboardHook(int code, nint message, nint pointer) {
        if (code >= 0 && ((int)message is 0x100 or 0x101 or 0x104 or 0x105)) {
            try {
                var data = Marshal.PtrToStructure<Native.KeyboardData>(pointer);
                bool down = (int)message is 0x100 or 0x104;
                bool repeat = down && pressed.Contains((int)data.Key);
                if (down) pressed.Add((int)data.Key); else pressed.Remove((int)data.Key);
                if (Key?.Invoke(new((int)data.Key, down, repeat, CurrentModifiers())) == true) return 1;
            } catch (Exception error) { Application.Current.Dispatcher.BeginInvoke(() => Fault?.Invoke("鍵盤監聽發生問題：" + error.Message)); }
        }
        return Native.CallNextHookEx(keyboard, code, message, pointer);
    }
    nint MouseHook(int code, nint message, nint pointer) {
        if (code >= 0) {
            int msg = (int)message;
            if (msg is 0x200 or 0x201 or 0x202 or 0x204 or 0x205 or 0x207 or 0x208) {
                try {
                    var data = Marshal.PtrToStructure<Native.MouseData>(pointer);
                    int button = msg is 0x201 or 0x202 ? 0 : msg is 0x204 or 0x205 ? 1 : 2;
                    if (Mouse?.Invoke(new(button, msg is 0x201 or 0x204 or 0x207, msg is 0x202 or 0x205 or 0x208, msg == 0x200, new(data.Point.X, data.Point.Y))) == true) return 1;
                } catch (Exception error) { Application.Current.Dispatcher.BeginInvoke(() => Fault?.Invoke("滑鼠監聽發生問題：" + error.Message)); }
            }
        }
        return Native.CallNextHookEx(mouse, code, message, pointer);
    }
    public void Dispose() { Stop(); source.RemoveHook(WindowMessage); source.Dispose(); }
}
