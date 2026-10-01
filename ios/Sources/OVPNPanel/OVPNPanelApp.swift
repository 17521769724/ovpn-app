import SwiftUI

@main
struct OVPNPanelApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(nil)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

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
        // 全局统一导航/按钮色调：返回按钮与链接不再使用系统蓝色
        .tint(palette.foreground)
    }
}

/// 主界面：自定义底部导航（三端样式统一）
struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var tab: Int = 0

    private let items: [(icon: String, activeIcon: String, title: String, color: Color)] = [
        ("bolt.horizontal.circle", "bolt.horizontal.circle.fill", "线路", DS.IconColor.sky),
        ("shippingbox", "shippingbox.fill", "套餐", DS.IconColor.violet),
        ("person.crop.circle", "person.crop.circle.fill", "我的", DS.IconColor.emerald),
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
                default:
                    NavigationStack { ProfileView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar(palette)
        }
        .pageBackground()
        .tint(palette.foreground)
    }

    private func tabBar(_ palette: Palette) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    tab = index
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab == index ? item.activeIcon : item.icon)
                            .font(.system(size: 19, weight: tab == index ? .semibold : .regular))
                            .foregroundStyle(tab == index ? item.color : palette.mutedForeground)
                        Text(item.title)
                            .font(.system(size: 11, weight: tab == index ? .semibold : .regular))
                            .foregroundStyle(tab == index ? palette.foreground : palette.mutedForeground)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.Size.tabBarHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(palette.background)
        .overlay(Rectangle().fill(palette.border).frame(height: 1), alignment: .top)
    }
}