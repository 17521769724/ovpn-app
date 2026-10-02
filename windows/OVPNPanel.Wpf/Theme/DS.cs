using System;
using System.Windows.Media;

namespace OVPNPanel.Theme
{
    /// <summary>提示横幅类型（与 iOS / Android 一致）</summary>
    public enum BannerKind { Success, Error, Warning, Info }

    /// <summary>
    /// 三端统一设计令牌（与 iOS Theme.swift / Android Theme.kt / Web globals.css 一一对应，改动需三端同步）。
    ///
    /// 单位说明：iOS 的 pt 与 Android 的 dp 都是 1/160 英寸，WPF 的设备无关单位是 1/96 英寸。
    /// 这里把令牌数值 **按 1:1 映射** 到 WPF 单位——因为字号与容器尺寸同比例放大，
    /// 版式比例与手机端完全一致，同时更符合桌面端的观看距离。
    /// </summary>
    public static class DS
    {
        /// <summary>由 0xRRGGBB 构造颜色</summary>
        public static Color C(uint rgb) =>
            Color.FromRgb((byte)((rgb >> 16) & 0xFF), (byte)((rgb >> 8) & 0xFF), (byte)(rgb & 0xFF));

        /// <summary>由 0xRRGGBB + 透明度构造颜色</summary>
        public static Color C(uint rgb, double alpha) =>
            Color.FromArgb((byte)Math.Round(alpha * 255), (byte)((rgb >> 16) & 0xFF),
                           (byte)((rgb >> 8) & 0xFF), (byte)(rgb & 0xFF));

        /// <summary>圆角（对齐 Web 端 --radius: 0.625rem = 10px 基准）</summary>
        public static class Radius
        {
            public const double Sm = 6;
            public const double Md = 8;
            public const double Lg = 10;
            public const double Xl = 14;
            public const double Xxl = 18;
        }

        /// <summary>控件尺寸（三端硬性对齐）</summary>
        public static class Size
        {
            public const double ButtonHeight = 42;
            public const double ButtonHeightLarge = 46;
            public const double ButtonHeightSmall = 30;
            public const double InputHeight = 42;
            public const double CardPadding = 16;
            public const double PagePadding = 16;
            public const double Gap = 12;
            public const double GapLarge = 16;
            public const double TabBarHeight = 54;
            /// <summary>桌面端内容列的最大宽度（保持与手机端一致的纵向版式）</summary>
            public const double ContentMaxWidth = 430;
            public const double WindowWidth = 460;
            public const double WindowHeight = 880;
        }

        /// <summary>字号（三端一致：title 20 / section 15 / body 15 / bodySmall 13 / caption 12）</summary>
        public static class FontSize
        {
            public const double Title = 20;
            public const double Section = 15;
            public const double Body = 15;
            public const double BodySmall = 13;
            public const double Caption = 12;
            public const double TabIcon = 19;
            public const double TabLabel = 11;
        }

        /// <summary>品牌色（绿色为主，配青绿 / 黄绿 / 冷青 / 琥珀等协调辅助色）</summary>
        public static class Brand
        {
            public static readonly Color Primary = C(0x059669);
            public static readonly Color PrimaryDeep = C(0x047857);
            public static readonly Color Green = C(0x10B981);
            public static readonly Color Mint = C(0x34D399);
            public static readonly Color Teal = C(0x14B8A6);
            public static readonly Color TealDeep = C(0x0F766E);
            public static readonly Color Lime = C(0x84CC16);
            public static readonly Color Cyan = C(0x06B6D4);
            public static readonly Color Amber = C(0xF59E0B);
            public static readonly Color Red = C(0xE5484D);
            public static readonly Color RedDeep = C(0xC02830);
        }

        /// <summary>颜色（亮色）</summary>
        public static class Light
        {
            public static readonly Color Background = C(0xF6F8F7);
            public static readonly Color Foreground = C(0x0C1512);
            public static readonly Color Card = C(0xFFFFFF);
            public static readonly Color CardForeground = C(0x0C1512);
            public static readonly Color Primary = C(0x059669);
            public static readonly Color PrimaryForeground = C(0xFFFFFF);
            public static readonly Color Secondary = C(0xE6F7F0);
            public static readonly Color SecondaryForeground = C(0x046B56);
            public static readonly Color Muted = C(0xEEF2F0);
            public static readonly Color MutedForeground = C(0x7C8A85);
            public static readonly Color Border = C(0xE2E9E6);
            public static readonly Color Destructive = C(0xE5484D);
            /// <summary>次级文字：比 mutedForeground 更深，保证可读性</summary>
            public static readonly Color SecondaryText = C(0x5A6068);
        }

        /// <summary>颜色（暗色）</summary>
        public static class Dark
        {
            public static readonly Color Background = C(0x0A0F0D);
            public static readonly Color Foreground = C(0xF5FAF8);
            public static readonly Color Card = C(0x141A18);
            public static readonly Color CardForeground = C(0xF5FAF8);
            public static readonly Color Primary = C(0x34D399);
            public static readonly Color PrimaryForeground = C(0x04231B);
            public static readonly Color Secondary = C(0x16302A);
            public static readonly Color SecondaryForeground = C(0xA7F3D0);
            public static readonly Color Muted = C(0x212926);
            public static readonly Color MutedForeground = C(0x9BAAA5);
            /// <summary>Color.white.opacity(0.10)</summary>
            public static readonly Color Border = C(0xFFFFFF, 0.10);
            public static readonly Color Destructive = C(0xFF6B70);
            public static readonly Color SecondaryText = C(0xC9CCD2);
        }

        /// <summary>状态色（Tailwind 色板，与 Web 端一致）</summary>
        public static class Status
        {
            public static readonly Color OnlineBg = C(0x10B981, 0.15);
            public static readonly Color OnlineText = C(0x059669);
            public static readonly Color OfflineBg = C(0xEF4444, 0.15);
            public static readonly Color OfflineText = C(0xDC2626);
            public static readonly Color PendingBg = C(0xE5E5E5);
            public static readonly Color PendingText = C(0x737373);
            public static readonly Color WarningBg = C(0xF59E0B, 0.14);
            public static readonly Color WarningText = C(0xB45309);
            public static readonly Color InfoText = C(0x2563EB);
        }

        /// <summary>流量绿（对应 Web 端 emerald 色板，流量统计统一纯绿色）</summary>
        public static class Traffic
        {
            public static readonly Color Bar = C(0x10B981);
            public static readonly Color BarStrong = C(0x059669);
            public static readonly Color BarSoft = C(0x6EE7B7);
            public static readonly Color Tracker = C(0xD1FAE5);
        }

        /// <summary>功能图标配色（绿色系为主 + 少量协调强调色）</summary>
        public static class IconColor
        {
            public static readonly Color Green = C(0x10B981);
            public static readonly Color Mint = C(0x34D399);
            public static readonly Color Teal = C(0x14B8A6);
            public static readonly Color TealDeep = C(0x0F766E);
            public static readonly Color Lime = C(0x84CC16);
            public static readonly Color Cyan = C(0x06B6D4);
            public static readonly Color Amber = C(0xF59E0B);
            public static readonly Color Orange = C(0xFB923C);
            public static readonly Color Rose = C(0xF43F5E);
            public static readonly Color Slate = C(0x64748B);
        }

        /// <summary>提示横幅配色（对齐 Web 端 sonner richColors）</summary>
        public struct ToastStyle
        {
            public Color Background;
            public Color Border;
            public Color Foreground;

            public static ToastStyle Of(BannerKind kind, bool dark)
            {
                switch (kind)
                {
                    case BannerKind.Success:
                        return dark
                            ? Make(0x001A0F, 0x065F46, 0x4ADE80)
                            : Make(0xECFDF5, 0xA7F3D0, 0x047857);
                    case BannerKind.Error:
                        return dark
                            ? Make(0x2D0607, 0x7F1D1D, 0xFF9B9D)
                            : Make(0xFEF2F2, 0xFECACA, 0xE7000B);
                    case BannerKind.Warning:
                        return dark
                            ? Make(0x1C1A00, 0x854D0E, 0xFCD34D)
                            : Make(0xFEFCE8, 0xFEF08A, 0xB45309);
                    default:
                        return dark
                            ? Make(0x001B33, 0x1E40AF, 0x60A5FA)
                            : Make(0xF0F9FF, 0xBAE6FD, 0x0369A1);
                }
            }

            static ToastStyle Make(uint bg, uint border, uint fg) => new ToastStyle
            {
                Background = C(bg),
                Border = C(border),
                Foreground = C(fg),
            };
        }
    }

    /// <summary>语义色（跟随明暗主题）。所有 Brush 均缓存复用。</summary>
    public sealed class Palette
    {
        public bool Dark { get; }

        public Palette(bool dark) { Dark = dark; }

        public Color Background => Dark ? DS.Dark.Background : DS.Light.Background;
        public Color Foreground => Dark ? DS.Dark.Foreground : DS.Light.Foreground;
        public Color Card => Dark ? DS.Dark.Card : DS.Light.Card;
        public Color CardForeground => Dark ? DS.Dark.CardForeground : DS.Light.CardForeground;
        public Color Primary => Dark ? DS.Dark.Primary : DS.Light.Primary;
        public Color PrimaryForeground => Dark ? DS.Dark.PrimaryForeground : DS.Light.PrimaryForeground;
        public Color Secondary => Dark ? DS.Dark.Secondary : DS.Light.Secondary;
        public Color SecondaryForeground => Dark ? DS.Dark.SecondaryForeground : DS.Light.SecondaryForeground;
        public Color Muted => Dark ? DS.Dark.Muted : DS.Light.Muted;
        public Color MutedForeground => Dark ? DS.Dark.MutedForeground : DS.Light.MutedForeground;
        public Color Border => Dark ? DS.Dark.Border : DS.Light.Border;
        public Color Destructive => Dark ? DS.Dark.Destructive : DS.Light.Destructive;
        /// <summary>次级文字</summary>
        public Color SecondaryText => Dark ? DS.Dark.SecondaryText : DS.Light.SecondaryText;

        public Color OnlineBg => DS.Status.OnlineBg;
        public Color OnlineText => Dark ? DS.C(0x34D399) : DS.Status.OnlineText;
        public Color OfflineBg => DS.Status.OfflineBg;
        public Color OfflineText => Dark ? DS.C(0xF87171) : DS.Status.OfflineText;
        public Color PendingBg => Dark ? DS.Dark.Muted : DS.Status.PendingBg;
        public Color PendingText => Dark ? DS.Dark.MutedForeground : DS.Status.PendingText;
        public Color WarningBg => DS.Status.WarningBg;
        public Color WarningText => Dark ? DS.C(0xFBBF24) : DS.Status.WarningText;

        /// <summary>流量统计统一纯绿色</summary>
        public Color TrafficBar => DS.Traffic.Bar;
        public Color TrafficTracker => Dark ? DS.C(0x064E3B) : DS.Traffic.Tracker;

        // ---- 渐变（与 SwiftUI / Compose 的起止方向一致：左上 → 右下）----

        /// <summary>品牌渐变（主按钮）</summary>
        public Brush AccentGradient => Dark
            ? Gradient(DS.C(0x10B981), DS.C(0x047857))
            : Gradient(DS.Brand.Primary, DS.Brand.PrimaryDeep);

        public Brush TealGradient => Dark
            ? Gradient(DS.C(0x2DD4BF), DS.C(0x0F766E))
            : Gradient(DS.Brand.Teal, DS.Brand.TealDeep);

        public Brush DangerGradient => Dark
            ? Gradient(DS.C(0xFF7C80), DS.C(0xE5484D))
            : Gradient(DS.Brand.Red, DS.Brand.RedDeep);

        /// <summary>连接圆环使用的渐变（绿 → 冷青 → 青绿 → 黄绿 → 亮绿 → 绿）</summary>
        public Color[] ConnectionGradientColors => new[]
        {
            DS.Traffic.Bar, DS.C(0x22D3EE), DS.Brand.Teal, DS.Brand.Lime, DS.C(0x6EE7B7), DS.Traffic.Bar
        };

        public DS.ToastStyle ToastStyle(BannerKind kind) => DS.ToastStyle.Of(kind, Dark);

        static LinearGradientBrush Gradient(Color a, Color b) => new LinearGradientBrush(a, b, 45);

        // ---- Brush 缓存（避免大量小对象造成的渲染开销）----
        readonly System.Collections.Generic.Dictionary<uint, SolidColorBrush> _cache =
            new System.Collections.Generic.Dictionary<uint, SolidColorBrush>();
        readonly object _lock = new object();

        public SolidColorBrush B(Color c)
        {
            uint key = ((uint)c.A << 24) | ((uint)c.R << 16) | ((uint)c.G << 8) | c.B;
            lock (_lock)
            {
                SolidColorBrush brush;
                if (!_cache.TryGetValue(key, out brush))
                {
                    brush = new SolidColorBrush(c);
                    brush.Freeze();
                    _cache[key] = brush;
                }
                return brush;
            }
        }
    }

    /// <summary>全局主题：跟随系统浅色/深色偏好，并被所有 UI 构建器读取。</summary>
    public static class AppTheme
    {
        static Palette _palette = new Palette(false);

        public static Palette Palette => _palette;

        public static bool IsDark => _palette.Dark;

        /// <summary>切换主题（跟随 Windows 的应用主题设置）</summary>
        public static void Apply(bool dark) { _palette = new Palette(dark); }

        public static readonly System.Windows.Media.FontFamily UiFont =
            new System.Windows.Media.FontFamily("Segoe UI, Microsoft YaHei UI, Microsoft YaHei, SimSun");
    }
}
