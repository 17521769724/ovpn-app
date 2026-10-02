import SwiftUI
import UIKit
import SafariServices

// MARK: - 内置浏览器（支付跳转用）

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onClose() }
    }
}

// MARK: - 交互反馈（仅保留：下拉刷新 / 连接 / 断开）

enum Haptics {
    /// 下拉刷新触发时的轻微反馈
    static func refresh() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }

    /// 线路连接成功
    static func connected() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 线路连接失败
    static func connectFailed() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// 断开线路
    static func disconnected() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// 卡片/列表行等自定义可点元素的按下反馈（仅缩放，不震动）
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 页面容器

struct PageBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        Palette(scheme: scheme).background.ignoresSafeArea().overlay(content)
    }
}

extension View {
    func pageBackground() -> some View { modifier(PageBackground()) }
}

// MARK: - 按钮

struct AppButton: View {
    enum Style { case primary, accent, secondary, outline, destructive }

    let title: String
    var icon: String?
    var style: Style = .primary
    var height: CGFloat = DS.Size.buttonHeight
    var loading: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        Button {
            action()
        } label: {
            HStack(spacing: 6) {
                if loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(foreground(palette))
                        .scaleEffect(0.8)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .foregroundStyle(foreground(palette))
            .background(background(palette))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(strokeColor(palette), lineWidth: style == .outline ? 1 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .shadow(color: shadowColor(palette), radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled || loading)
        .opacity(disabled ? 0.5 : 1)
    }

    private func foreground(_ palette: Palette) -> Color {
        switch style {
        case .primary, .accent, .destructive: return .white
        case .secondary: return palette.secondaryForeground
        case .outline: return palette.foreground
        }
    }

    @ViewBuilder
    private func background(_ palette: Palette) -> some View {
        switch style {
        case .primary: palette.accentGradient
        case .accent: palette.tealGradient
        case .secondary: palette.secondary
        case .outline: palette.card
        case .destructive: palette.dangerGradient
        }
    }

    private func strokeColor(_ palette: Palette) -> Color {
        style == .outline ? palette.border : .clear
    }

    private func shadowColor(_ palette: Palette) -> Color {
        switch style {
        case .primary: return DS.Brand.green.opacity(0.28)
        case .accent: return DS.Brand.teal.opacity(0.26)
        case .destructive: return DS.Brand.red.opacity(0.24)
        default: return .clear
        }
    }
}

/// 小尺寸标签按钮（分类筛选等）
struct ChipButton: View {
    let title: String
    var selected: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .frame(height: DS.Size.buttonHeightSmall)
                .foregroundStyle(selected ? .white : palette.foreground)
                .background(selected ? AnyView(palette.accentGradient) : AnyView(palette.card))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(palette.border, lineWidth: selected ? 0 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(PressableStyle())
    }
}

/// 竖线分隔符（全局替代 "·" 点分割）
struct VLine: View {
    var height: CGFloat = 10
    var color: Color?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(color ?? Palette(scheme: scheme).mutedForeground.opacity(0.38))
            .frame(width: 1, height: height)
    }
}

/// 分段切换（流量 近 7 天 / 近 15 天）
/// 固定分段宽度 + 固定字重 + 无位移动画：文字不可能被压缩/截断（避免「近15天」显示成「15」）
struct SegmentedTabs: View {
    let items: [String]
    @Binding var selection: Int
    /// 每个分段的固定宽度（按最长文案留足空间）
    var segmentWidth: CGFloat = 82

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    selection = index
                } label: {
                    Text(item)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == index ? palette.primary : palette.mutedForeground)
                        .frame(width: segmentWidth, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .fill(selection == index ? palette.card : Color.clear)
                                .shadow(color: .black.opacity(selection == index ? 0.08 : 0), radius: 3, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.96))
            }
        }
        .padding(2)
        .background(palette.muted)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }
}

// MARK: - 输入框

struct AppTextField: View {
    let title: String
    var placeholder: String = ""
    @Binding var text: String
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(DS.Font.bodySmall).foregroundStyle(palette.secondaryText)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .font(DS.Font.body)
            .foregroundStyle(palette.foreground)
            .padding(.horizontal, 12)
            .frame(height: DS.Size.inputHeight)
            .background(palette.background)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
    }
}

// MARK: - 卡片

struct AppCard<Content: View>: View {
    var padding: CGFloat = DS.Size.cardPadding
    /// 自定义卡片底色（传 nil 时使用常规卡片色；不可点击的场景使用柔和灰底）
    var background: Color?
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background ?? palette.card)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .stroke(palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
    }
}

// MARK: - 徽章与状态

struct StatusBadge: View {
    let text: String
    let background: Color
    let foreground: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }
}

struct NodeStatusBadge: View {
    let status: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        let (text, bg, fg): (String, Color, Color) = {
            switch status {
            case "online": return ("在线", palette.onlineBg, palette.onlineText)
            case "disabled": return ("已停用", palette.pendingBg, palette.pendingText)
            // 离线 / 未对接（pending）统一显示为「离线」，不暴露安装状态
            default: return ("离线", palette.offlineBg, palette.offlineText)
            }
        }()
        StatusBadge(text: text, background: bg, foreground: fg)
    }
}

/// 细进度条（对应 Web 端 MiniStat）
struct StatBar: View {
    let label: String
    let value: Double   // 0-100
    var icon: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 11)) }
                Text(label)
            }
            .font(DS.Font.caption)
            .foregroundStyle(palette.mutedForeground)
            .frame(width: 56, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.muted)
                    Capsule()
                        .fill(palette.accentGradient)
                        .frame(width: max(0, min(1, value / 100)) * geo.size.width)
                        .animation(.easeOut(duration: 0.5), value: value)
                }
            }
            .frame(height: 6)

            Text(String(format: "%.0f%%", value))
                .font(DS.Font.caption)
                .monospacedDigit()
                .foregroundStyle(palette.mutedForeground)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - 列表行与区块

struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(alignment: .top) {
            Text(label).font(DS.Font.bodySmall).foregroundStyle(palette.mutedForeground)
            Spacer(minLength: 12)
            Text(value)
                .font(DS.Font.value)
                // 默认使用柔和的次级文字色，避免右侧数值过黑、与整体不协调
                .foregroundStyle(valueColor ?? palette.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(DS.Font.section).foregroundStyle(palette.foreground)
            if let subtitle {
                Text(subtitle).font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
            }
        }
    }
}

struct EmptyHint: View {
    let icon: String
    let title: String
    var detail: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(palette.mutedForeground)
            Text(title).font(DS.Font.body).foregroundStyle(palette.mutedForeground)
            if let detail {
                Text(detail).font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

struct LoadingBlock: View {
    var text: String = "加载中…"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.9)
            Text(text).font(DS.Font.bodySmall).foregroundStyle(palette.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - 提示

/// 提示类型（内联提示条与全局横幅共用）
enum BannerKind {
    case success, error, warning, info
}

/// 页面内常驻提示条
struct BannerBar: View {
    let message: String
    var kind: BannerKind = .error

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        let (bg, fg, icon): (Color, Color, String) = {
            switch kind {
            case .error: return (palette.offlineBg, palette.offlineText, "exclamationmark.circle")
            case .warning: return (palette.warningBg, palette.warningText, "info.circle")
            case .success: return (palette.onlineBg, palette.onlineText, "checkmark.circle")
            case .info: return (palette.muted, palette.secondaryText, "info.circle")
            }
        }()
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.system(size: 13))
            Text(message).font(DS.Font.caption)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(bg)
        .foregroundStyle(fg)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let kind: BannerKind
}

struct ToastCard: View {
    let message: ToastMessage

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        let style = palette.toastStyle(message.kind)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: style.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(style.foreground)
            Text(message.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(style.foreground)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(style.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
    }
}

/// 顶部横幅宿主：负责展示与自动消失
/// 入场使用轻微缩放 + 淡入（不做位移），避免出现「文字先到、图标随后滑落」的渲染瑕疵
struct ToastHost: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack {
            if let toast = app.toast {
                ToastCard(message: toast)
                    .padding(.horizontal, DS.Size.pagePadding)
                    .padding(.top, 6)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.97, anchor: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .onTapGesture { app.dismissToast() }
            }
            Spacer()
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: app.toast)
        .allowsHitTesting(app.toast != nil)
    }
}

// MARK: - 彩色图标块（多色美化）

struct IconTile: View {
    let icon: String
    var color: Color = DS.IconColor.cyan
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3)
            .fill(
                LinearGradient(colors: [color.opacity(0.22), color.opacity(0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(color)
            )
    }
}

/// 个人中心等列表行（整行可点击）
struct MenuRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String?
    var badge: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(spacing: 12) {
            IconTile(icon: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.body)
                    .foregroundStyle(palette.foreground)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DS.Font.caption)
                        .foregroundStyle(palette.mutedForeground)
                }
            }
            Spacer(minLength: 8)
            if let badge, !badge.isEmpty {
                StatusBadge(text: badge, background: iconColor.opacity(0.14), foreground: iconColor)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.mutedForeground.opacity(0.8))
        }
        .padding(.horizontal, DS.Size.cardPadding)
        .frame(height: 58)
        .contentShape(Rectangle())
    }
}

/// 底部浮层提示
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(DS.Font.bodySmall)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .padding(.bottom, 28)
            .transition(.opacity)
    }
}