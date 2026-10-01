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
    enum Style { case primary, secondary, outline, destructive }

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
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(foreground(palette))
                        .scaleEffect(0.8)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .medium))
                }
                Text(title).font(DS.Font.body).fontWeight(.medium)
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
        }
        .buttonStyle(.plain)
        .disabled(disabled || loading)
        .opacity(disabled ? 0.5 : 1)
    }

    private func foreground(_ palette: Palette) -> Color {
        switch style {
        case .primary: return palette.primaryForeground
        case .secondary: return palette.secondaryForeground
        case .outline: return palette.foreground
        case .destructive: return .white
        }
    }

    private func background(_ palette: Palette) -> Color {
        switch style {
        case .primary: return palette.primary
        case .secondary: return palette.secondary
        case .outline: return .clear
        case .destructive: return palette.destructive
        }
    }

    private func strokeColor(_ palette: Palette) -> Color {
        style == .outline ? palette.border : .clear
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
                .font(DS.Font.bodySmall)
                .padding(.horizontal, 12)
                .frame(height: DS.Size.buttonHeightSmall)
                .foregroundStyle(selected ? palette.primaryForeground : palette.foreground)
                .background(selected ? palette.primary : palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(palette.border, lineWidth: selected ? 0 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
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
            Text(title).font(DS.Font.bodySmall).foregroundStyle(palette.mutedForeground)
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
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card)
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
            .font(DS.Font.caption)
            .padding(.horizontal, 8)
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
            case "offline": return ("离线", palette.offlineBg, palette.offlineText)
            case "disabled": return ("已停用", palette.pendingBg, palette.pendingText)
            default: return ("待安装", palette.pendingBg, palette.pendingText)
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
                        .fill(palette.primary.opacity(0.75))
                        .frame(width: max(0, min(1, value / 100)) * geo.size.width)
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
                .font(DS.Font.number)
                .foregroundStyle(valueColor ?? palette.foreground)
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

/// 顶部提示条（错误/警告/成功）
struct BannerBar: View {
    let message: String
    var kind: Kind = .error

    enum Kind { case error, warning, success }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        let (bg, fg, icon): (Color, Color, String) = {
            switch kind {
            case .error: return (palette.offlineBg, palette.offlineText, "exclamationmark.circle")
            case .warning: return (palette.warningBg, palette.warningText, "info.circle")
            case .success: return (palette.onlineBg, palette.onlineText, "checkmark.circle")
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

/// 底部浮层提示
struct ToastView: View {
    let message: String

    @Environment(\.colorScheme) private var scheme

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