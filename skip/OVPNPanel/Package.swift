// swift-tools-version: 6.1
import PackageDescription

// Skip Lite 模式（默认）：SwiftUI 源码被转译为 Kotlin + Jetpack Compose，
// iOS 侧仍为原生 SwiftUI。UI 层完全共享，不再维护两套界面代码。
//
// 平台要求与 SkipUI 保持一致（iOS 16 起），与改造前的部署目标一致。
let package = Package(
    name: "ovpn-panel",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Skip 要求被转译的模块以 dynamic library 形式产出
        .library(name: "OVPNPanel", type: .dynamic, targets: ["OVPNPanel"]),
    ],
    dependencies: [
        // SwiftUI → Jetpack Compose 的兼容层（含 .sheet / presentationDetents / NavigationStack 等）
        .package(url: "https://github.com/skiptools/skip-ui.git", from: "1.61.0"),
        // Foundation（URLSession / UserDefaults / NotificationCenter）跨平台适配
        .package(url: "https://github.com/skiptools/skip-foundation.git", from: "1.4.6"),
        // Combine 的 ObservableObject / @Published 跨平台适配
        .package(url: "https://github.com/skiptools/skip-model.git", from: "1.8.0"),
        // Skip 工具链（提供 skipstone 转译插件）
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.13"),
        // iOS 侧隧道内核（与 Darwin 工程使用的 fork 版本保持一致）。
        // 仅在 iOS 平台参与构建：Android 侧走 Kotlin VpnBridge，不引用该依赖。
        .package(url: "https://github.com/17521769724/tunnelkit",
                 revision: "db03b9d5af783c40738a187cce3612c4259b2b3a"),
    ],
    targets: [
        .target(
            name: "OVPNPanel",
            dependencies: [
                .product(name: "SkipUI", package: "skip-ui"),
                .product(name: "SkipFoundation", package: "skip-foundation"),
                .product(name: "SkipModel", package: "skip-model"),
                // Darwin（iOS）侧 VPNManager 需要，Android 端由 #if SKIP 分支剥离
                .product(name: "TunnelKit", package: "TunnelKit", condition: .when(platforms: [.iOS])),
                .product(name: "TunnelKitOpenVPN", package: "TunnelKit", condition: .when(platforms: [.iOS])),
            ],
            resources: [.process("Resources")],
            // 与 Darwin 工程保持一致（SWIFT_VERSION 5.0）：
            // 否则 swift-tools-version 6.x 会默认启用 Swift 6 严格并发检查，
            // 导致 UIKit / NetworkExtension / 单例等既有写法被判定为编译错误。
            swiftSettings: [.swiftLanguageMode(.v5)],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
