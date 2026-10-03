import Foundation

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

// MARK: - 主控接口

/// 各接口方法在调用点用具体类型解析 data 段：
/// Kotlin 泛型运行时擦除，泛型函数内无法 `decode(T.self)`，故统一写成
/// `request(..., decode: { data in try APIClient.apiDecoder().decode(X.self, from: data) })`。
extension APIClient {

    // 认证
    func login(username: String, password: String) async throws -> AuthResult {
        try await request("/api/v1/auth/login", method: "POST",
                          body: ["username": username, "password": password],
                          decode: { data in try APIClient.apiDecoder().decode(AuthResult.self, from: data) })
    }

    func register(username: String, password: String, email: String,
                  captchaToken: String, captchaInput: String) async throws -> AuthResult {
        var body: [String: Any] = ["username": username, "password": password, "email": email]
        if !captchaToken.isEmpty { body["captchaToken"] = captchaToken }
        if !captchaInput.isEmpty { body["captchaInput"] = captchaInput }
        return try await request("/api/v1/auth/register", method: "POST", body: body,
                                 decode: { data in try APIClient.apiDecoder().decode(AuthResult.self, from: data) })
    }

    /// 注册验证码（GET /api/auth/captcha，与 Web 端同一接口）
    func fetchCaptcha() async throws -> CaptchaPayload {
        try await request("/api/auth/captcha",
                          decode: { data in try APIClient.apiDecoder().decode(CaptchaPayload.self, from: data) })
    }

    func forgotQuestion(account: String) async throws -> String {
        let result = try await request("/api/v1/auth/forgot", method: "POST",
                                       body: ["account": account],
                                       decode: { data in try APIClient.apiDecoder().decode(SimpleResult.self, from: data) })
        return result.question ?? ""
    }

    func resetPassword(account: String, answer: String, newPassword: String) async throws {
        try await requestVoid("/api/v1/auth/reset-password", method: "POST",
                              body: ["account": account, "answer": answer, "newPassword": newPassword])
    }

    // 服务器与线路
    func fetchLines() async throws -> LinesPayload {
        try await request("/api/v1/lines",
                          decode: { data in try APIClient.apiDecoder().decode(LinesPayload.self, from: data) })
    }

    func fetchLineConfig(lineId: Int, nodeId: Int, family: String = "v4") async throws -> LineConfig {
        try await request("/api/v1/lines/\(lineId)/config",
                          query: ["nodeId": String(nodeId), "family": family],
                          decode: { data in try APIClient.apiDecoder().decode(LineConfig.self, from: data) })
    }

    /// 账号异常状态与通知（套餐到期、流量耗尽、被管理员断开等）
    func fetchUserStatus() async throws -> UserStatusPayload {
        try await request("/api/v1/user/status",
                          decode: { data in try APIClient.apiDecoder().decode(UserStatusPayload.self, from: data) })
    }

    /// 用户主动断开：关闭主控侧在线会话并通知节点释放 peer
    func closeSessions() async throws {
        try await requestVoid("/api/v1/user/sessions", method: "POST", body: ["action": "disconnect"])
    }

    // 用户中心
    func fetchUserCenter() async throws -> UserCenterPayload {
        try await request("/api/v1/user",
                          decode: { data in try APIClient.apiDecoder().decode(UserCenterPayload.self, from: data) })
    }

    func fetchTraffic(days: Int = 15) async throws -> TrafficPayload {
        try await request("/api/v1/user/traffic", query: ["days": String(days)],
                          decode: { data in try APIClient.apiDecoder().decode(TrafficPayload.self, from: data) })
    }

    func changePassword(old: String, new: String) async throws {
        try await requestVoid("/api/v1/user/password", method: "POST",
                              body: ["oldPassword": old, "newPassword": new])
    }

    func fetchSecurityQuestion() async throws -> String? {
        let result = try await request("/api/v1/user/security",
                                       decode: { data in try APIClient.apiDecoder().decode(SimpleResult.self, from: data) })
        return result.question
    }

    func updateSecurity(question: String, answer: String) async throws {
        try await requestVoid("/api/v1/user/security", method: "POST",
                              body: ["question": question, "answer": answer])
    }

    // 套餐与订单
    func fetchPlans() async throws -> PlansPayload {
        try await request("/api/v1/plans",
                          decode: { data in try APIClient.apiDecoder().decode(PlansPayload.self, from: data) })
    }

    func fetchOrders(page: Int = 1) async throws -> OrdersPayload {
        try await request("/api/v1/orders", query: ["page": String(page)],
                          decode: { data in try APIClient.apiDecoder().decode(OrdersPayload.self, from: data) })
    }

    func createOrder(planId: Int, method: String,
                     useCoins: Bool = false, payWithBalance: Bool = false,
                     channelId: Int? = nil) async throws -> CreateOrderPayload {
        var body: [String: Any] = ["plan_id": planId, "method": method]
        if useCoins { body["use_coins"] = true }
        if payWithBalance { body["pay_with_balance"] = true }
        if let channelId { body["channel_id"] = channelId }
        return try await request("/api/v1/orders", method: "POST", body: body,
                                 decode: { data in try APIClient.apiDecoder().decode(CreateOrderPayload.self, from: data) })
    }

    /// 余额充值：创建充值订单并返回支付跳转地址（在内置浏览器打开）
    func rechargeBalance(amountYuan: Double, method: String, channelId: Int?) async throws -> CreateOrderPayload {
        var body: [String: Any] = ["amount_yuan": amountYuan, "method": method]
        if let channelId { body["channel_id"] = channelId }
        return try await request("/api/v1/orders/recharge", method: "POST", body: body,
                                 decode: { data in try APIClient.apiDecoder().decode(CreateOrderPayload.self, from: data) })
    }

    /// 继续支付（复用原订单，不再新建订单）
    func payOrder(id: Int) async throws -> CreateOrderPayload {
        try await request("/api/v1/orders/\(id)/pay", method: "POST",
                          decode: { data in try APIClient.apiDecoder().decode(CreateOrderPayload.self, from: data) })
    }

    /// 取消未支付订单
    func cancelOrder(id: Int) async throws {
        try await requestVoid("/api/v1/orders/\(id)/cancel", method: "POST")
    }

    // 公告
    func fetchAnnouncements() async throws -> AnnouncementsPayload {
        try await request("/api/v1/announcements",
                          decode: { data in try APIClient.apiDecoder().decode(AnnouncementsPayload.self, from: data) })
    }

    func markAnnouncementsRead(ids: [Int]) async throws {
        try await requestVoid("/api/v1/announcements", method: "POST", body: ["ids": ids])
    }

    // 激活码
    func fetchActivationRecords() async throws -> [ActivationRecord] {
        let payload = try await request("/api/v1/activation",
                                        decode: { data in try APIClient.apiDecoder().decode(ActivationRecordsPayload.self, from: data) })
        return payload.records
    }

    func previewActivation(code: String) async throws -> ActivationPreview {
        try await request("/api/v1/activation", query: ["code": code],
                          decode: { data in try APIClient.apiDecoder().decode(ActivationPreview.self, from: data) })
    }

    func redeemActivation(code: String) async throws -> ActivationRedeemResult {
        try await request("/api/v1/activation", method: "POST", body: ["code": code],
                          decode: { data in try APIClient.apiDecoder().decode(ActivationRedeemResult.self, from: data) })
    }

    // 金币
    func fetchCoins() async throws -> CoinsPayload {
        try await request("/api/v1/coins",
                          decode: { data in try APIClient.apiDecoder().decode(CoinsPayload.self, from: data) })
    }

    // 反馈
    func fetchFeedback() async throws -> [FeedbackItem] {
        let payload = try await request("/api/v1/feedback",
                                        decode: { data in try APIClient.apiDecoder().decode(FeedbackListPayload.self, from: data) })
        return payload.feedback
    }

    func submitFeedback(lineId: Int?, title: String, content: String, contact: String) async throws {
        var body: [String: Any] = ["title": title, "content": content, "contact": contact]
        if let lineId { body["lineId"] = lineId }
        try await requestVoid("/api/v1/feedback", method: "POST", body: body)
    }
}