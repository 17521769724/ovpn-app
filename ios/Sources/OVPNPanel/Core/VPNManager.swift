import Foundation
import NetworkExtension
import TunnelKit
import TunnelKitOpenVPN

/// VPN 连接管理：解析 .ovpn → 安装隧道配置 → 启动/停止 NetworkExtension 隧道
@MainActor
final class VPNManager: ObservableObject {
    static let shared = VPNManager()

    /// 与隧道扩展共享的 App Group（需在 entitlements 中声明）
    static let appGroup = "group.com.ovpn.panel"
    /// 隧道扩展的 Bundle Identifier
    static let tunnelBundleIdentifier = "com.ovpn.panel.tunnel"

    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var lastError: String?

    private var manager: NETunnelProviderManager?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncStatus()
            }
        }
    }

    // MARK: - 状态展示

    var statusText: String {
        switch status {
        case .connected: return "已连接"
        case .connecting: return "连接中…"
        case .disconnecting: return "正在断开…"
        case .reasserting: return "正在重连…"
        case .invalid: return "不可用"
        default: return "未连接"
        }
    }

    var isConnected: Bool { status == .connected }

    var isBusy: Bool {
        status == .connecting || status == .disconnecting || status == .reasserting
    }

    // MARK: - 隧道管理

    /// 加载已存在的隧道配置（首次为 nil）
    func prepare() async {
        manager = try? await loadManager()
        syncStatus()
    }

    private func loadManager() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == Self.tunnelBundleIdentifier
        }
    }

    private func syncStatus() {
        guard let manager else {
            status = .disconnected
            return
        }
        status = manager.connection.status
    }

    /// 使用主控下发的 .ovpn 配置建立连接
    func connect(profile: LineConfig, username: String, password: String) async throws {
        lastError = nil

        // 1) 解析 .ovpn（含证书、密钥、tls-crypt）
        let parsed = try OpenVPN.ConfigurationParser.parsed(fromContents: profile.content)
        let builder = parsed.configuration.builder()

        // 2) 组装隧道配置（凭据：用户名 + 钥匙串密码引用）
        let title = "\(profile.nodeName) · \(profile.lineName)"
        var providerConfiguration = OpenVPN.ProviderConfiguration(
            title,
            appGroup: Self.appGroup,
            configuration: builder.build()
        )
        providerConfiguration.username = username

        var extra = NetworkExtensionExtra()
        if let reference = try? Keychain(group: Self.appGroup)
            .set(password: password, for: username, context: Self.tunnelBundleIdentifier) {
            extra.passwordReference = reference
        }

        let protocolConfiguration = try providerConfiguration.asTunnelProtocol(
            withBundleIdentifier: Self.tunnelBundleIdentifier,
            extra: extra
        )
        // 钥匙串不可用时（如签名 entitlements 缺失）回退：由隧道扩展在自身进程内写入
        if extra.passwordReference == nil {
            protocolConfiguration.providerConfiguration?["__plain_password"] = password
        }

        // 3) 安装并启动
        let manager = try await loadManager() ?? NETunnelProviderManager()
        manager.localizedDescription = title
        manager.protocolConfiguration = protocolConfiguration
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        self.manager = manager

        try manager.connection.startVPNTunnel()
        syncStatus()
    }

    /// 断开连接（保留配置，便于下次快速连接）
    func disconnect() async {
        guard let manager else {
            await prepare()
            return
        }
        manager.connection.stopVPNTunnel()
        syncStatus()
    }
}