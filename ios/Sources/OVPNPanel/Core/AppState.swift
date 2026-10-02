import Foundation
import SwiftUI

/// 启动参数（仅供 CI 自动化界面检查 / 本地调试使用，正常启动不带参数时完全不生效）
enum LaunchArgs {
    static func value(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    /// 启动后直接展示的 Tab（0 线路 / 1 套餐 / 2 邀请 / 3 我的）
    static var startTab: Int {
        guard let raw = value("-startTab"), let value = Int(raw) else { return 0 }
        return max(0, min(3, value))
    }
}

/// 全局应用状态：主控地址、登录态、用户信息、全局横幅提示
@MainActor
final class AppState: ObservableObject {

    enum Phase {
        case setup   // 未配置主控地址
        case auth    // 已配置主控，等待登录
        case main    // 已登录
    }

    @Published var phase: Phase = .setup
    @Published var masterURL: String = ""
    @Published var user: AppUser?
    @Published var toast: ToastMessage?
    @Published var busy: Bool = false

    private let api = APIClient.shared
    private var toastToken = UUID()
    private var statusTask: Task<Void, Never>?
    private var lastNoticeKey: String?

    init() {
        restore()
        applyLaunchOverrides()
    }

    private func restore() {
        if let saved = LocalStore.masterURL, !saved.isEmpty {
            masterURL = saved
            api.setBaseURL(saved)
            if let token = SecureStore.load(), !token.isEmpty {
                api.setToken(token)
                phase = .main
                Task { await refreshUser() }
                startStatusPolling()
            } else {
                phase = .auth
            }
        } else {
            phase = .setup
        }
    }

    /// 启动参数覆盖（CI 界面检查）：-masterURL / -autoLogin user:pass
    private func applyLaunchOverrides() {
        guard let rawURL = LaunchArgs.value("-masterURL"), !rawURL.isEmpty else { return }
        let normalized = normalize(rawURL)
        masterURL = normalized
        LocalStore.masterURL = normalized
        api.setBaseURL(normalized)
        phase = .auth
        if let credentials = LaunchArgs.value("-autoLogin") {
            let parts = credentials.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            Task { try? await login(account: parts[0], password: parts[1]) }
        }
    }

    /// 校验并保存主控地址（可达即视为合法主控）
    func configureMaster(_ url: String) async throws {
        let normalized = normalize(url)
        guard let probeURL = URL(string: normalized + "/api/v1/lines") else {
            throw APIError.badURL
        }
        var request = URLRequest(url: probeURL)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if APIError.from(error).isCancelled { throw APIError.cancelled }
            throw APIError.network("无法连接该地址：\(error.localizedDescription)")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 主控对未登录请求会返回 401 + 统一包裹；只要能解析出 code 字段即认定为主控
        let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let isMaster = decoded?["code"] != nil
        guard isMaster || (200...299).contains(status) else {
            throw APIError.server("该地址不是有效的主控（HTTP \(status)）")
        }

        masterURL = normalized
        LocalStore.masterURL = normalized
        api.setBaseURL(normalized)
        phase = .auth
    }

    private func normalize(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "http://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    func login(account: String, password: String) async throws {
        let result = try await api.login(username: account, password: password)
        applyAuth(result)
        LocalStore.lastAccount = account
        // 保存连接 VPN 用的登录密码（OpenVPN 采用账号密码认证）
        SecureStore.save(password, account: SecureStore.passwordAccount)
    }

    func register(username: String, password: String, email: String,
                  captchaToken: String, captchaInput: String) async throws {
        let result = try await api.register(username: username, password: password, email: email,
                                            captchaToken: captchaToken, captchaInput: captchaInput)
        applyAuth(result)
        LocalStore.lastAccount = username
        SecureStore.save(password, account: SecureStore.passwordAccount)
    }

    private func applyAuth(_ result: AuthResult) {
        api.setToken(result.token)
        SecureStore.save(result.token)
        user = result.user
        phase = .main
        startStatusPolling()
    }

    func refreshUser() async {
        do {
            let center = try await api.fetchUserCenter()
            user = center.user
        } catch {
            if case APIError.server(let message) = error, message.contains("未登录") {
                logout()
            }
        }
    }

    func logout() {
        stopStatusPolling()
        api.setToken(nil)
        SecureStore.clear()
        user = nil
        phase = .auth
        dismissToast()
    }

    // MARK: - 账号异常状态轮询（被管理员断开 / 套餐到期 / 流量耗尽 / 封禁）

    func startStatusPolling() {
        statusTask?.cancel()
        lastNoticeKey = nil
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollStatus()
                // 轮询间隔 8s：被管理员断开等异常能较快以横幅提示
                try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
            }
        }
    }

    func stopStatusPolling() {
        statusTask?.cancel()
        statusTask = nil
    }

    /// 立即检查一次（连接失败、下单后等需要即时反馈的场景）
    func checkStatusNow() async {
        await pollStatus()
    }

    private func pollStatus() async {
        guard phase == .main else { return }
        guard let payload = try? await api.fetchUserStatus() else { return }
        guard let notice = payload.notice else {
            // 状态恢复正常，允许下次同样的问题重新提示
            lastNoticeKey = nil
            return
        }
        guard notice.key != lastNoticeKey else { return }
        lastNoticeKey = notice.key

        let kind: BannerKind = (notice.code == "blocked" || notice.code == "banned"
                                || notice.code == "expired" || notice.code == "over_quota")
            ? .error : .warning
        showToast(notice.message, kind: kind)

        // 被管理员断开 / 封禁：本地同步断开隧道，避免界面仍停留在「已连接」
        if notice.code == "blocked" || notice.code == "banned" {
            await VPNManager.shared.disconnect()
        }
        if payload.quota?.valid != true { await refreshUser() }
    }

    /// 切换主控（回到配置页）
    func resetMaster() {
        logout()
        LocalStore.masterURL = nil
        masterURL = ""
        phase = .setup
    }

    // MARK: - 全局横幅提示（与 Web 端 toast 一致）

    /// 非隔离入口：任何上下文都能直接调用（内部切回主线程更新 UI）
    nonisolated func showToast(_ message: String, kind: BannerKind = .info) {
        Task { @MainActor in
            self.presentToast(message, kind: kind)
        }
    }

    /// 统一错误上报：取消类错误静默忽略，其余以红色横幅提示
    nonisolated func report(_ error: Error) {
        let apiError = APIError.from(error)
        if apiError.isCancelled { return }
        showToast(apiError.localizedDescription, kind: .error)
    }

    func dismissToast() {
        toastToken = UUID()
        withAnimation(.easeInOut(duration: 0.18)) { toast = nil }
    }

    private func presentToast(_ message: String, kind: BannerKind) {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let token = UUID()
        toastToken = token
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            toast = ToastMessage(text: value, kind: kind)
        }
        let duration: Double = kind == .error ? 3.6 : 2.6
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.dismissToast()
        }
    }
}