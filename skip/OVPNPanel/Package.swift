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
    ],
    targets: [
        .target(
            name: "OVPNPanel",
            dependencies: [
                .product(name: "SkipUI", package: "skip-ui"),
                .product(name: "SkipFoundation", package: "skip-foundation"),
                .product(name: "SkipModel", package: "skip-model"),
            ],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
