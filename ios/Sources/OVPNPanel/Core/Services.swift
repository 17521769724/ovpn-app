import Foundation
import Security

// MARK: - 本地存储

enum LocalStore {
    private static let masterKey = "ovpn.master.url"
    private static let accountKey = "ovpn.last.account"

    static var masterURL: String? {
        get { UserDefaults.standard.string(forKey: masterKey) }
        set { UserDefaults.standard.set(newValue, forKey: masterKey) }
    }

    static var lastAccount: String? {
        get { UserDefaults.standard.string(forKey: accountKey) }
        set { UserDefaults.standard.set(newValue, forKey: accountKey) }
    }
}

/// 令牌安全存储（Keychain）
enum Keychain {
    private static let service = "com.ovpn.panel"
    private static let account = "app.token"

    static func save(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 主控接口

extension APIClient {

    // 认证
    func login(username: String, password: String) async throws -> AuthResult {
        try await request("/api/v1/auth/login", method: "POST",
                          body: ["username": username, "password": password], as: AuthResult.self)
    }

    func register(username: String, password: String, email: String) async throws -> AuthResult {
        try await request("/api/v1/auth/register", method: "POST",
                          body: ["username": username, "password": password, "email": email],
                          as: AuthResult.self)
    }

    func forgotQuestion(account: String) async throws -> String {
        let result = try await request("/api/v1/auth/forgot", method: "POST",
                                       body: ["account": account], as: SimpleResult.self)
        return result.question ?? ""
    }

    func resetPassword(account: String, answer: String, newPassword: String) async throws {
        try await requestVoid("/api/v1/auth/reset-password", method: "POST",
                              body: ["account": account, "answer": answer, "newPassword": newPassword])
    }

    // 服务器与线路
    func fetchLines() async throws -> LinesPayload {
        try await request("/api/v1/lines", as: LinesPayload.self)
    }

    func fetchLineConfig(lineId: Int, nodeId: Int) async throws -> LineConfig {
        try await request("/api/v1/lines/\(lineId)/config",
                          query: ["nodeId": String(nodeId)], as: LineConfig.self)
    }

    // 用户中心
    func fetchUserCenter() async throws -> UserCenterPayload {
        try await request("/api/v1/user", as: UserCenterPayload.self)
    }

    func fetchTraffic(days: Int = 15) async throws -> TrafficPayload {
        try await request("/api/v1/user/traffic", query: ["days": String(days)], as: TrafficPayload.self)
    }

    func changePassword(old: String, new: String) async throws {
        try await requestVoid("/api/v1/user/password", method: "POST",
                              body: ["oldPassword": old, "newPassword": new])
    }

    func fetchSecurityQuestion() async throws -> String? {
        let result = try await request("/api/v1/user/security", as: SimpleResult.self)
        return result.question
    }

    func updateSecurity(question: String, answer: String) async throws {
        try await requestVoid("/api/v1/user/security", method: "POST",
                              body: ["question": question, "answer": answer])
    }

    // 套餐与订单
    func fetchPlans() async throws -> PlansPayload {
        try await request("/api/v1/plans", as: PlansPayload.self)
    }

    func fetchOrders(page: Int = 1) async throws -> OrdersPayload {
        try await request("/api/v1/orders", query: ["page": String(page)], as: OrdersPayload.self)
    }

    func createOrder(planId: Int, method: String) async throws -> CreateOrderPayload {
        try await request("/api/v1/orders", method: "POST",
                          body: ["plan_id": planId, "method": method], as: CreateOrderPayload.self)
    }

    // 公告
    func fetchAnnouncements() async throws -> AnnouncementsPayload {
        try await request("/api/v1/announcements", as: AnnouncementsPayload.self)
    }

    func markAnnouncementsRead(ids: [Int]) async throws {
        try await requestVoid("/api/v1/announcements", method: "POST", body: ["ids": ids])
    }

    // 激活码
    func fetchActivationRecords() async throws -> [ActivationRecord] {
        let payload = try await request("/api/v1/activation", as: ActivationRecordsPayload.self)
        return payload.records
    }

    func previewActivation(code: String) async throws -> ActivationPreview {
        try await request("/api/v1/activation", query: ["code": code], as: ActivationPreview.self)
    }

    func redeemActivation(code: String) async throws -> ActivationRedeemResult {
        try await request("/api/v1/activation", method: "POST", body: ["code": code],
                          as: ActivationRedeemResult.self)
    }

    // 金币
    func fetchCoins() async throws -> CoinsPayload {
        try await request("/api/v1/coins", as: CoinsPayload.self)
    }

    // 反馈
    func fetchFeedback() async throws -> [FeedbackItem] {
        let payload = try await request("/api/v1/feedback", as: FeedbackListPayload.self)
        return payload.feedback
    }

    func submitFeedback(lineId: Int?, title: String, content: String, contact: String) async throws {
        var body: [String: Any] = ["title": title, "content": content, "contact": contact]
        if let lineId { body["lineId"] = lineId }
        try await requestVoid("/api/v1/feedback", method: "POST", body: body)
    }
}