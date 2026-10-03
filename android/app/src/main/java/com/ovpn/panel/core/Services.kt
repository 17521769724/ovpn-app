package com.ovpn.panel.core

import android.content.Context
import android.content.SharedPreferences

// MARK: - 本地存储（对应 iOS LocalStore / SecureStore）
//
// 说明：iOS 原版 token / VPN 密码存放在 Keychain（SecureStore）。Android 端按要求
// 统一使用 SharedPreferences（不引入 EncryptedSharedPreferences，避免额外依赖）。

/** 共享首选项文件名 */
private const val PREFS_NAME = "ovpn.panel"

/**
 * 取共享首选项。上下文由 [AppState.init] 一次性注入。
 * 注意：必须在 `AppState.init(context)` 之后调用，否则会抛 UninitializedPropertyAccessException。
 */
private fun prefs(): SharedPreferences =
    AppState.appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

/** 本地存储：主控地址与上次登录账号（对应 iOS LocalStore） */
object LocalStore {
    private const val masterKey = "ovpn.master.url"
    private const val accountKey = "ovpn.last.account"

    var masterURL: String?
        get() = prefs().getString(masterKey, null)
        set(value) {
            prefs().edit().apply {
                if (value == null) remove(masterKey) else putString(masterKey, value)
            }.apply()
        }

    var lastAccount: String?
        get() = prefs().getString(accountKey, null)
        set(value) {
            prefs().edit().apply {
                if (value == null) remove(accountKey) else putString(accountKey, value)
            }.apply()
        }
}

/**
 * 令牌与凭据存储（Android 使用 SharedPreferences 承载，语义对应 iOS Keychain SecureStore）。
 */
object SecureStore {
    /** 登录令牌 */
    const val tokenAccount = "app.token"

    /** 连接 VPN 用的账号密码（登录成功后保存，连接时自动使用） */
    const val passwordAccount = "vpn.password"

    fun save(value: String, account: String = tokenAccount) {
        prefs().edit().putString(account, value).apply()
    }

    fun load(account: String = tokenAccount): String? =
        prefs().getString(account, null)

    fun clear(account: String = tokenAccount) {
        prefs().edit().remove(account).apply()
    }
}

// MARK: - 主控接口（对应 iOS APIClient extension）

/**
 * 主控 API 封装。与 iOS `APIClient` 扩展一一对应：
 * 路径 / HTTP 方法 / query / body JSON 键完全保持一致。
 * 请求体中的键沿用 Swift 端发送的原始键名（部分为 snake_case，部分为 camelCase）。
 */
object ApiService {

    // 认证

    suspend fun login(username: String, password: String): AuthResult =
        ApiClient.request(
            "/api/v1/auth/login",
            method = "POST",
            body = bodyOf("username" to username, "password" to password),
            deserializer = AuthResult.serializer(),
        )

    suspend fun register(
        username: String,
        password: String,
        email: String,
        captchaToken: String,
        captchaInput: String,
    ): AuthResult {
        val body = mutableMapOf<String, Any?>(
            "username" to username,
            "password" to password,
            "email" to email,
        )
        if (captchaToken.isNotEmpty()) body["captchaToken"] = captchaToken
        if (captchaInput.isNotEmpty()) body["captchaInput"] = captchaInput
        return ApiClient.request(
            "/api/v1/auth/register",
            method = "POST",
            body = body,
            deserializer = AuthResult.serializer(),
        )
    }

    /** 注册验证码（GET /api/auth/captcha，与 Web 端同一接口） */
    suspend fun fetchCaptcha(): CaptchaPayload =
        ApiClient.request("/api/auth/captcha", deserializer = CaptchaPayload.serializer())

    suspend fun forgotQuestion(account: String): String {
        val result = ApiClient.request(
            "/api/v1/auth/forgot",
            method = "POST",
            body = bodyOf("account" to account),
            deserializer = SimpleResult.serializer(),
        )
        return result.question ?: ""
    }

    suspend fun resetPassword(account: String, answer: String, newPassword: String) {
        ApiClient.requestVoid(
            "/api/v1/auth/reset-password",
            method = "POST",
            body = bodyOf("account" to account, "answer" to answer, "newPassword" to newPassword),
        )
    }

    // 服务器与线路

    suspend fun fetchLines(): LinesPayload =
        ApiClient.request("/api/v1/lines", deserializer = LinesPayload.serializer())

    suspend fun fetchLineConfig(lineId: Int, nodeId: Int, family: String = "v4"): LineConfig =
        ApiClient.request(
            "/api/v1/lines/$lineId/config",
            query = mapOf("nodeId" to nodeId.toString(), "family" to family),
            deserializer = LineConfig.serializer(),
        )

    /** 账号异常状态与通知（套餐到期、流量耗尽、被管理员断开等） */
    suspend fun fetchUserStatus(): UserStatusPayload =
        ApiClient.request("/api/v1/user/status", deserializer = UserStatusPayload.serializer())

    /** 用户主动断开：关闭主控侧在线会话并通知节点释放 peer */
    suspend fun closeSessions() {
        ApiClient.requestVoid(
            "/api/v1/user/sessions",
            method = "POST",
            body = bodyOf("action" to "disconnect"),
        )
    }

    // 用户中心

    suspend fun fetchUserCenter(): UserCenterPayload =
        ApiClient.request("/api/v1/user", deserializer = UserCenterPayload.serializer())

    suspend fun fetchTraffic(days: Int = 15): TrafficPayload =
        ApiClient.request(
            "/api/v1/user/traffic",
            query = mapOf("days" to days.toString()),
            deserializer = TrafficPayload.serializer(),
        )

    suspend fun changePassword(old: String, new: String) {
        ApiClient.requestVoid(
            "/api/v1/user/password",
            method = "POST",
            body = bodyOf("oldPassword" to old, "newPassword" to new),
        )
    }

    suspend fun fetchSecurityQuestion(): String? =
        ApiClient.request("/api/v1/user/security", deserializer = SimpleResult.serializer()).question

    suspend fun updateSecurity(question: String, answer: String) {
        ApiClient.requestVoid(
            "/api/v1/user/security",
            method = "POST",
            body = bodyOf("question" to question, "answer" to answer),
        )
    }

    // 套餐与订单

    suspend fun fetchPlans(): PlansPayload =
        ApiClient.request("/api/v1/plans", deserializer = PlansPayload.serializer())

    suspend fun fetchOrders(page: Int = 1): OrdersPayload =
        ApiClient.request(
            "/api/v1/orders",
            query = mapOf("page" to page.toString()),
            deserializer = OrdersPayload.serializer(),
        )

    suspend fun createOrder(
        planId: Int,
        method: String,
        useCoins: Boolean = false,
        payWithBalance: Boolean = false,
        channelId: Int? = null,
    ): CreateOrderPayload {
        val body = mutableMapOf<String, Any?>("plan_id" to planId, "method" to method)
        if (useCoins) body["use_coins"] = true
        if (payWithBalance) body["pay_with_balance"] = true
        if (channelId != null) body["channel_id"] = channelId
        return ApiClient.request(
            "/api/v1/orders",
            method = "POST",
            body = body,
            deserializer = CreateOrderPayload.serializer(),
        )
    }

    /** 余额充值：创建充值订单并返回支付跳转地址（在内置浏览器打开） */
    suspend fun rechargeBalance(amountYuan: Double, method: String, channelId: Int?): CreateOrderPayload {
        val body = mutableMapOf<String, Any?>("amount_yuan" to amountYuan, "method" to method)
        if (channelId != null) body["channel_id"] = channelId
        return ApiClient.request(
            "/api/v1/orders/recharge",
            method = "POST",
            body = body,
            deserializer = CreateOrderPayload.serializer(),
        )
    }

    /** 继续支付（复用原订单，不再新建订单） */
    suspend fun payOrder(id: Int): CreateOrderPayload =
        ApiClient.request(
            "/api/v1/orders/$id/pay",
            method = "POST",
            deserializer = CreateOrderPayload.serializer(),
        )

    /** 取消未支付订单 */
    suspend fun cancelOrder(id: Int) {
        ApiClient.requestVoid("/api/v1/orders/$id/cancel", method = "POST")
    }

    // 公告

    suspend fun fetchAnnouncements(): AnnouncementsPayload =
        ApiClient.request("/api/v1/announcements", deserializer = AnnouncementsPayload.serializer())

    suspend fun markAnnouncementsRead(ids: List<Int>) {
        ApiClient.requestVoid(
            "/api/v1/announcements",
            method = "POST",
            body = bodyOf("ids" to ids),
        )
    }

    // 激活码

    suspend fun fetchActivationRecords(): List<ActivationRecord> =
        ApiClient.request("/api/v1/activation", deserializer = ActivationRecordsPayload.serializer()).records

    suspend fun previewActivation(code: String): ActivationPreview =
        ApiClient.request(
            "/api/v1/activation",
            query = mapOf("code" to code),
            deserializer = ActivationPreview.serializer(),
        )

    suspend fun redeemActivation(code: String): ActivationRedeemResult =
        ApiClient.request(
            "/api/v1/activation",
            method = "POST",
            body = bodyOf("code" to code),
            deserializer = ActivationRedeemResult.serializer(),
        )

    // 金币

    suspend fun fetchCoins(): CoinsPayload =
        ApiClient.request("/api/v1/coins", deserializer = CoinsPayload.serializer())

    // 反馈

    suspend fun fetchFeedback(): List<FeedbackItem> =
        ApiClient.request("/api/v1/feedback", deserializer = FeedbackListPayload.serializer()).feedback

    suspend fun submitFeedback(lineId: Int?, title: String, content: String, contact: String) {
        val body = mutableMapOf<String, Any?>(
            "title" to title,
            "content" to content,
            "contact" to contact,
        )
        if (lineId != null) body["lineId"] = lineId
        ApiClient.requestVoid("/api/v1/feedback", method = "POST", body = body)
    }
}