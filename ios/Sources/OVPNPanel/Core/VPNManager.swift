import Foundation
import NetworkExtension
import TunnelKit
import TunnelKitOpenVPN

/// VPN 连接管理：解析 .ovpn → 安装隧道配置 → 启动/停止 NetworkExtension 隧道
final class VPNManager: ObservableObject {
    static let shared = VPNManager()

    /// 与隧道扩展共享的 App Group（需在 entitlements 中声明）
    static let appGroup = "group.com.ovpn.panel"
    /// 隧道扩展的 Bundle Identifier
    static let tunnelBundleIdentifier = "com.ovpn.panel.tunnel"

    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var lastError: String?
    /// 当前会话的连接建立时间（由系统隧道提供，跨页面 / 冷启动 / 系统设置连接均有效）
    @Published private(set) var connectedAt: Date?
    /// 当前连接使用的服务器 / 线路名称（供「已连接」页展示，页面重建后仍可恢复）
    @Published private(set) var activeServerName: String = ""
    @Published private(set) var activeLineName: String = ""
    /// 当前连接所用节点 ID（用于绑定该会话的流量统计）
    @Published private(set) var activeNodeId: Int = 0

    private var manager: NETunnelProviderManager?
    private var observing = false

    /// 连接建立时间持久化：App 被杀/重启后仍能正确显示已连接时长
    private var storedConnectedAt: Date? {
        get {
            let value = UserDefaults.standard.double(forKey: "ovpn.session.connectedAt")
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: "ovpn.session.connectedAt")
            } else {
                UserDefaults.standard.removeObject(forKey: "ovpn.session.connectedAt")
            }
        }
    }

    /// 本地是否可能存在未关闭的主控在线会话（连接成功后置位，清理成功后复位）
    private var hasLikelyOpenSession: Bool {
        get { UserDefaults.standard.bool(forKey: "ovpn.session.likelyOpen") }
        set { UserDefaults.standard.set(newValue, forKey: "ovpn.session.likelyOpen") }
    }
    /// 最近一次会话清理时间（节流，避免重复请求）
    private var lastSessionCleanupAt: Date?

    private init() {}

    /// 开始监听系统 VPN 状态变化（首次进入线路页时调用）
    @MainActor
    func startObserving() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 观察者注册在 main queue，回调本身就在主线程
            self?.syncStatus()
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
    @MainActor
    func prepare() async {
        startObserving()
        manager = try? await loadManager()
        syncStatus()
    }

    /// App 回到前台 / 冷启动时调用：重新读取系统隧道状态，
    /// 并补偿清理「后台期间在系统设置里断开」遗留的主控在线会话。
    @MainActor
    func refreshStatus() async {
        startObserving()
        manager = try? await loadManager()
        syncStatus()
        if status == .disconnected || status == .invalid {
            await cleanupRemoteSessionsIfNeeded()
        }
    }

    private func loadManager() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == Self.tunnelBundleIdentifier
        }
    }

    private func syncStatus() {
        let previous = status
        if let manager {
            status = manager.connection.status
            // 页面重建后从隧道配置恢复服务器 / 线路名称（标题格式：服务器 ｜ 线路）
            if activeServerName.isEmpty, let title = manager.localizedDescription {
                applyTitle(title)
            }
        } else {
            status = .disconnected
        }

        // 连接建立时间：优先取系统隧道记录的时间（系统设置里建立的连接同样有效），
        // 并持久化，保证切换页面 / App 重启后计时不重置。
        if status == .connected {
            hasLikelyOpenSession = true
            let systemDate = manager?.connection.connectedDate
            if let systemDate {
                connectedAt = systemDate
                storedConnectedAt = systemDate
            } else if let stored = storedConnectedAt {
                connectedAt = stored
            } else {
                connectedAt = Date()
                storedConnectedAt = connectedAt
            }
        } else if status == .disconnected || status == .invalid {
            if connectedAt != nil { connectedAt = nil }
            storedConnectedAt = nil
        }

        // 从「已连接 / 断开中 / 重连中」落到断开：立刻关闭主控会话（含在系统设置中断开）
        let wasActive = previous == .connected || previous == .disconnecting || previous == .reasserting
        if (status == .disconnected || status == .invalid) && wasActive {
            Task { await cleanupRemoteSessionsIfNeeded(force: true) }
        }
    }

    /// 关闭主控侧在线会话（节流 30s；force 时忽略节流）。
    /// 仅在本地记录过「可能存在会话」时调用，避免误伤同账号其他设备。
    private func cleanupRemoteSessionsIfNeeded(force: Bool = false) async {
        guard hasLikelyOpenSession else { return }
        if !force, let last = lastSessionCleanupAt, Date().timeIntervalSince(last) < 30 { return }
        lastSessionCleanupAt = Date()
        try? await APIClient.shared.closeSessions()
        hasLikelyOpenSession = false
    }

    /// 解析「服务器 ｜ 线路」标题（兼容旧版本的 " · " 分隔）
    private func applyTitle(_ title: String) {
        var parts = title.components(separatedBy: " ｜ ")
        if parts.count < 2 {
            parts = title.components(separatedBy: " · ")
        }
        activeServerName = parts.first ?? title
        activeLineName = parts.count > 1 ? parts[1] : ""
    }

    /// 使用主控下发的 .ovpn 配置建立连接
    @MainActor
    func connect(profile: LineConfig, username: String, password: String) async throws {
        lastError = nil

        // 1) 解析 .ovpn（含证书、密钥、tls-crypt）
        let parsed = try OpenVPN.ConfigurationParser.parsed(fromContents: profile.content)
        let builder = parsed.configuration.builder()

        // 2) 组装隧道配置（凭据：用户名 + 钥匙串密码引用）
        let title = "\(profile.nodeName) ｜ \(profile.lineName)"
        activeServerName = profile.nodeName
        activeLineName = profile.lineName
        activeNodeId = profile.nodeId
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
    @MainActor
    func disconnect() async {
        guard let manager else {
            await prepare()
            return
        }
        manager.connection.stopVPNTunnel()
        syncStatus()
    }
}