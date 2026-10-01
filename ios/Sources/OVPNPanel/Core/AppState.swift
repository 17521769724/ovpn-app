import Foundation
import SwiftUI

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

    init() {
        restore()
    }

    private func restore() {
        if let saved = LocalStore.masterURL, !saved.isEmpty {
            masterURL = saved
            api.setBaseURL(saved)
            if let token = SecureStore.load(), !token.isEmpty {
                api.setToken(token)
                phase = .main
                Task { await refreshUser() }
            } else {
                phase = .auth
            }
        } else {
            phase = .setup
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
        api.setToken(nil)
        SecureStore.clear()
        user = nil
        phase = .auth
        dismissToast()
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