using System.Globalization;

namespace TeachingFocus.Windows;

internal enum PaintTool { Pen, Line, Arrow, Rectangle, Ellipse, Laser }
internal sealed class Stroke(PaintTool tool, Color color, double width, Point first) {
    public PaintTool Tool { get; } = tool;
    public Color Color { get; } = color;
    public double Width { get; } = width;
    public List<Point> Points { get; } = [first];
    public double Born { get; set; }
}
internal static class Painting {
    public static readonly Color[] Palette = [Colors.Red, Colors.DodgerBlue, Colors.LimeGreen, Colors.Black, Colors.White];
    public static Color Parse(string hex) => (Color)ColorConverter.ConvertFromString(hex);
    public static SolidColorBrush Brush(Color color, double opacity = 1) { var brush = new SolidColorBrush(color) { Opacity = Math.Clamp(opacity, 0, 1) }; brush.Freeze(); return brush; }
    public static Pen Pen(Color color, double width, double opacity = 1) {
        var pen = new Pen(Brush(color, opacity), width) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round }; pen.Freeze(); return pen;
    }
    public static void Stroke(DrawingContext context, Stroke stroke, double opacity = 1) {
        if (stroke.Points.Count == 0) return;
        Point first = stroke.Points[0], last = stroke.Points[^1];
        var pen = Pen(stroke.Color, stroke.Width, opacity);
        switch (stroke.Tool) {
            case PaintTool.Rectangle: context.DrawRectangle(null, pen, new Rect(first, last)); break;
            case PaintTool.Ellipse: context.DrawEllipse(null, pen, new Point((first.X + last.X) / 2, (first.Y + last.Y) / 2), Math.Abs(last.X - first.X) / 2, Math.Abs(last.Y - first.Y) / 2); break;
            case PaintTool.Line:
            case PaintTool.Arrow:
                context.DrawLine(pen, first, last);
                if (stroke.Tool == PaintTool.Arrow) {
                    double angle = Math.Atan2(last.Y - first.Y, last.X - first.X), length = Math.Max(15, stroke.Width * 4);
                    foreach (double offset in new[] { -.5, .5 }) context.DrawLine(pen, last, new(last.X - length * Math.Cos(angle + offset), last.Y - length * Math.Sin(angle + offset)));
                }
                break;
            default:
                if (stroke.Points.Count == 1) { context.DrawEllipse(Brush(stroke.Color, opacity), null, first, stroke.Width / 2, stroke.Width / 2); break; }
                var path = new StreamGeometry();
                using (var drawing = path.Open()) { drawing.BeginFigure(first, false, false); drawing.PolyLineTo(stroke.Points.Skip(1).ToArray(), true, false); }
                path.Freeze(); context.DrawGeometry(null, pen, path); break;
        }
    }
    public static void GlowRing(DrawingContext context, Point center, double radius, Color color, double width, double glow, double opacity) {
        for (int i = 4; i >= 1; i--) context.DrawEllipse(null, Pen(color, width + glow * i / 2, opacity * .025), center, radius, radius);
        context.DrawEllipse(null, Pen(color, width, opacity), center, radius, radius);
    }
    public static void Particles(DrawingContext context, IEnumerable<Burst> bursts, string displayId, Color color, double now) {
        foreach (var burst in bursts.Where(b => b.DisplayId == displayId)) foreach (var particle in burst.Sample(now)) {
            var center = new Point(particle.Position.X, particle.Position.Y);
            switch (burst.Kind) {
                case ParticleKind.Dots: context.DrawEllipse(Brush(color, particle.Opacity), null, center, particle.Size, particle.Size); break;
                case ParticleKind.Sparks:
                    context.DrawLine(Pen(color, 1.8, particle.Opacity), center, new(center.X - Math.Cos(particle.Angle) * particle.Size * 3, center.Y - Math.Sin(particle.Angle) * particle.Size * 3)); break;
                case ParticleKind.Stars:
                    var path = new StreamGeometry();
                    using (var geometry = path.Open()) for (int i = 0; i < 8; i++) {
                        double angle = particle.Angle + i * Math.PI / 4, radius = particle.Size * (i % 2 == 0 ? 1.8 : .5);
                        Point point = new(center.X + Math.Cos(angle) * radius, center.Y + Math.Sin(angle) * radius);
                        if (i == 0) geometry.BeginFigure(point, true, true); else geometry.LineTo(point, true, false);
                    }
                    path.Freeze(); context.DrawGeometry(Brush(color, particle.Opacity), null, path); break;
            }
        }
    }
    public static void Text(DrawingContext context, string text, Point at, double size, Color color, double pixelsPerDip = 1) => context.DrawText(new FormattedText(text, CultureInfo.GetCultureInfo("zh-TW"), FlowDirection.LeftToRight, new Typeface("Microsoft JhengHei UI"), size, Brush(color), pixelsPerDip), at);
    public static void Cursor(DrawingContext context, Point center, double size = 18) {
        var path = new StreamGeometry();
        using (var geo = path.Open()) {
            geo.BeginFigure(new(center.X - size * .25, center.Y - size * .5), true, true);
            geo.LineTo(new(center.X + size * .5, center.Y + size * .05), true, false);
            geo.LineTo(new(center.X + size * .08, center.Y + size * .12), true, false);
            geo.LineTo(new(center.X - size * .2, center.Y + size * .5), true, false);
        }
        path.Freeze(); context.DrawGeometry(Brush(Colors.White), Pen(Colors.Black, 1), path);
    }
}
