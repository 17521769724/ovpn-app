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

    var body: some View {
        ZStack {
            switch app.phase {
            case .setup:
                SetupView()
            case .auth:
                LoginView()
            case .main:
                MainTabView()
            }

            if let banner = app.banner {
                VStack {
                    Spacer()
                    ToastView(message: banner)
                }
                .allowsHitTesting(false)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        if app.banner == banner { app.banner = nil }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: app.banner)
    }
}

/// 主界面：自定义底部导航（三端样式统一）
struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var tab: Int = 0

    private let items: [(icon: String, title: String)] = [
        ("bolt.horizontal.circle", "线路"),
        ("shippingbox", "套餐"),
        ("person.crop.circle", "我的"),
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
    }

    private func tabBar(_ palette: Palette) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    tab = index
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: tab == index ? .semibold : .regular))
                        Text(item.title).font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.Size.tabBarHeight)
                    .foregroundStyle(tab == index ? palette.foreground : palette.mutedForeground)
                }
                .buttonStyle(.plain)
            }
        }
        .background(palette.background)
        .overlay(Rectangle().fill(palette.border).frame(height: 1), alignment: .top)
    }
}