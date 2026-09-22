namespace TeachingFocus.Windows;

internal sealed class RecorderWindow : Window {
    readonly Controller owner;
    readonly Command command;
    readonly TextBlock combination, message;
    readonly Button save;
    Shortcut? candidate;
    public RecorderWindow(Controller owner, Command command) {
        this.owner = owner; this.command = command;
        Title = command == Command.Freeze ? "錄製凍結快捷鍵" : "錄製聚光燈快捷鍵";
        Width = 490; Height = 260; ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterOwner; Topmost = true; ShowInTaskbar = false;
        Background = Painting.Brush(Color.FromRgb(247, 249, 252)); Foreground = Ui.Ink; FontFamily = new FontFamily("Microsoft JhengHei UI");
        var stack = new StackPanel { Margin = new Thickness(20) }; Content = stack;
        combination = new TextBlock { Text = "請按下想使用的快捷鍵…", FontSize = 22, TextAlignment = TextAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        stack.Children.Add(new Border { Height = 66, BorderBrush = Brushes.DodgerBlue, BorderThickness = new Thickness(2), CornerRadius = new CornerRadius(10), Background = Brushes.White, Child = combination });
        message = new TextBlock { Text = "Ctrl 或 Alt 搭配字母、數字或 F1–F11，可加 Shift。按 Esc 取消。", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 12), MinHeight = 34 }; stack.Children.Add(message);
        var actions = Ui.Row(); actions.HorizontalAlignment = HorizontalAlignment.Right;
        actions.Children.Add(Ui.Button("取消", Close)); save = Ui.Button("儲存", Save); save.IsEnabled = false; actions.Children.Add(save); stack.Children.Add(actions);
        PreviewKeyDown += Record;
    }
    void Record(object sender, KeyEventArgs e) {
        Key key = e.Key == Key.System ? e.SystemKey : e.Key; e.Handled = true;
        if (key == Key.Escape) { Close(); return; }
        if (e.IsRepeat) return;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin) return;
        var keyboard = Keyboard.Modifiers;
        Modifiers modifiers = 0;
        if (keyboard.HasFlag(ModifierKeys.Control)) modifiers |= Modifiers.Control;
        if (keyboard.HasFlag(ModifierKeys.Alt)) modifiers |= Modifiers.Alt;
        if (keyboard.HasFlag(ModifierKeys.Shift)) modifiers |= Modifiers.Shift;
        if (keyboard.HasFlag(ModifierKeys.Windows)) modifiers |= Modifiers.Windows;
        var next = new Shortcut(modifiers, KeyInterop.VirtualKeyFromKey(key)); combination.Text = next.ToString();
        string? error = next.ValidationError();
        var other = command == Command.Freeze ? owner.Settings.SpotlightShortcut : owner.Settings.FreezeShortcut;
        if (next == other) error = "與另一個功能重複，請換一組。";
        if (error != null) { candidate = null; save.IsEnabled = false; message.Text = error; return; }
        candidate = next; save.IsEnabled = true; message.Text = "已錄製。按「儲存」套用，或繼續按鍵重新錄製。";
    }
    void Save() {
        if (candidate is not Shortcut value) return;
        if (!owner.ApplyShortcut(command, value, out var error)) { message.Text = error; return; }
        Close();
    }
}
