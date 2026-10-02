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

extension APIClient {

    // 认证
    func login(username: String, password: String) async throws -> AuthResult {
        try await request("/api/v1/auth/login", method: "POST",
                          body: ["username": username, "password": password], as: AuthResult.self)
    }

    func register(username: String, password: String, email: String,
                  captchaToken: String, captchaInput: String) async throws -> AuthResult {
        var body: [String: Any] = ["username": username, "password": password, "email": email]
        if !captchaToken.isEmpty { body["captchaToken"] = captchaToken }
        if !captchaInput.isEmpty { body["captchaInput"] = captchaInput }
        return try await request("/api/v1/auth/register", method: "POST", body: body, as: AuthResult.self)
    }

    /// 注册验证码（GET /api/auth/captcha，与 Web 端同一接口）
    func fetchCaptcha() async throws -> CaptchaPayload {
        try await request("/api/auth/captcha", as: CaptchaPayload.self)
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

    func fetchLineConfig(lineId: Int, nodeId: Int, family: String = "v4") async throws -> LineConfig {
        try await request("/api/v1/lines/\(lineId)/config",
                          query: ["nodeId": String(nodeId), "family": family], as: LineConfig.self)
    }

    /// 账号异常状态与通知（套餐到期、流量耗尽、被管理员断开等）
    func fetchUserStatus() async throws -> UserStatusPayload {
        try await request("/api/v1/user/status", as: UserStatusPayload.self)
    }

    /// 用户主动断开：关闭主控侧在线会话并通知节点释放 peer
    func closeSessions() async throws {
        try await requestVoid("/api/v1/user/sessions", method: "POST", body: ["action": "disconnect"])
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

    func createOrder(planId: Int, method: String,
                     useCoins: Bool = false, payWithBalance: Bool = false,
                     channelId: Int? = nil) async throws -> CreateOrderPayload {
        var body: [String: Any] = ["plan_id": planId, "method": method]
        if useCoins { body["use_coins"] = true }
        if payWithBalance { body["pay_with_balance"] = true }
        if let channelId { body["channel_id"] = channelId }
        return try await request("/api/v1/orders", method: "POST", body: body, as: CreateOrderPayload.self)
    }

    /// 余额充值：创建充值订单并返回支付跳转地址（在内置浏览器打开）
    func rechargeBalance(amountYuan: Double, method: String, channelId: Int?) async throws -> CreateOrderPayload {
        var body: [String: Any] = ["amount_yuan": amountYuan, "method": method]
        if let channelId { body["channel_id"] = channelId }
        return try await request("/api/v1/orders/recharge", method: "POST", body: body, as: CreateOrderPayload.self)
    }

    /// 继续支付（复用原订单，不再新建订单）
    func payOrder(id: Int) async throws -> CreateOrderPayload {
        try await request("/api/v1/orders/\(id)/pay", method: "POST", as: CreateOrderPayload.self)
    }

    /// 取消未支付订单
    func cancelOrder(id: Int) async throws {
        try await requestVoid("/api/v1/orders/\(id)/cancel", method: "POST")
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