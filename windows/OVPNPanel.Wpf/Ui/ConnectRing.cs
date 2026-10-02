using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using OVPNPanel.Theme;

namespace OVPNPanel.Core
{
    /// <summary>
    /// 连接状态圆环（极光光环：渐变描边 + 光晕呼吸 + 中心计时），
    /// 与 iOS / Android 的 ConnectRing 视觉与动效一致。
    /// </summary>
    public class ConnectRing : Grid
    {
        readonly double _size;
        readonly double _ringWidth = 9;

        readonly Image _glow1;
        readonly Image _glow2;
        readonly Image _ring;
        readonly Image _comet;
        readonly RotateTransform _ringRotate;
        readonly RotateTransform _cometRotate;
        readonly StackPanel _center;

        VpnStatus _status = VpnStatus.Disconnected;
        string _duration = "00:00";

        public ConnectRing(double size = 224)
        {
            _size = size;
            Width = size;
            Height = size;
            ClipToBounds = true;
            HorizontalAlignment = HorizontalAlignment.Center;

            var palette = Ui.P;
            var colors = palette.ConnectionGradientColors;

            // 1) 外层光晕：两层低透明度粗描边模拟柔光
            _glow1 = RingImage(size, size - 44, 30, colors, 0);
            _glow2 = RingImage(size, size - 40, 18, colors, 0);
            _glow1.Opacity = 0.16;
            _glow2.Opacity = 0.16;
            Children.Add(_glow1);
            Children.Add(_glow2);

            // 2) 底环
            Children.Add(new Ellipse
            {
                Width = size - _ringWidth,
                Height = size - _ringWidth,
                Stroke = Ui.B(palette.Muted),
                StrokeThickness = _ringWidth,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            });

            // 3) 内部柔和径向底色
            var radial = new RadialGradientBrush
            {
                GradientOrigin = new Point(0.5, 0.5),
                Center = new Point(0.5, 0.5),
                RadiusX = 0.5,
                RadiusY = 0.5,
            };
            radial.GradientStops.Add(new GradientStop(Ui.Alpha(palette.MutedForeground, 0.07), 0.0));
            radial.GradientStops.Add(new GradientStop(Ui.Alpha(palette.MutedForeground, 0.015), 1.0));
            var inner = new Ellipse
            {
                Width = size - (_ringWidth + 2) * 2,
                Height = size - (_ringWidth + 2) * 2,
                Fill = radial,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Children.Add(inner);

            // 4) 渐变主环（缓慢流转；未连接时淡显）
            _ring = RingImage(size, size - _ringWidth, _ringWidth, colors, 0);
            _ring.Opacity = 0.32;
            _ringRotate = new RotateTransform(0, size / 2, size / 2);
            _ring.RenderTransform = _ringRotate;
            Children.Add(_ring);

            // 5) 高光彗尾
            _comet = CometImage(size, size - _ringWidth, _ringWidth);
            _cometRotate = new RotateTransform(0, size / 2, size / 2);
            _comet.RenderTransform = _cometRotate;
            _comet.Visibility = Visibility.Collapsed;
            Children.Add(_comet);

            // 6) 中心内容
            _center = new StackPanel
            {
                Orientation = Orientation.Vertical,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Children.Add(_center);

            StartRotations();
            UpdateCenter();
        }

        /// <summary>更新状态与已连接时长</summary>
        public void SetState(VpnStatus status, string duration)
        {
            _status = status;
            _duration = string.IsNullOrEmpty(duration) ? "00:00" : duration;
            Apply();
        }

        void Apply()
        {
            var palette = Ui.P;
            bool connected = _status == VpnStatus.Connected;
            bool busy = _status == VpnStatus.Connecting || _status == VpnStatus.Reasserting
                || _status == VpnStatus.Disconnecting;
            var tint = connected ? DS.IconColor.Green : (busy ? DS.IconColor.Teal : palette.MutedForeground);

            _ring.Opacity = connected ? 1 : (busy ? 0.9 : 0.32);
            _comet.Visibility = (connected || busy) ? Visibility.Visible : Visibility.Collapsed;
            _comet.Opacity = busy ? 0.9 : 0.45;

            // 光晕呼吸
            double baseGlow = connected ? 0.9 : (busy ? 0.6 : 0.16);
            Breathe(_glow1, baseGlow * 0.45, 2.6);
            Breathe(_glow2, baseGlow * 0.6, 2.6);

            StartRotations();
            UpdateCenter(tint, connected, busy);
        }

        void UpdateCenter()
        {
            bool connected = _status == VpnStatus.Connected;
            bool busy = _status == VpnStatus.Connecting || _status == VpnStatus.Reasserting
                || _status == VpnStatus.Disconnecting;
            var tint = connected ? DS.IconColor.Green : (busy ? DS.IconColor.Teal : Ui.P.MutedForeground);
            UpdateCenter(tint, connected, busy);
        }

        void UpdateCenter(Color tint, bool connected, bool busy)
        {
            _center.Children.Clear();
            if (connected)
            {
                var timer = Ui.Text(_duration, 34, FontWeights.SemiBold, Ui.P.Foreground);
                timer.FontFamily = new FontFamily("Consolas, Segoe UI");
                timer.HorizontalAlignment = HorizontalAlignment.Center;
                _center.Children.Add(timer);
                _center.Children.Add(StatusRow(tint, "已连接"));
            }
            else
            {
                string icon = busy ? "refresh" : "power";
                var glyph = Ui.Icon(icon, 30, tint, 2.2);
                glyph.HorizontalAlignment = HorizontalAlignment.Center;
                if (busy)
                {
                    var rotate = new RotateTransform(0, 15, 15);
                    glyph.RenderTransform = rotate;
                    rotate.BeginAnimation(RotateTransform.AngleProperty,
                        new DoubleAnimation(0, 360, TimeSpan.FromSeconds(1.2)) { RepeatBehavior = RepeatBehavior.Forever });
                }
                _center.Children.Add(glyph);

                string label = _status == VpnStatus.Connecting ? "连接中…"
                    : _status == VpnStatus.Reasserting ? "重连中…"
                    : _status == VpnStatus.Disconnecting ? "断开中…" : "未连接";
                var text = Ui.Text(label, 16, FontWeights.SemiBold, tint);
                text.HorizontalAlignment = HorizontalAlignment.Center;
                text.Margin = new Thickness(0, 8, 0, 0);
                _center.Children.Add(text);
            }
        }

        UIElement StatusRow(Color tint, string label)
        {
            var dot = new Ellipse
            {
                Width = 7,
                Height = 7,
                Fill = Ui.B(DS.IconColor.Green),
                VerticalAlignment = VerticalAlignment.Center,
                Effect = new DropShadowEffect { BlurRadius = 4, ShadowDepth = 0, Opacity = 0.6, Color = DS.IconColor.Green },
            };
            var text = Ui.Text(label, 13, FontWeights.Medium, tint);
            var row = Ui.Stack(Orientation.Horizontal, 5, dot, text);
            row.HorizontalAlignment = HorizontalAlignment.Center;
            row.Margin = new Thickness(0, 4, 0, 0);
            return row;
        }

        void StartRotations()
        {
            bool busy = _status == VpnStatus.Connecting || _status == VpnStatus.Reasserting
                || _status == VpnStatus.Disconnecting;
            bool connected = _status == VpnStatus.Connected;

            _ringRotate.BeginAnimation(RotateTransform.AngleProperty, null);
            _ringRotate.Angle = 0;
            _ringRotate.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360,
                TimeSpan.FromSeconds(busy ? 1.6 : 16)) { RepeatBehavior = RepeatBehavior.Forever });

            if (connected || busy)
            {
                _cometRotate.BeginAnimation(RotateTransform.AngleProperty, null);
                _cometRotate.Angle = 0;
                _cometRotate.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360,
                    TimeSpan.FromSeconds(busy ? 1.3 : 6)) { RepeatBehavior = RepeatBehavior.Forever });
            }
        }

        static void Breathe(UIElement element, double to, double seconds)
        {
            var animation = new DoubleAnimation(to, TimeSpan.FromSeconds(seconds))
            {
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever,
                EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut },
            };
            element.BeginAnimation(UIElement.OpacityProperty, animation);
        }

        // MARK: - 圆锥渐变绘制

        /// <summary>生成圆锥渐变的圆环图像</summary>
        public static Image RingImage(double canvas, double diameter, double thickness, Color[] colors, double startAngle)
        {
            return BuildRing(canvas, diameter, thickness, colors, startAngle, 1.0, false);
        }

        /// <summary>高光彗尾：0 → 14% 的白色渐隐弧</summary>
        public static Image CometImage(double canvas, double diameter, double thickness)
        {
            var image = BuildRing(canvas, diameter, thickness, new[] { Ui.Alpha(Colors.White, 0.0), Ui.Alpha(Colors.White, 0.85) },
                0, 0.14, true);
            return image;
        }

        static Image BuildRing(double canvas, double diameter, double thickness, Color[] colors,
            double startAngle, double sweepFraction, bool comet)
        {
            const int segments = 180;
            int count = Math.Max(2, (int)Math.Round(segments * sweepFraction));
            double totalSweep = 360.0 * sweepFraction;
            var group = new DrawingGroup();
            var center = new Point(canvas / 2, canvas / 2);
            double radius = diameter / 2;

            double step = totalSweep / count;
            for (int i = 0; i < count; i++)
            {
                double a0 = startAngle + i * step - step * 0.25;
                double a1 = startAngle + (i + 1) * step + step * 0.25;
                var p0 = C.PointOnCircle(center, radius, a0);
                var p1 = C.PointOnCircle(center, radius, a1);

                var geometry = new StreamGeometry();
                using (var ctx = geometry.Open())
                {
                    ctx.BeginFigure(p0, false, false);
                    ctx.ArcTo(p1, new Size(radius, radius), 0, false, SweepDirection.Clockwise, true, false);
                }
                geometry.Freeze();

                double t = (double)i / Math.Max(1, count - 1);
                var color = SampleColors(colors, t);
                var pen = new Pen(new SolidColorBrush(color), thickness)
                {
                    StartLineCap = PenLineCap.Round,
                    EndLineCap = PenLineCap.Round,
                };
                pen.Freeze();
                group.Children.Add(new GeometryDrawing(null, pen, geometry));
            }

            var image = new Image
            {
                Width = canvas,
                Height = canvas,
                Stretch = Stretch.None,
                SnapsToDevicePixels = true,
                Source = new DrawingImage(group),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            };
            if (comet)
            {
                var rotate = new RotateTransform(0, canvas / 2, canvas / 2);
                image.RenderTransform = rotate;
            }
            return image;
        }

        static Color SampleColors(Color[] colors, double t)
        {
            if (colors == null || colors.Length == 0) return Colors.Transparent;
            if (colors.Length == 1) return colors[0];
            double scaled = Math.Max(0, Math.Min(0.9999, t)) * (colors.Length - 1);
            int index = (int)Math.Floor(scaled);
            double frac = scaled - index;
            return Ui.Mix(colors[index], colors[Math.Min(colors.Length - 1, index + 1)], frac);
        }
    }
}
