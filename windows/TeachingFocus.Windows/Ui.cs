using System.Windows.Media.Imaging;

namespace TeachingFocus.Windows;

internal static class Ui {
    public static readonly Brush Ink = Painting.Brush(Color.FromRgb(34, 42, 53));
    public static Button Button(string title, Action action) {
        var button = new Button { Content = title, MinHeight = 28, Padding = new Thickness(8, 3, 8, 3), Margin = new Thickness(3), FontSize = 12, Background = Brushes.White, Foreground = Ink, BorderBrush = Painting.Brush(Color.FromRgb(197, 205, 215)), BorderThickness = new Thickness(1), Cursor = Cursors.Hand };
        button.Click += (_, _) => action(); return button;
    }
    public static StackPanel Row() => new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
    public static Grid EqualRow(int columns) { var grid = new Grid { Margin = new Thickness(0, 4, 0, 0) }; for (int i = 0; i < columns; i++) grid.ColumnDefinitions.Add(new()); return grid; }
    public static void Add(Grid grid, UIElement child, int column) { Grid.SetColumn(child, column); grid.Children.Add(child); }
    public static void Selected(Button button, bool selected) {
        button.Background = selected ? Painting.Brush(Color.FromRgb(214, 239, 255)) : Brushes.White;
        button.BorderBrush = selected ? Painting.Brush(Color.FromRgb(0, 151, 206)) : Painting.Brush(Color.FromRgb(197, 205, 215));
    }
    public static ImageSource AppIcon() => BitmapFrame.Create(new Uri("pack://application:,,,/AppIcon.ico"));
}
