namespace TeachingFocus.Core;

public readonly record struct Position(double X, double Y);
public readonly record struct Area(double X, double Y, double Width, double Height) {
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public bool Contains(Position point) => point.X >= X && point.X < Right && point.Y >= Y && point.Y < Bottom;
}
public sealed record BallPosition(bool Right = true, double Fraction = .5);
public static class FloatingLayout {
    public const double Size = 44, Margin = 12;
    public static Area Ball(double width, double height, BallPosition saved) => new(
        saved.Right ? Math.Max(Margin, width - Margin - Size) : Margin,
        Margin + Math.Max(0, height - 2 * Margin - Size) * Math.Clamp(saved.Fraction, 0, 1), Size, Size);
    public static Area Clamp(Position origin, double width, double height) => new(
        Math.Clamp(origin.X, Margin, Math.Max(Margin, width - Margin - Size)),
        Math.Clamp(origin.Y, Margin, Math.Max(Margin, height - Margin - Size)), Size, Size);
    public static BallPosition Snap(Area ball, double width, double height) => new(
        ball.X + Size / 2 >= width / 2,
        Math.Clamp((ball.Y - Margin) / Math.Max(1, height - 2 * Margin - Size), 0, 1));
    public static Area Panel(Area ball, double width, double height, double requestedHeight = 300) {
        double w = Math.Min(320, Math.Max(1, width - 24)), h = Math.Min(requestedHeight, Math.Max(1, height - 24));
        double x = ball.X + Size / 2 >= width / 2 ? ball.X - 10 - w : ball.Right + 10;
        return new(Math.Clamp(x, Margin, Math.Max(Margin, width - Margin - w)),
            Math.Clamp(ball.Y + Size / 2 - h / 2, Margin, Math.Max(Margin, height - Margin - h)), w, h);
    }
    public static bool IsDrag(Position start, Position end) => Math.Sqrt(Math.Pow(end.X - start.X, 2) + Math.Pow(end.Y - start.Y, 2)) >= 4;
}
public enum ParticleKind { Dots, Sparks, Stars }
public readonly record struct Particle(Position Position, double Angle, double Size, double Opacity);
public sealed record Burst(Position Origin, double Born, ParticleKind Kind, int Intensity, string DisplayId) {
    public const double Lifetime = .6;
    public IEnumerable<Particle> Sample(double now) {
        double p = (now - Born) / Lifetime;
        if (p < 0 || p >= 1) yield break;
        int level = Math.Clamp(Intensity, 1, 5), count = new[] { 6, 10, 16, 24, 32 }[level - 1];
        double reach = new[] { 24d, 32, 42, 54, 68 }[level - 1];
        for (int i = 0; i < count; i++) {
            double angle = i * Math.PI * 2 / count + level * .17;
            double distance = reach * (1 - Math.Pow(1 - p, 2)) * (.65 + i % 4 * .1);
            yield return new(new(Origin.X + Math.Cos(angle) * distance, Origin.Y + Math.Sin(angle) * distance), angle, 2 + i % 3 * .6, Math.Pow(1 - p, 2));
        }
    }
}
public sealed class BurstBuffer {
    readonly List<Burst> items = [];
    public IReadOnlyList<Burst> Items => items;
    public void Add(Burst burst, bool reducedMotion) {
        if (reducedMotion) return;
        Expire(burst.Born); items.Add(burst);
        if (items.Count > 8) items.RemoveRange(0, items.Count - 8);
    }
    public void Expire(double now) => items.RemoveAll(x => now - x.Born >= Burst.Lifetime);
    public void Clear() => items.Clear();
}
public static class FocusAnimation {
    public static (double Scale, double Opacity, bool Active) Sample(double now, double started, double duration, bool reduceMotion) {
        if (reduceMotion) return (1, 1, false);
        double p = Math.Clamp((now - started) / Math.Clamp(duration, .1, 1), 0, 1);
        double eased = 1 - Math.Pow(1 - p, 3);
        return (1 + .65 * (1 - eased), eased, p < 1);
    }
}
