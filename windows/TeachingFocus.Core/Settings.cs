using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace TeachingFocus.Core;

public sealed class Settings {
    public int SchemaVersion { get; set; } = 1;
    public double Radius { get; set; } = 120;
    public double Dim { get; set; } = .6;
    public bool Border { get; set; } = true;
    public string BorderColor { get; set; } = "#00D8FF";
    public double BorderWidth { get; set; } = 3;
    public double Glow { get; set; } = 12;
    public bool Animate { get; set; } = true;
    public double AnimationSeconds { get; set; } = .25;
    public bool Halo { get; set; }
    public string HaloColor { get; set; } = "#FFD60A";
    public double HaloRadius { get; set; } = 20;
    public double HaloOpacity { get; set; } = .3;
    public bool Ripples { get; set; } = true;
    public bool Particles { get; set; }
    public ParticleKind ParticleStyle { get; set; }
    public int ParticleIntensity { get; set; } = 2;
    public bool DoubleControl { get; set; } = true;
    public double EscapeSeconds { get; set; } = 3;
    public double PenWidth { get; set; } = 4;
    public Shortcut FreezeShortcut { get; set; } = new(Modifiers.Control | Modifiers.Alt, 0x44);
    public Shortcut SpotlightShortcut { get; set; } = new(Modifiers.Control | Modifiers.Alt, 0x53);
    public Dictionary<string, BallPosition> BallPositions { get; set; } = [];
    public Settings Clone() => JsonSerializer.Deserialize<Settings>(JsonSerializer.Serialize(this, SettingsStore.Options), SettingsStore.Options)!;
    public void Normalize() {
        static double Range(double value, double min, double max, double fallback) => double.IsFinite(value) ? Math.Clamp(value, min, max) : fallback;
        static bool ValidColor(string? value) => value is { Length: 7 } && value[0] == '#' && int.TryParse(value.AsSpan(1), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out _);
        Radius = Range(Radius, 40, 400, 120); Dim = Range(Dim, .1, .9, .6);
        BorderWidth = Range(BorderWidth, 1, 10, 3); Glow = Range(Glow, 0, 30, 12);
        HaloRadius = Range(HaloRadius, 6, 80, 20); HaloOpacity = Range(HaloOpacity, 0, 1, .3);
        AnimationSeconds = Math.Round(Range(AnimationSeconds, .1, 1, .25) / .05) * .05;
        EscapeSeconds = Range(EscapeSeconds, .5, 10, 3); ParticleIntensity = Math.Clamp(ParticleIntensity, 1, 5);
        if (!new[] { 2d, 4, 8, 12 }.Contains(PenWidth)) PenWidth = 4;
        if (!ValidColor(BorderColor)) BorderColor = "#00D8FF";
        if (!ValidColor(HaloColor)) HaloColor = "#FFD60A";
        if (!Enum.IsDefined(ParticleStyle)) ParticleStyle = ParticleKind.Dots;
        if (FreezeShortcut.ValidationError() != null || SpotlightShortcut.ValidationError() != null || FreezeShortcut == SpotlightShortcut) {
            FreezeShortcut = new(Modifiers.Control | Modifiers.Alt, 0x44); SpotlightShortcut = new(Modifiers.Control | Modifiers.Alt, 0x53);
        }
        BallPositions ??= [];
        foreach (var key in BallPositions.Keys.ToArray()) {
            var value = BallPositions[key];
            if (value == null || !double.IsFinite(value.Fraction)) BallPositions.Remove(key);
            else BallPositions[key] = value with { Fraction = Math.Clamp(value.Fraction, 0, 1) };
        }
    }
}
public sealed class SettingsStore {
    public static readonly JsonSerializerOptions Options = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };
    public string FilePath { get; }
    public string? Warning { get; private set; }
    bool canSave = true;
    public SettingsStore(string? path = null) => FilePath = path ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TeachingFocus", "settings.json");
    public Settings Load() {
        if (!File.Exists(FilePath)) return new();
        try {
            var value = JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath), Options) ?? throw new JsonException("設定內容為空。");
            if (value.SchemaVersion > 1) throw new JsonException("設定版本比此程式更新。");
            value.Normalize(); return value;
        } catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException) {
            Warning = "設定無法讀取，這次先使用預設值。";
            try { File.Copy(FilePath, FilePath + ".backup-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff"), false); }
            catch (Exception backupError) when (backupError is IOException or UnauthorizedAccessException) { canSave = false; Warning += "原檔無法備份，因此暫不覆寫設定。"; }
            return new();
        }
    }
    public void Save(Settings settings) {
        if (!canSave) throw new IOException("原設定檔尚未成功備份，請檢查設定資料夾權限。");
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        string temporary = FilePath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough)) {
                JsonSerializer.Serialize(stream, settings, Options); stream.Flush(true);
            }
            File.Move(temporary, FilePath, true);
        } finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
