using System.IO.Pipes;
using System.Security.Principal;
using System.Text;

namespace TeachingFocus.Windows;

internal static class Program {
    [STAThread]
    static void Main() {
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 19045)) { MessageBox.Show("TeachingFocus 需要 Windows 10 22H2 或 Windows 11（x64）。", "TeachingFocus"); return; }
        Native.SetProcessDpiAwarenessContext(new nint(-4));
        string identity = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
        string pipeName = "TeachingFocus-" + identity + "-" + Process.GetCurrentProcess().SessionId;
        using var mutex = new Mutex(true, @"Local\" + pipeName, out bool first);
        if (!first) {
            try { using var client = new NamedPipeClientStream(".", pipeName, PipeDirection.Out); client.Connect(2000); client.Write(Encoding.UTF8.GetBytes("settings\n")); client.Flush(); }
            catch (Exception e) when (e is IOException or TimeoutException or UnauthorizedAccessException) { MessageBox.Show("TeachingFocus 已在通知區執行。請從右下角圖示開啟設定。", "TeachingFocus"); }
            return;
        }
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        using var cancellation = new CancellationTokenSource();
        Controller? controller = null;
        app.Startup += (_, _) => {
            try { controller = new Controller(app.Dispatcher); _ = Listen(pipeName, app.Dispatcher, () => controller?.OpenSettings(), cancellation.Token); }
            catch (Exception error) { MessageBox.Show("TeachingFocus 無法啟動：" + error.Message, "TeachingFocus", MessageBoxButton.OK, MessageBoxImage.Error); controller?.Dispose(); app.Shutdown(1); }
        };
        app.DispatcherUnhandledException += (_, e) => {
            e.Handled = true; controller?.Dispose(); MessageBox.Show("TeachingFocus 已停止並移除覆蓋視窗：" + e.Exception.Message, "TeachingFocus", MessageBoxButton.OK, MessageBoxImage.Error); app.Shutdown(1);
        };
        app.Exit += (_, _) => { cancellation.Cancel(); controller?.Dispose(); };
        try { app.Run(); } finally { mutex.ReleaseMutex(); }
    }
    static async Task Listen(string name, Dispatcher dispatcher, Action show, CancellationToken token) {
        while (!token.IsCancellationRequested) {
            try {
                using var server = new NamedPipeServerStream(name, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await server.WaitForConnectionAsync(token);
                var buffer = new byte[32];
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token); timeout.CancelAfter(2000);
                int length = await server.ReadAsync(buffer, timeout.Token);
                if (Encoding.UTF8.GetString(buffer, 0, length).StartsWith("settings", StringComparison.Ordinal)) _ = dispatcher.BeginInvoke(show);
            } catch (OperationCanceledException) { if (token.IsCancellationRequested) return; }
            catch (IOException) { await Task.Delay(500, token).ConfigureAwait(false); }
        }
    }
}
