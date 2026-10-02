using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using System.Windows.Shapes;

namespace OVPNPanel.Theme
{
    /// <summary>
    /// 矢量图标集。
    ///
    /// 手机端用的是 SF Symbols（iOS）与 Material 图标（Android）；
    /// Windows 侧不使用图标字体——Win7 没有 Segoe MDL2 / Segoe Fluent Icons，
    /// 因此全部以 24×24 视图内的矢量路径绘制，保证 Win7 ~ Win11 渲染完全一致。
    ///
    /// 统一采用「描边」风格（线宽 2、圆头圆角），贴近 SF Symbols 的观感。
    /// </summary>
    public static class Icons
    {
        public const double ViewBox = 24;

        static readonly Dictionary<string, string> Paths = new Dictionary<string, string>
        {
            // ---- 导航 / 通用 ----
            { "chevronLeft",     "M14.5 5 L8 12 L14.5 19" },
            { "chevronRight",    "M9.5 5 L16 12 L9.5 19" },
            { "chevronDown",     "M5 9.5 L12 16 L19 9.5" },
            { "chevronUp",       "M5 14.5 L12 8 L19 14.5" },
            { "close",           "M6 6 L18 18 M18 6 L6 18" },
            { "check",           "M5 12.5 L10 17.5 L19 6.5" },
            { "plus",            "M12 5 V19 M5 12 H19" },
            { "minus",           "M5 12 H19" },
            { "arrowRight",      "M4 12 H19 M13 6 L19 12 L13 18" },
            { "refresh",         "M20 12 A8 8 0 1 1 17 5.9 M17 3 V6.5 H13.5" },
            { "power",           "M12 3 V11 M7.5 6.2 A7.5 7.5 0 1 0 16.5 6.2" },
            { "search",          "M11 4 A7 7 0 1 0 11 18 A7 7 0 1 0 11 4 M16.2 16.2 L21 21" },
            { "info",            "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M12 11 V16.5 M12 7.6 V8.2" },
            { "question",        "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M9.6 9.4 A2.5 2.5 0 0 1 14.5 10 C14.5 12 12 12.2 12 14.4 M12 17.4 V18" },

            // ---- 状态 / 警示 ----
            { "warning",         "M12 3.5 L21.5 20 H2.5 Z M12 9.5 V14 M12 16.8 V17.4" },
            { "checkCircle",     "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M8 12.2 L11 15.2 L16.2 9.2" },
            { "shield",          "M12 3 L20 6 V12 C20 16.8 16.3 20 12 21 C7.7 20 4 16.8 4 12 V6 Z" },
            { "shieldFill",      "M12 3 L20 6 V12 C20 16.8 16.3 20 12 21 C7.7 20 4 16.8 4 12 V6 Z M12 9 V17" },
            { "cloudOff",        "M5 8 A5 5 0 0 1 13 6 A4.5 4.5 0 0 1 19.5 10.4 M4 19 H16 M3 3 L21 21" },

            // ---- 连接 ----
            { "bolt",            "M13.5 2.5 L5 13.5 H11 L10.5 21.5 L19 10.5 H13 Z" },
            { "server",          "M4 5.5 H20 V10 H4 Z M4 14 H20 V18.5 H4 Z M7.5 7.75 V7.75 M7.5 16.25 V16.25" },
            { "globe",           "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M3.5 12 H20.5 M12 3 C15.5 6.5 15.5 17.5 12 21 M12 3 C8.5 6.5 8.5 17.5 12 21" },

            // ---- 底部导航 ----
            { "tabLines",        "M13.5 2.5 L5 13.5 H11 L10.5 21.5 L19 10.5 H13 Z M12 12 A9 9 0 1 0 12 12" },
            { "tabPlans",        "M3.5 7.5 L12 3.5 L20.5 7.5 V16.5 L12 20.5 L3.5 16.5 Z M3.5 7.5 L12 11.5 L20.5 7.5 M12 11.5 V20.5" },
            { "tabInvite",       "M9.5 11 A3.6 3.6 0 1 0 9.5 3.8 A3.6 3.6 0 1 0 9.5 11 M2.5 20.5 C2.5 16.6 5.7 14.5 9.5 14.5 C11 14.5 12.4 14.8 13.5 15.4 M18 13 V20 M14.5 16.5 H21.5" },
            { "tabProfile",      "M12 11.5 A4 4 0 1 0 12 3.5 A4 4 0 1 0 12 11.5 M4 21 C4 16.6 7.6 14 12 14 C16.4 14 20 16.6 20 21" },

            // ---- 个人中心 / 功能 ----
            { "person",          "M12 11.5 A4 4 0 1 0 12 3.5 A4 4 0 1 0 12 11.5 M4 21 C4 16.6 7.6 14 12 14 C16.4 14 20 16.6 20 21" },
            { "gift",            "M3.5 8.5 H20.5 V12 H3.5 Z M5 12 V20.5 H19 V12 M12 8.5 V20.5 M12 8.5 C12 8.5 9 8.6 8 7.4 C7 6.2 8.2 4.2 9.6 4.6 C11.4 5.1 12 8.5 12 8.5 M12 8.5 C12 8.5 15 8.6 16 7.4 C17 6.2 15.8 4.2 14.4 4.6 C12.6 5.1 12 8.5 12 8.5" },
            { "ticket",          "M3.5 8 H20.5 V11 C19.4 11 18.5 11.9 18.5 13 C18.5 14.1 19.4 15 20.5 15 V18 H3.5 V15 C4.6 15 5.5 14.1 5.5 13 C5.5 11.9 4.6 11 3.5 11 Z" },
            { "coin",            "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M9.5 9.5 L12 12.5 L14.5 9.5 M12 12.5 V16.5 M9.5 13.5 H14.5" },
            { "card",            "M3 6.5 H21 V17.5 H3 Z M3 10.5 H21 M6.5 14 H10" },
            { "clock",           "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M12 7 V12.3 L15.8 14.5" },
            { "chart",           "M4 20 V11 M10 20 V5 M16 20 V14 M22 20 H2" },
            { "megaphone",       "M4 10 V14 H7 L15 19 V5 L7 10 Z M18 9.5 C19.5 10.7 19.5 13.3 18 14.5" },
            { "bell",            "M6.5 10 A5.5 5.5 0 0 1 17.5 10 C17.5 15 19 16.5 19 16.5 H5 C5 16.5 6.5 15 6.5 10 M10 19.5 A2.2 2.2 0 0 0 14 19.5" },
            { "envelope",        "M3 6 H21 V18 H3 Z M3 6.5 L12 13 L21 6.5" },
            { "key",             "M15.5 3.5 A5 5 0 1 0 15.5 13.5 A5 5 0 1 0 15.5 3.5 M11.4 11.6 L3.5 19.5 M5.5 17.5 L7.5 19.5 M3.5 19.5 L5 21" },
            { "lock",            "M5.5 10.5 H18.5 V20.5 H5.5 Z M8.5 10.5 V7.5 A3.5 3.5 0 0 1 15.5 7.5 V10.5 M12 14.5 V16.5" },
            { "link",            "M10 14 A4 4 0 0 0 15.6 14 L18.4 11.2 A4 4 0 0 0 12.8 5.6 L11.4 7 M14 10 A4 4 0 0 0 8.4 10 L5.6 12.8 A4 4 0 0 0 11.2 18.4 L12.6 17" },
            { "copy",            "M9 9 H20 V20 H9 Z M15 6 H4 V17 H6.5" },
            { "message",         "M4 5 H20 V16 H10 L5 20 V16 H4 Z M8 9 H16 M8 12 H13" },
            { "gear",            "M12 8.6 A3.4 3.4 0 1 0 12 15.4 A3.4 3.4 0 1 0 12 8.6 M12 2.5 L13.4 5.4 L16.6 4.8 L17 8 L20 9 L18.6 12 L20 15 L17 16 L16.6 19.2 L13.4 18.6 L12 21.5 L10.6 18.6 L7.4 19.2 L7 16 L4 15 L5.4 12 L4 9 L7 8 L7.4 4.8 L10.6 5.4 Z" },
            { "eye",             "M2.5 12 C5.5 7 8.7 5 12 5 C15.3 5 18.5 7 21.5 12 C18.5 17 15.3 19 12 19 C8.7 19 5.5 17 2.5 12 Z M12 9 A3 3 0 1 0 12 15 A3 3 0 1 0 12 9" },
            { "trash",           "M4.5 6.5 H19.5 M9 6.5 V4.5 H15 V6.5 M6.5 6.5 L7.5 20.5 H16.5 L17.5 6.5 M10 10 V17 M14 10 V17" },
            { "logout",          "M14 4 H19.5 V20 H14 M9 12 H19 M13 8 L17 12 L13 16" },
            { "doc",             "M6 3 H14.5 L19 7.5 V21 H6 Z M14 3 V8 H19 M9 12 H16 M9 15.5 H16 M9 19 H13" },
            { "externalLink",    "M14 4 H20 V10 M20 4 L11 13 M18 14 V20 H4 V6 H10" },
            { "upload",          "M12 16.5 V4.5 M7.5 9 L12 4.5 L16.5 9 M4 20 H20" },
            { "edit",            "M4 20 H8 L19 9 L15 5 L4 16 Z M14 6 L18 10" },
            { "list",            "M4 6.5 H20 M4 12 H20 M4 17.5 H20" },
            { "calendar",        "M4 5.5 H20 V20.5 H4 Z M4 10 H20 M8.5 3.5 V7 M15.5 3.5 V7" },
        };

        /// <summary>取图标的路径数据；未收录的图标返回 null。</summary>
        public static string Data(string name)
        {
            string d;
            return Paths.TryGetValue(name, out d) ? d : null;
        }

        /// <summary>构造一个描边风格的图标（默认线宽 2，圆头）</summary>
        public static Path Create(string name, double size, Color color, double thickness = 2)
        {
            var path = new Path
            {
                Stroke = AppTheme.Palette.B(color),
                StrokeThickness = thickness,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round,
                StrokeLineJoin = PenLineJoin.Round,
                Fill = null,
                Stretch = Stretch.Uniform,
                Width = size,
                Height = size,
                Data = ParseGeometry(Data(name) ?? "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3"),
                SnapsToDevicePixels = true,
            };
            return path;
        }

        /// <summary>把 24×24 视图的路径数据缩放到目标尺寸</summary>
        public static Geometry ParseGeometry(string data)
        {
            var g = (Geometry)Geometry.Parse(data);
            var scale = new ScaleTransform(ViewBox / ViewBox, ViewBox / ViewBox);
            var group = new TransformGroup();
            group.Children.Add(scale);
            g.Transform = group;
            g.Freeze();
            return g;
        }
    }
}
