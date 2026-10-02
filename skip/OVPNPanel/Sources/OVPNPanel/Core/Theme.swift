import SwiftUI

/// 三端统一设计令牌（与 Web 端 globals.css 一一对应，改动需三端同步）
/// Web 端基准：--radius: 0.625rem (=10px)，Tailwind 语义色。
enum DS {

    // MARK: - 十六进制颜色
    /// Skip 无法把扩展合并进模块外的 `Color` 类型，故以本项目内的工厂函数代替
    /// `extension Color { init(hex:) }`，两端行为一致。
    static func hex(_ value: UInt32, alpha: Double = 1) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: alpha
        )
    }

    // MARK: - 圆角
    enum Radius {
        static let sm: CGFloat = 6    // 0.6 × 10
        static let md: CGFloat = 8    // 0.8 × 10
        static let lg: CGFloat = 10   // 基准
        static let xl: CGFloat = 14   // 1.4 × 10
        static let xxl: CGFloat = 18  // 1.8 × 10
        static let full: CGFloat = 999
    }

    // MARK: - 控件尺寸（三端硬性对齐）
    enum Size {
        static let buttonHeight: CGFloat = 42     // 主操作按钮高度（略微收紧，更接近 iOS 18 比例）
        static let buttonHeightLarge: CGFloat = 46 // 连接等强调按钮
        static let buttonHeightSmall: CGFloat = 30 // 次级/小按钮
        static let inputHeight: CGFloat = 42      // 输入框高度
        static let cardPadding: CGFloat = 16
        static let pagePadding: CGFloat = 16
        static let gap: CGFloat = 12
        static let gapLarge: CGFloat = 16
        static let tabBarHeight: CGFloat = 54
    }

    // MARK: - 字号
    enum Font {
        static let title = SwiftUI.Font.system(size: 20, weight: .semibold)
        static let section = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 15)
        static let bodySmall = SwiftUI.Font.system(size: 13)
        static let caption = SwiftUI.Font.system(size: 12)
        static let value = SwiftUI.Font.system(size: 13, weight: .regular)  // 列表右侧数值（柔化，避免过重）
        static let number = SwiftUI.Font.system(size: 15, weight: .medium)
    }

    // MARK: - 品牌色（绿色为主，配青绿 / 黄绿 / 冷青 / 琥珀等协调辅助色）
    enum Brand {
        static let primary = DS.hex( 0x059669)      // 主色（深一档，保证白字对比度）
        static let primaryDeep = DS.hex( 0x047857)
        static let green = DS.hex( 0x10B981)        // 主绿（emerald-500）
        static let mint = DS.hex( 0x34D399)         // 亮绿（emerald-400）
        static let teal = DS.hex( 0x14B8A6)         // 青绿（邻近色）
        static let tealDeep = DS.hex( 0x0F766E)
        static let lime = DS.hex( 0x84CC16)         // 黄绿（邻近色）
        static let cyan = DS.hex( 0x06B6D4)         // 冷青（邻近色）
        static let amber = DS.hex( 0xF59E0B)        // 琥珀（互补强调）
        static let red = DS.hex( 0xE5484D)          // 危险（断开 / 退出）
        static let redDeep = DS.hex( 0xC02830)
    }

    // MARK: - 颜色（亮色）
    enum Light {
        static let background = DS.hex( 0xF6F8F7)
        static let foreground = DS.hex( 0x0C1512)
        static let card = DS.hex( 0xFFFFFF)
        static let cardForeground = DS.hex( 0x0C1512)
        static let primary = DS.hex( 0x059669)
        static let primaryForeground = DS.hex( 0xFFFFFF)
        static let secondary = DS.hex( 0xE6F7F0)
        static let secondaryForeground = DS.hex( 0x046B56)
        static let muted = DS.hex( 0xEEF2F0)
        static let mutedForeground = DS.hex( 0x7C8A85)
        static let border = DS.hex( 0xE2E9E6)
        static let destructive = DS.hex( 0xE5484D)
    }

    // MARK: - 颜色（暗色）
    enum Dark {
        static let background = DS.hex( 0x0A0F0D)
        static let foreground = DS.hex( 0xF5FAF8)
        static let card = DS.hex( 0x141A18)
        static let cardForeground = DS.hex( 0xF5FAF8)
        static let primary = DS.hex( 0x34D399)
        static let primaryForeground = DS.hex( 0x04231B)
        static let secondary = DS.hex( 0x16302A)
        static let secondaryForeground = DS.hex( 0xA7F3D0)
        static let muted = DS.hex( 0x212926)
        static let mutedForeground = DS.hex( 0x9BAAA5)
        static let border = Color.white.opacity(0.10)
        static let destructive = DS.hex( 0xFF6B70)
    }

    // MARK: - 状态色（Tailwind 色板，与 Web 端一致）
    enum Status {
        static let onlineBg = DS.hex( 0x10B981).opacity(0.15)
        static let onlineText = DS.hex( 0x059669)
        static let offlineBg = DS.hex( 0xEF4444).opacity(0.15)
        static let offlineText = DS.hex( 0xDC2626)
        static let pendingBg = DS.hex( 0xE5E5E5)
        static let pendingText = DS.hex( 0x737373)
        static let warningBg = DS.hex( 0xF59E0B).opacity(0.14)
        static let warningText = DS.hex( 0xB45309)
        static let infoText = DS.hex( 0x2563EB)
    }

    // MARK: - 流量绿（对应 Web 端 emerald 色板，流量统计统一纯绿色）
    enum Traffic {
        static let bar = DS.hex( 0x10B981)        // emerald-500
        static let barStrong = DS.hex( 0x059669)  // emerald-600
        static let barSoft = DS.hex( 0x6EE7B7)    // emerald-300
        static let tracker = DS.hex( 0xD1FAE5)    // emerald-100
    }

    // MARK: - 提示横幅配色（对齐 Web 端 sonner richColors）
    struct ToastStyle {
        let background: Color
        let border: Color
        let foreground: Color
        let icon: String

        static func of(_ kind: BannerKind, dark: Bool) -> ToastStyle {
            switch (kind, dark) {
            case (.success, false):
                return ToastStyle(background: DS.hex( 0xECFDF5), border: DS.hex( 0xA7F3D0),
                                  foreground: DS.hex( 0x047857), icon: "checkmark.circle.fill")
            case (.success, true):
                return ToastStyle(background: DS.hex( 0x001A0F), border: DS.hex( 0x065F46),
                                  foreground: DS.hex( 0x4ADE80), icon: "checkmark.circle.fill")
            case (.error, false):
                return ToastStyle(background: DS.hex( 0xFEF2F2), border: DS.hex( 0xFECACA),
                                  foreground: DS.hex( 0xE7000B), icon: "octagon.fill")
            case (.error, true):
                return ToastStyle(background: DS.hex( 0x2D0607), border: DS.hex( 0x7F1D1D),
                                  foreground: DS.hex( 0xFF9B9D), icon: "octagon.fill")
            case (.warning, false):
                return ToastStyle(background: DS.hex( 0xFEFCE8), border: DS.hex( 0xFEF08A),
                                  foreground: DS.hex( 0xB45309), icon: "exclamationmark.triangle.fill")
            case (.warning, true):
                return ToastStyle(background: DS.hex( 0x1C1A00), border: DS.hex( 0x854D0E),
                                  foreground: DS.hex( 0xFCD34D), icon: "exclamationmark.triangle.fill")
            case (.info, false):
                return ToastStyle(background: DS.hex( 0xF0F9FF), border: DS.hex( 0xBAE6FD),
                                  foreground: DS.hex( 0x0369A1), icon: "info.circle.fill")
            case (.info, true):
                return ToastStyle(background: DS.hex( 0x001B33), border: DS.hex( 0x1E40AF),
                                  foreground: DS.hex( 0x60A5FA), icon: "info.circle.fill")
            }
        }
    }

    // MARK: - 功能图标配色（绿色系为主 + 少量协调强调色）
    enum IconColor {
        static let green = DS.hex( 0x10B981)      // 主绿
        static let mint = DS.hex( 0x34D399)       // 亮绿
        static let teal = DS.hex( 0x14B8A6)       // 青绿（邻近）
        static let tealDeep = DS.hex( 0x0F766E)
        static let lime = DS.hex( 0x84CC16)       // 黄绿（邻近）
        static let cyan = DS.hex( 0x06B6D4)       // 冷青（邻近）
        static let amber = DS.hex( 0xF59E0B)      // 琥珀（互补强调）
        static let orange = DS.hex( 0xFB923C)     // 橙（金币）
        static let rose = DS.hex( 0xF43F5E)       // 玫红（警示类入口）
        static let slate = DS.hex( 0x64748B)      // 中性
    }
}

// MARK: - 语义色（跟随系统明暗）
struct Palette {
    let scheme: ColorScheme

    private var isDark: Bool { scheme == .dark }

    var background: Color { isDark ? DS.Dark.background : DS.Light.background }
    var foreground: Color { isDark ? DS.Dark.foreground : DS.Light.foreground }
    var card: Color { isDark ? DS.Dark.card : DS.Light.card }
    var cardForeground: Color { isDark ? DS.Dark.cardForeground : DS.Light.cardForeground }
    var primary: Color { isDark ? DS.Dark.primary : DS.Light.primary }
    var primaryForeground: Color { isDark ? DS.Dark.primaryForeground : DS.Light.primaryForeground }
    var secondary: Color { isDark ? DS.Dark.secondary : DS.Light.secondary }
    var secondaryForeground: Color {
        isDark ? DS.Dark.secondaryForeground : DS.Light.secondaryForeground
    }
    var muted: Color { isDark ? DS.Dark.muted : DS.Light.muted }
    var mutedForeground: Color { isDark ? DS.Dark.mutedForeground : DS.Light.mutedForeground }
    var border: Color { isDark ? DS.Dark.border : DS.Light.border }
    var destructive: Color { isDark ? DS.Dark.destructive : DS.Light.destructive }

    var onlineBg: Color { DS.Status.onlineBg }
    var onlineText: Color { isDark ? DS.hex( 0x34D399) : DS.Status.onlineText }
    var offlineBg: Color { DS.Status.offlineBg }
    var offlineText: Color { isDark ? DS.hex( 0xF87171) : DS.Status.offlineText }
    var pendingBg: Color { isDark ? DS.Dark.muted : DS.Status.pendingBg }
    var pendingText: Color { isDark ? DS.Dark.mutedForeground : DS.Status.pendingText }
    var warningBg: Color { DS.Status.warningBg }
    var warningText: Color { isDark ? DS.hex( 0xFBBF24) : DS.Status.warningText }

    /// 次级文字：比 mutedForeground 更深，保证手机上的可读性
    var secondaryText: Color { isDark ? DS.hex( 0xC9CCD2) : DS.hex( 0x5A6068) }

    /// 流量统计统一纯绿色
    var trafficBar: Color { DS.Traffic.bar }
    var trafficTracker: Color { isDark ? DS.hex( 0x064E3B) : DS.Traffic.tracker }

    // MARK: 品牌渐变（按钮）
    var accentGradient: LinearGradient {
        isDark
            ? LinearGradient(colors: [DS.hex( 0x10B981), DS.hex( 0x047857)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [DS.Brand.primary, DS.Brand.primaryDeep],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var tealGradient: LinearGradient {
        isDark
            ? LinearGradient(colors: [DS.hex( 0x2DD4BF), DS.hex( 0x0F766E)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [DS.Brand.teal, DS.Brand.tealDeep],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var dangerGradient: LinearGradient {
        isDark
            ? LinearGradient(colors: [DS.hex( 0xFF7C80), DS.hex( 0xE5484D)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [DS.Brand.red, DS.Brand.redDeep],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 连接圆环使用的渐变（绿 → 青绿 → 冷青 → 黄绿）
    var connectionGradient: AngularGradient {
        AngularGradient(
            colors: [DS.Traffic.bar, DS.hex( 0x22D3EE), DS.Brand.teal,
                     DS.Brand.lime, DS.hex( 0x6EE7B7), DS.Traffic.bar],
            center: .center
        )
    }

    func toastStyle(_ kind: BannerKind) -> DS.ToastStyle { DS.ToastStyle.of(kind, dark: isDark) }
}

/// 供视图使用的环境简写
struct Themed<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: (Palette) -> Content

    init(@ViewBuilder content: @escaping (Palette) -> Content) {
        self.content = content
    }

    var body: some View {
        content(Palette(scheme: scheme))
    }
}