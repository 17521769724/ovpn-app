import SwiftUI
import OVPNPanel

/// iOS 应用入口。
///
/// 界面来自共享模块 `OVPNPanel`（与 Android 侧同一份 SwiftUI 代码，
/// 由 Skip 转译为 Jetpack Compose），这里只负责承载根视图。
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            OVPNPanelRootView()
        }
    }
}
