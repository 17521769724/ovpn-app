import Foundation
import SwiftUI

/// 全局应用状态：主控地址、登录态、用户信息
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
    @Published var banner: String?
    @Published var busy: Bool = false

    private let api = APIClient.shared

    init() {
        restore()
    }

    private func restore() {
        if let saved = LocalStore.masterURL, !saved.isEmpty {
            masterURL = saved
            api.setBaseURL(saved)
            if let token = Keychain.load(), !token.isEmpty {
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
    }

    func register(username: String, password: String, email: String) async throws {
        let result = try await api.register(username: username, password: password, email: email)
        applyAuth(result)
        LocalStore.lastAccount = username
    }

    private func applyAuth(_ result: AuthResult) {
        api.setToken(result.token)
        Keychain.save(result.token)
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
        Keychain.clear()
        user = nil
        phase = .auth
    }

    /// 切换主控（回到配置页）
    func resetMaster() {
        logout()
        LocalStore.masterURL = nil
        masterURL = ""
        phase = .setup
    }

    func toast(_ message: String) {
        banner = message
    }
}