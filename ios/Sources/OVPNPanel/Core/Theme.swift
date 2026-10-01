import SwiftUI

/// 三端统一设计令牌（与 Web 端 globals.css 一一对应，改动需三端同步）
/// Web 端基准：--radius: 0.625rem (=10px)，Tailwind 语义色。
enum DS {

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
        static let buttonHeight: CGFloat = 48     // 主操作按钮高度
        static let buttonHeightSmall: CGFloat = 34 // 次级/小按钮
        static let inputHeight: CGFloat = 48      // 输入框高度
        static let cardPadding: CGFloat = 16
        static let pagePadding: CGFloat = 16
        static let gap: CGFloat = 12
        static let gapLarge: CGFloat = 16
        static let tabBarHeight: CGFloat = 56
    }

    // MARK: - 字号
    enum Font {
        static let title = SwiftUI.Font.system(size: 20, weight: .semibold)
        static let section = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 15)
        static let bodySmall = SwiftUI.Font.system(size: 13)
        static let caption = SwiftUI.Font.system(size: 12)
        static let number = SwiftUI.Font.system(size: 15, weight: .medium).monospacedDigit()
    }

    // MARK: - 颜色（亮色）
    enum Light {
        static let background = Color(hex: 0xFFFFFF)
        static let foreground = Color(hex: 0x0A0A0A)
        static let card = Color(hex: 0xFFFFFF)
        static let cardForeground = Color(hex: 0x0A0A0A)
        static let primary = Color(hex: 0x171717)
        static let primaryForeground = Color(hex: 0xFAFAFA)
        static let secondary = Color(hex: 0xF5F5F5)
        static let secondaryForeground = Color(hex: 0x171717)
        static let muted = Color(hex: 0xF5F5F5)
        static let mutedForeground = Color(hex: 0x737373)
        static let border = Color(hex: 0xE5E5E5)
        static let destructive = Color(hex: 0xE7000B)
    }

    // MARK: - 颜色（暗色）
    enum Dark {
        static let background = Color(hex: 0x0A0A0A)
        static let foreground = Color(hex: 0xFAFAFA)
        static let card = Color(hex: 0x171717)
        static let cardForeground = Color(hex: 0xFAFAFA)
        static let primary = Color(hex: 0xE5E5E5)
        static let primaryForeground = Color(hex: 0x171717)
        static let secondary = Color(hex: 0x262626)
        static let secondaryForeground = Color(hex: 0xFAFAFA)
        static let muted = Color(hex: 0x262626)
        static let mutedForeground = Color(hex: 0xA1A1A1)
        static let border = Color.white.opacity(0.1)
        static let destructive = Color(hex: 0xFF6467)
    }

    // MARK: - 状态色（Tailwind 色板，与 Web 端一致）
    enum Status {
        static let onlineBg = Color(hex: 0x10B981).opacity(0.15)
        static let onlineText = Color(hex: 0x059669)
        static let offlineBg = Color(hex: 0xEF4444).opacity(0.15)
        static let offlineText = Color(hex: 0xDC2626)
        static let pendingBg = Color(hex: 0xE5E5E5)
        static let pendingText = Color(hex: 0x737373)
        static let warningBg = Color(hex: 0xF59E0B).opacity(0.14)
        static let warningText = Color(hex: 0xB45309)
        static let infoText = Color(hex: 0x2563EB)
    }

    // MARK: - 流量绿（对应 Web 端 emerald 色板，流量统计统一纯绿色）
    enum Traffic {
        static let bar = Color(hex: 0x10B981)        // emerald-500
        static let barStrong = Color(hex: 0x059669)  // emerald-600
        static let barSoft = Color(hex: 0x6EE7B7)    // emerald-300
        static let tracker = Color(hex: 0xD1FAE5)    // emerald-100
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
                return ToastStyle(background: Color(hex: 0xECFDF5), border: Color(hex: 0xA7F3D0),
                                  foreground: Color(hex: 0x047857), icon: "checkmark.circle.fill")
            case (.success, true):
                return ToastStyle(background: Color(hex: 0x001A0F), border: Color(hex: 0x065F46),
                                  foreground: Color(hex: 0x4ADE80), icon: "checkmark.circle.fill")
            case (.error, false):
                return ToastStyle(background: Color(hex: 0xFEF2F2), border: Color(hex: 0xFECACA),
                                  foreground: Color(hex: 0xE7000B), icon: "octagon.fill")
            case (.error, true):
                return ToastStyle(background: Color(hex: 0x2D0607), border: Color(hex: 0x7F1D1D),
                                  foreground: Color(hex: 0xFF9B9D), icon: "octagon.fill")
            case (.warning, false):
                return ToastStyle(background: Color(hex: 0xFEFCE8), border: Color(hex: 0xFEF08A),
                                  foreground: Color(hex: 0xB45309), icon: "exclamationmark.triangle.fill")
            case (.warning, true):
                return ToastStyle(background: Color(hex: 0x1C1A00), border: Color(hex: 0x854D0E),
                                  foreground: Color(hex: 0xFCD34D), icon: "exclamationmark.triangle.fill")
            case (.info, false):
                return ToastStyle(background: Color(hex: 0xF0F9FF), border: Color(hex: 0xBAE6FD),
                                  foreground: Color(hex: 0x0369A1), icon: "info.circle.fill")
            case (.info, true):
                return ToastStyle(background: Color(hex: 0x001B33), border: Color(hex: 0x1E40AF),
                                  foreground: Color(hex: 0x60A5FA), icon: "info.circle.fill")
            }
        }
    }

    // MARK: - 功能图标配色（多色美化，个人中心/入口通用）
    enum IconColor {
        static let blue = Color(hex: 0x3B82F6)
        static let indigo = Color(hex: 0x6366F1)
        static let violet = Color(hex: 0x8B5CF6)
        static let emerald = Color(hex: 0x10B981)
        static let teal = Color(hex: 0x14B8A6)
        static let amber = Color(hex: 0xF59E0B)
        static let orange = Color(hex: 0xF97316)
        static let rose = Color(hex: 0xF43F5E)
        static let sky = Color(hex: 0x0EA5E9)
        static let slate = Color(hex: 0x64748B)
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
    var onlineText: Color { isDark ? Color(hex: 0x34D399) : DS.Status.onlineText }
    var offlineBg: Color { DS.Status.offlineBg }
    var offlineText: Color { isDark ? Color(hex: 0xF87171) : DS.Status.offlineText }
    var pendingBg: Color { isDark ? DS.Dark.muted : DS.Status.pendingBg }
    var pendingText: Color { isDark ? DS.Dark.mutedForeground : DS.Status.pendingText }
    var warningBg: Color { DS.Status.warningBg }
    var warningText: Color { isDark ? Color(hex: 0xFBBF24) : DS.Status.warningText }

    /// 次级文字：比 mutedForeground 更深，保证手机上的可读性
    var secondaryText: Color { isDark ? Color(hex: 0xD4D4D4) : Color(hex: 0x404040) }

    /// 流量统计统一纯绿色
    var trafficBar: Color { DS.Traffic.bar }
    var trafficTracker: Color { isDark ? Color(hex: 0x064E3B) : DS.Traffic.tracker }

    func toastStyle(_ kind: BannerKind) -> DS.ToastStyle { DS.ToastStyle.of(kind, dark: isDark) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
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