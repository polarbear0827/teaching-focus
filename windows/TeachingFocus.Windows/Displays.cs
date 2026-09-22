using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace TeachingFocus.Windows;

internal sealed record DisplayInfo(string Id, Drawing.Rectangle Bounds, double Scale) {
    public double Width => Bounds.Width / Scale;
    public double Height => Bounds.Height / Scale;
    public bool Contains(Position position) => position.X >= Bounds.Left && position.X < Bounds.Right && position.Y >= Bounds.Top && position.Y < Bounds.Bottom;
    public Point Local(Position position) => new((position.X - Bounds.Left) / Scale, (position.Y - Bounds.Top) / Scale);
    public (int X, int Y, int Width, int Height) Physical(Area area) => (
        Bounds.Left + (int)Math.Round(area.X * Scale), Bounds.Top + (int)Math.Round(area.Y * Scale),
        Math.Max(1, (int)Math.Round(area.Width * Scale)), Math.Max(1, (int)Math.Round(area.Height * Scale)));
}
internal static class Displays {
    public static List<DisplayInfo> Read() {
        var result = new List<DisplayInfo>();
        foreach (var screen in Forms.Screen.AllScreens.GroupBy(s => s.Bounds).Select(g => g.First())) {
            var device = new Native.DisplayDevice { Size = Marshal.SizeOf<Native.DisplayDevice>(), Name = "", Description = "", Id = "", Registry = "" };
            bool found = Native.EnumDisplayDevicesW(screen.DeviceName, 0, ref device, 1);
            string id = found && !string.IsNullOrWhiteSpace(device.Id) ? device.Id : screen.DeviceName;
            var monitor = Native.MonitorFromPoint(new Native.POINT { X = screen.Bounds.Left + screen.Bounds.Width / 2, Y = screen.Bounds.Top + screen.Bounds.Height / 2 }, 2);
            double scale = Native.GetDpiForMonitor(monitor, 0, out var dpi, out _) == 0 ? Math.Max(1, dpi / 96d) : 1;
            result.Add(new(id, screen.Bounds, scale));
        }
        return result;
    }
    public static BitmapSource Capture(DisplayInfo display) {
        using var image = new Drawing.Bitmap(display.Bounds.Width, display.Bounds.Height, Drawing.Imaging.PixelFormat.Format32bppRgb);
        using (var graphics = Drawing.Graphics.FromImage(image)) graphics.CopyFromScreen(display.Bounds.Location, Drawing.Point.Empty, display.Bounds.Size, Drawing.CopyPixelOperation.SourceCopy);
        nint bitmap = image.GetHbitmap();
        try {
            var source = Imaging.CreateBitmapSourceFromHBitmap(bitmap, 0, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions()); source.Freeze(); return source;
        } finally { Native.DeleteObject(bitmap); }
    }
    public static void Place(Window window, DisplayInfo display, Area local, bool activate = false) {
        var (x, y, w, h) = display.Physical(local);
        nint handle = new WindowInteropHelper(window).EnsureHandle();
        Native.SetWindowPos(handle, Native.Topmost, x, y, w, h, Native.NoOwnerZOrder | (activate ? 0u : Native.NoActivatePosition));
    }
}
