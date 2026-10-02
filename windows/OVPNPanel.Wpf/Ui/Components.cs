using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using OVPNPanel.Theme;

namespace OVPNPanel.Core
{
    public enum BtnStyle { Primary, Accent, Secondary, Outline, Destructive }

    /// <summary>三端统一的基础组件库（对应 iOS Components.swift）</summary>
    public static class C
    {
        // MARK: - 按钮

        public static Border Button(string title, Action action, BtnStyle style = BtnStyle.Primary,
            string icon = null, double height = DS.Size.ButtonHeight, bool loading = false, bool disabled = false,
            string subtitle = null)
        {
            var palette = Ui.P;
            var row = Ui.Stack(Orientation.Horizontal, 6);
            row.HorizontalAlignment = HorizontalAlignment.Center;
            row.VerticalAlignment = VerticalAlignment.Center;

            if (loading) row.Children.Add(Spinner(14, Foreground(style)));
            else if (!string.IsNullOrEmpty(icon)) row.Children.Add(Ui.Icon(icon, 14, Foreground(style), 2));

            var labelStack = Ui.Stack(Orientation.Vertical, 1);
            labelStack.HorizontalAlignment = HorizontalAlignment.Center;
            labelStack.Children.Add(Ui.Text(title ?? "", 15, FontWeights.SemiBold, Foreground(style)));

            row.Children.Add(labelStack);

            Brush background = Background(style);
            var border = new Border
            {
                Height = height,
                CornerRadius = new CornerRadius(DS.Radius.Lg),
                Background = background,
                BorderBrush = style == BtnStyle.Outline ? Ui.B(palette.Border) : null,
                BorderThickness = style == BtnStyle.Outline ? new Thickness(1) : new Thickness(0),
                Child = row,
                SnapsToDevicePixels = true,
            };

            var shadowColor = Shadow(style);
            if (shadowColor.HasValue)
            {
                border.Effect = new System.Windows.Media.Effects.DropShadowEffect
                {
                    BlurRadius = 9,
                    ShadowDepth = 3,
                    Opacity = 0.35,
                    Color = shadowColor.Value,
                };
            }

            if (disabled || loading)
            {
                border.Opacity = disabled ? 0.5 : 0.85;
                border.Cursor = Cursors.Arrow;
                return border;
            }
            border.Clickable(action, 0.97);
            return border;
        }

        static Color Foreground(BtnStyle style)
        {
            switch (style)
            {
                case BtnStyle.Primary:
                case BtnStyle.Accent:
                case BtnStyle.Destructive: return Colors.White;
                case BtnStyle.Secondary: return Ui.P.SecondaryForeground;
                default: return Ui.P.Foreground;
            }
        }

        static Brush Background(BtnStyle style)
        {
            switch (style)
            {
                case BtnStyle.Primary: return Ui.P.AccentGradient;
                case BtnStyle.Accent: return Ui.P.TealGradient;
                case BtnStyle.Secondary: return Ui.B(Ui.P.Secondary);
                case BtnStyle.Outline: return Ui.B(Ui.P.Card);
                default: return Ui.P.DangerGradient;
            }
        }

        static Color? Shadow(BtnStyle style)
        {
            switch (style)
            {
                case BtnStyle.Primary: return DS.Brand.Green;
                case BtnStyle.Accent: return DS.Brand.Teal;
                case BtnStyle.Destructive: return DS.Brand.Red;
                default: return null;
            }
        }

        /// <summary>小尺寸标签按钮（分类筛选等）</summary>
        public static Border Chip(string title, bool selected, Action action)
        {
            var palette = Ui.P;
            var text = Ui.Text(title, 13, selected ? FontWeights.SemiBold : FontWeights.Normal,
                selected ? Colors.White : palette.Foreground);
            text.Margin = new Thickness(12, 0, 12, 0);
            var border = new Border
            {
                Height = DS.Size.ButtonHeightSmall,
                CornerRadius = new CornerRadius(DS.Radius.Md),
                Background = selected ? (Brush)palette.AccentGradient : Ui.B(palette.Card),
                BorderBrush = Ui.B(palette.Border),
                BorderThickness = selected ? new Thickness(0) : new Thickness(1),
                Child = new Grid { Children = { text } },
                SnapsToDevicePixels = true,
            };
            border.Clickable(action);
            return border;
        }

        /// <summary>下拉刷新按钮（对应三端共有的 refresh 交互）</summary>
        public static Border IconButton(string icon, Color color, Action action, double size = 34)
        {
            var border = new Border
            {
                Width = size,
                Height = size,
                CornerRadius = new CornerRadius(size / 2),
                Background = Ui.B(Ui.Alpha(color, 0.12)),
                Child = new Grid { Children = { Ui.Icon(icon, size * 0.5, color, 2) } },
            };
            border.Clickable(action);
            return border;
        }

        // MARK: - 输入框

        /// <summary>带标题的输入框（返回控件可通过 .Value 读取当前文本）</summary>
        public static TextFieldControl TextField(string title, string placeholder, string initial = "",
            bool secure = false, Action<string> onChanged = null)
        {
            return new TextFieldControl(title, placeholder, initial, secure, onChanged);
        }

        public static Border ReadOnlyField(string title, string value, bool masked = false)
        {
            var palette = Ui.P;
            var stack = Ui.Stack(Orientation.Vertical, 6);
            stack.Children.Add(Ui.Text(title, DS.FontSize.BodySmall, FontWeights.Normal, palette.SecondaryText));

            var box = new Border
            {
                Height = DS.Size.InputHeight,
                CornerRadius = new CornerRadius(DS.Radius.Lg),
                Background = Ui.B(palette.Muted),
                Opacity = 0.6f,
                BorderBrush = Ui.B(palette.Border),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(12, 0, 12, 0),
                Child = Ui.Text(masked ? "••••••••" : (value ?? ""), DS.FontSize.Body, FontWeights.Normal, palette.MutedForeground),
            };
            stack.Children.Add(box);
            stack.IsHitTestVisible = false;
            return new Border { Child = stack };
        }

        // MARK: - 卡片

        public static Border Card(UIElement child, double padding = DS.Size.CardPadding, Color? background = null)
        {
            return Ui.Box(child, background ?? Ui.P.Card, DS.Radius.Xl, Ui.P.Border, 1, new Thickness(padding));
        }

        /// <summary>无边框的浅色分组卡片（列表容器）</summary>
        public static Border MenuGroup(UIElement child)
        {
            return Ui.Box(child, Ui.P.Card, DS.Radius.Xl, Ui.P.Border, 1, new Thickness(0));
        }

        // MARK: - 徽章与状态

        public static Border StatusBadge(string text, Color background, Color foreground)
        {
            var label = Ui.Text(text, 11, FontWeights.Medium, foreground);
            label.Margin = new Thickness(7, 3, 7, 3);
            return new Border
            {
                CornerRadius = new CornerRadius(99),
                Background = Ui.B(background),
                Child = label,
                VerticalAlignment = VerticalAlignment.Center,
            };
        }

        public static Border NodeStatusBadge(string status)
        {
            var palette = Ui.P;
            string text; Color bg; Color fg;
            switch (status)
            {
                case "online": text = "在线"; bg = palette.OnlineBg; fg = palette.OnlineText; break;
                case "disabled": text = "已停用"; bg = palette.PendingBg; fg = palette.PendingText; break;
                default: text = "离线"; bg = palette.OfflineBg; fg = palette.OfflineText; break;
            }
            return StatusBadge(text, bg, fg);
        }

        // MARK: - 统计条

        public static Grid StatBar(string label, double value, string icon = null)
        {
            var palette = Ui.P;
            var left = Ui.Stack(Orientation.Horizontal, 4);
            if (!string.IsNullOrEmpty(icon)) left.Children.Add(Ui.Icon(icon, 11, palette.MutedForeground, 1.8));
            left.Children.Add(Ui.Text(label, DS.FontSize.Caption, FontWeights.Normal, palette.MutedForeground));
            left.Width = 56;
            left.HorizontalAlignment = HorizontalAlignment.Left;

            var bar = new BarView(6) { Value = value, VerticalAlignment = VerticalAlignment.Center };

            var percent = Ui.Text(value.ToString("F0") + "%", DS.FontSize.Caption, FontWeights.Normal, palette.MutedForeground);
            percent.Width = 36;
            percent.TextAlignment = TextAlignment.Right;

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(left, 0); grid.Children.Add(left);
            Grid.SetColumn(bar, 1); bar.Margin = new Thickness(8, 0, 8, 0); grid.Children.Add(bar);
            Grid.SetColumn(percent, 2); grid.Children.Add(percent);
            return grid;
        }

        // MARK: - 列表行与区块

        public static Grid InfoRow(string label, string value, Color? valueColor = null)
        {
            var palette = Ui.P;
            var left = Ui.Text(label, DS.FontSize.BodySmall, FontWeights.Normal, palette.MutedForeground);
            left.VerticalAlignment = VerticalAlignment.Top;
            var right = Ui.Text(value ?? "", DS.FontSize.BodySmall, FontWeights.Normal, valueColor ?? palette.SecondaryText);
            right.TextAlignment = TextAlignment.Right;
            right.VerticalAlignment = VerticalAlignment.Top;
            right.Margin = new Thickness(12, 0, 0, 0);
            right.TextWrapping = TextWrapping.Wrap;

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetColumn(left, 0); grid.Children.Add(left);
            Grid.SetColumn(right, 1); grid.Children.Add(right);
            return grid;
        }

        public static StackPanel SectionHeader(string title, string subtitle = null)
        {
            var stack = Ui.Stack(Orientation.Vertical, 2);
            stack.Children.Add(Ui.SectionTitle(title));
            if (!string.IsNullOrEmpty(subtitle))
                stack.Children.Add(Ui.Caption(subtitle));
            return stack;
        }

        public static StackPanel EmptyHint(string icon, string title, string detail = null)
        {
            var palette = Ui.P;
            var stack = Ui.Stack(Orientation.Vertical, 8);
            stack.HorizontalAlignment = HorizontalAlignment.Center;
            stack.Margin = new Thickness(0, 32, 0, 32);
            var glyph = Ui.Icon(icon, 26, palette.MutedForeground, 1.8);
            glyph.HorizontalAlignment = HorizontalAlignment.Center;
            stack.Children.Add(glyph);
            var t = Ui.Text(title, DS.FontSize.Body, FontWeights.Normal, palette.MutedForeground);
            t.HorizontalAlignment = HorizontalAlignment.Center;
            stack.Children.Add(t);
            if (!string.IsNullOrEmpty(detail))
            {
                var d = Ui.Caption(detail);
                d.HorizontalAlignment = HorizontalAlignment.Center;
                stack.Children.Add(d);
            }
            return stack;
        }

        public static StackPanel LoadingBlock(string text = "加载中…")
        {
            var palette = Ui.P;
            var stack = Ui.Stack(Orientation.Horizontal, 8);
            stack.HorizontalAlignment = HorizontalAlignment.Center;
            stack.Margin = new Thickness(0, 28, 0, 28);
            stack.Children.Add(Spinner(15, palette.MutedForeground));
            stack.Children.Add(Ui.Text(text, DS.FontSize.BodySmall, FontWeights.Normal, palette.MutedForeground));
            return stack;
        }

        // MARK: - 提示

        public static Border BannerBar(string message, BannerKind kind = BannerKind.Error)
        {
            var palette = Ui.P;
            Color bg; Color fg; string icon;
            switch (kind)
            {
                case BannerKind.Error: bg = palette.OfflineBg; fg = palette.OfflineText; icon = "info"; break;
                case BannerKind.Warning: bg = palette.WarningBg; fg = palette.WarningText; icon = "info"; break;
                case BannerKind.Success: bg = palette.OnlineBg; fg = palette.OnlineText; icon = "checkCircle"; break;
                default: bg = palette.Muted; fg = palette.SecondaryText; icon = "info"; break;
            }
            var glyph = Ui.Icon(icon, 13, fg, 1.8);
            glyph.VerticalAlignment = VerticalAlignment.Top;
            glyph.Margin = new Thickness(0, 1, 0, 0);
            var text = Ui.Text(message, DS.FontSize.Caption, FontWeights.Normal, fg, TextWrapping.Wrap);
            var row = Ui.Stack(Orientation.Horizontal, 6, glyph, text);
            return Ui.Box(row, bg, DS.Radius.Md, null, 0, new Thickness(10, 8, 10, 8));
        }

        // MARK: - 个人中心列表行

        public static Border MenuRow(string icon, Color iconColor, string title, string subtitle = null,
            string badge = null, Action onClick = null, double height = 58)
        {
            var palette = Ui.P;
            var texts = Ui.Stack(Orientation.Vertical, 2);
            texts.Children.Add(Ui.Text(title, DS.FontSize.Body, FontWeights.Normal, palette.Foreground));
            if (!string.IsNullOrEmpty(subtitle))
                texts.Children.Add(Ui.Caption(subtitle));

            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var tile = Ui.IconTile(icon, iconColor);
            var textsBorder = new Border { Child = texts, Padding = new Thickness(12, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
            var chevron = Ui.Icon("chevronRight", 12, Ui.Alpha(palette.MutedForeground, 0.8), 2);
            chevron.VerticalAlignment = VerticalAlignment.Center;
            chevron.Margin = new Thickness(8, 0, 0, 0);

            Grid.SetColumn(tile, 0); row.Children.Add(tile);
            Grid.SetColumn(textsBorder, 1); row.Children.Add(textsBorder);
            if (!string.IsNullOrEmpty(badge))
            {
                var badgeView = StatusBadge(badge, Ui.Alpha(iconColor, 0.14), iconColor);
                Grid.SetColumn(badgeView, 2);
                badgeView.Margin = new Thickness(0, 0, 4, 0);
                row.Children.Add(badgeView);
            }
            Grid.SetColumn(chevron, 3); row.Children.Add(chevron);

            var surface = new PressSurface
            {
                Height = height,
                Child = row,
                Padding = new Thickness(DS.Size.CardPadding, 0, DS.Size.CardPadding, 0),
            };
            if (onClick != null) surface.Clicked += onClick;
            return surface;
        }

        /// <summary>分组内的菜单行（带底部分隔线，最后一行不显示）</summary>
        public static StackPanel MenuList(params UIElement[] rows)
        {
            var stack = Ui.Stack(Orientation.Vertical, 0);
            for (int i = 0; i < rows.Length; i++)
            {
                if (rows[i] == null) continue;
                stack.Children.Add(rows[i]);
                if (i < rows.Length - 1)
                {
                    stack.Children.Add(new Border
                    {
                        Height = 1,
                        Background = Ui.B(Ui.P.Border),
                        Margin = new Thickness(DS.Size.CardPadding, 0, DS.Size.CardPadding, 0),
                    });
                }
            }
            return stack;
        }

        // MARK: - 感应器

        /// <summary>环形加载指示器（旋转弧线）</summary>
        public static Grid Spinner(double size, Color color)
        {
            var root = new Grid { Width = size, Height = size };
            var arc = new Path
            {
                Stroke = Ui.B(color),
                StrokeThickness = Math.Max(1.6, size * 0.12),
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round,
                Data = ArcGeometry(size / 2, 0.02, 0.78),
                Width = size,
                Height = size,
                Stretch = Stretch.None,
            };
            root.Children.Add(arc);
            var rotate = new RotateTransform(0, size / 2, size / 2);
            root.RenderTransform = rotate;
            var animation = new DoubleAnimation(0, 360, TimeSpan.FromSeconds(0.9))
            {
                RepeatBehavior = RepeatBehavior.Forever,
            };
            rotate.BeginAnimation(RotateTransform.AngleProperty, animation);
            return root;
        }

        public static Geometry ArcGeometry(double radius, double from, double to)
        {
            var center = new Point(radius, radius);
            var start = PointOnCircle(center, radius, from * 360 - 90);
            var end = PointOnCircle(center, radius, to * 360 - 90);
            var geometry = new StreamGeometry();
            using (var ctx = geometry.Open())
            {
                ctx.BeginFigure(start, false, false);
                ctx.ArcTo(end, new Size(radius, radius), 0, (to - from) > 0.5,
                    SweepDirection.Clockwise, true, false);
            }
            geometry.Freeze();
            return geometry;
        }

        public static Point PointOnCircle(Point center, double radius, double degrees)
        {
            double radians = degrees * Math.PI / 180.0;
            return new Point(center.X + radius * Math.Cos(radians), center.Y + radius * Math.Sin(radians));
        }
    }

    /// <summary>带标题的输入框控件</summary>
    public class TextFieldControl : StackPanel
    {
        readonly TextBox _box;
        readonly PasswordBox _password;
        readonly bool _secure;

        public TextFieldControl(string title, string placeholder, string initial, bool secure, Action<string> onChanged)
        {
            Orientation = Orientation.Vertical;
            _secure = secure;
            var palette = Ui.P;

            var label = Ui.Text(title, DS.FontSize.BodySmall, FontWeights.Normal, palette.SecondaryText);
            label.Margin = new Thickness(0, 0, 0, 6);
            Children.Add(label);

            FrameworkElement input;
            if (secure)
            {
                _password = new PasswordBox
                {
                    Height = DS.Size.InputHeight,
                    FontSize = DS.FontSize.Body,
                    Padding = new Thickness(11, 0, 11, 0),
                    VerticalContentAlignment = VerticalAlignment.Center,
                    Background = Ui.B(palette.Background),
                    Foreground = Ui.B(palette.Foreground),
                    BorderBrush = Ui.B(palette.Border),
                    BorderThickness = new Thickness(1),
                    Password = initial ?? "",
                };
                _password.PasswordChanged += (s, e) => { if (onChanged != null) onChanged(_password.Password); };
                input = _password;
            }
            else
            {
                _box = new TextBox
                {
                    Height = DS.Size.InputHeight,
                    FontSize = DS.FontSize.Body,
                    Padding = new Thickness(11, 0, 11, 0),
                    VerticalContentAlignment = VerticalAlignment.Center,
                    Background = Ui.B(palette.Background),
                    Foreground = Ui.B(palette.Foreground),
                    BorderBrush = Ui.B(palette.Border),
                    BorderThickness = new Thickness(1),
                    Text = initial ?? "",
                    AcceptsReturn = false,
                };
                if (!string.IsNullOrEmpty(placeholder)) _box.ToolTip = placeholder;
                _box.TextChanged += (s, e) => { if (onChanged != null) onChanged(_box.Text); };
                input = _box;
            }

            // 圆角输入框：WPF TextBox 无圆角，外包一层 Border 后再隐藏原生边框
            var wrapper = new Border
            {
                CornerRadius = new CornerRadius(DS.Radius.Lg),
                Child = input,
                Background = Ui.B(palette.Background),
                BorderBrush = Ui.B(palette.Border),
                BorderThickness = new Thickness(1),
                ClipToBounds = true,
            };
            Children.Add(wrapper);
            Margin = new Thickness(0);
        }

        public string Value
        {
            get { return _secure ? _password.Password : _box.Text; }
            set
            {
                if (_secure) _password.Password = value ?? "";
                else _box.Text = value ?? "";
            }
        }

        public void FocusInput()
        {
            if (_secure) _password.Focus();
            else _box.Focus();
        }
    }

    /// <summary>分段切换（流量 近 7 天 / 近 15 天）</summary>
    public class SegmentedTabs : Border
    {
        readonly List<Border> _segments = new List<Border>();
        readonly List<TextBlock> _labels = new List<TextBlock>();
        int _selection;

        public Action<int> SelectionChanged;

        public SegmentedTabs(string[] items, int selection = 0, double segmentWidth = 82)
        {
            var palette = Ui.P;
            _selection = selection;
            CornerRadius = new CornerRadius(DS.Radius.Md);
            Background = Ui.B(palette.Muted);
            Padding = new Thickness(2);

            var row = Ui.Stack(Orientation.Horizontal, 2);
            for (int i = 0; i < items.Length; i++)
            {
                int index = i;
                var label = Ui.Text(items[i], 12, FontWeights.SemiBold, palette.MutedForeground);
                label.Width = segmentWidth;
                label.Height = 28;
                label.TextAlignment = TextAlignment.Center;
                label.HorizontalAlignment = HorizontalAlignment.Center;
                var segment = new Border
                {
                    Width = segmentWidth,
                    Height = 28,
                    CornerRadius = new CornerRadius(DS.Radius.Sm),
                    Background = Brushes.Transparent,
                    Child = new Grid { Children = { label } },
                };
                segment.Clickable(() => Select(index), 0.96);
                _segments.Add(segment);
                _labels.Add(label);
                row.Children.Add(segment);
            }
            Child = row;
            Apply();
        }

        public int Selection
        {
            get { return _selection; }
            set { Select(value, false); }
        }

        void Select(int index, bool notify = true)
        {
            if (index < 0 || index >= _segments.Count) return;
            _selection = index;
            Apply();
            if (notify && SelectionChanged != null) SelectionChanged(index);
        }

        void Apply()
        {
            var palette = Ui.P;
            for (int i = 0; i < _segments.Count; i++)
            {
                bool active = i == _selection;
                _segments[i].Background = active ? Ui.B(palette.Card) : Brushes.Transparent;
                _labels[i].Foreground = Ui.B(active ? palette.Primary : palette.MutedForeground);
                _segments[i].Effect = active
                    ? new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 3, ShadowDepth = 1, Opacity = 0.10, Color = Colors.Black }
                    : null;
            }
        }
    }
}
