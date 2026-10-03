import SwiftUI

/// 应用根视图（共享层）。
///
/// Skip 约定：
/// - iOS 由 `Darwin/Sources/Main.swift` 中的 `@main` 外壳加载本视图；
/// - Android 由 Skip 生成的 `MainActivity` 加载本视图。
///
/// `// SKIP @bridge` 标记该成员需要暴露给原生侧调用。
// SKIP @bridge
public struct OVPNPanelRootView: View {
    @StateObject private var app = AppState()

    // SKIP @bridge
    public init() {
    }

    public var body: some View {
        RootView()
            .environmentObject(app)
            .preferredColorScheme(nil)
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let palette = Palette(scheme: scheme)
        ZStack {
            switch app.phase {
            case .setup:
                SetupView()
            case .auth:
                LoginView()
            case .main:
                MainTabView()
            }

            // 全局横幅提示（与 Web 端 toast 一致）
            ToastHost()
        }
        // 全局统一导航色调：返回按钮 / 链接使用主题绿，不使用黑色或系统蓝
        .tint(palette.primary)
        // 冷启动：同步系统 VPN 状态，并补偿清理上次遗留的主控在线会话
        .task { await VPNManager.shared.refreshStatus() }
        // 回到前台：重新同步系统 VPN 状态（在「设置」里连接/断开也能正确反映到 App）
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await VPNManager.shared.refreshStatus() }
            }
        }
    }
}

/// 主界面：自定义底部导航（三端样式统一）
struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var tab: Int = LaunchArgs.startTab

    private let items: [(icon: String, activeIcon: String, title: String, color: Color)] = [
        ("bolt.horizontal.circle", "bolt.horizontal.circle.fill", "线路", DS.IconColor.green),
        ("shippingbox", "shippingbox.fill", "套餐", DS.IconColor.teal),
        ("person.badge.plus", "person.badge.plus", "邀请", DS.IconColor.lime),
        ("person.crop.circle", "person.crop.circle.fill", "我的", DS.IconColor.cyan),
    ]

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 0) {
            Group {
                switch tab {
                case 0:
                    NavigationStack { HomeView() }
                case 1:
                    NavigationStack { PlansView() }
                case 2:
                    NavigationStack { InviteView() }
                default:
                    NavigationStack { ProfileView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar(palette)
        }
        .pageBackground()
        .tint(palette.primary)
    }

    private func tabBar(_ palette: Palette) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.indices), id: \.self) { index in
                let item = items[index]
                Button {
                    withAnimation(Animation.spring(response: 0.32, dampingFraction: 0.82)) { tab = index }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab == index ? item.activeIcon : item.icon)
                            .font(.system(size: 19, weight: tab == index ? .semibold : .regular))
                            .foregroundStyle(tab == index ? item.color : palette.mutedForeground)
                            .scaleEffect(tab == index ? 1.06 : 1.0)
                        Text(item.title)
                            .font(.system(size: 11, weight: tab == index ? .semibold : .regular))
                            .foregroundStyle(tab == index ? palette.foreground : palette.mutedForeground)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.Size.tabBarHeight)
#if !SKIP
                    .contentShape(Rectangle())
#endif
                }
                .pressableStyle(scale: 0.88)
            }
        }
        .background(palette.background)
        .overlay(Rectangle().fill(palette.border).frame(height: 1), alignment: .top)
    }
}
