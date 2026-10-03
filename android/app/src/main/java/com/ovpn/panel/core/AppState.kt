package com.ovpn.panel.core

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import kotlinx.serialization.json.jsonObject

/**
 * 全局横幅消息（对应 iOS `ToastMessage`）。
 *
 * 注意：该类型由 AppState 产出、UI 消费；UI 层请直接复用此类型，不要重复定义。
 */
data class ToastMessage(
    val id: Long,
    val text: String,
    val kind: BannerKind,
)

/**
 * 全局应用状态：主控地址、登录态、用户信息、全局横幅提示。
 * 对应 iOS `@MainActor final class AppState: ObservableObject`，此处移植为单例 object，
 * 可观测值使用 [MutableStateFlow]（Compose 友好）。
 *
 * 使用前需调用一次 [init]（注入 Application Context 并恢复本地状态）。
 */
object AppState {

    /** 应用阶段 */
    enum class Phase {
        /** 未配置主控地址 */
        Setup,

        /** 已配置主控，等待登录 */
        Auth,

        /** 已登录 */
        Main,
    }

    /** 调用方一次性注入的上下文（Application Context） */
    lateinit var appContext: Context
        private set

    private var initialized = false

    val phase = MutableStateFlow(Phase.Setup)
    val masterUrl = MutableStateFlow("")
    val user = MutableStateFlow<AppUser?>(null)
    val toast = MutableStateFlow<ToastMessage?>(null)
    val busy = MutableStateFlow(false)

    /** 是否已登录（等价于 phase == Main，单独暴露便于 UI 观察） */
    val isLoggedIn = MutableStateFlow(false)

    /** 最近一次上报的错误（取消类错误也会记录，但不弹横幅） */
    val lastError = MutableStateFlow<APIError?>(null)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val toastToken = AtomicLong(0L)
    private var statusTask: Job? = null
    private var lastNoticeKey: String? = null

    /**
     * 初始化：注入 Context（只生效一次），随后恢复本地状态。
     * 对应 iOS `init()` 中的 `restore()`。
     */
    fun init(context: Context) {
        if (initialized) return
        appContext = context.applicationContext
        initialized = true
        restore()
        // 注：iOS 的 `applyLaunchOverrides()`（CI 启动参数 -masterURL / -autoLogin）
        // 依赖 ProcessInfo，Android 无对应机制，故不移植。
    }

    private fun restore() {
        val saved = LocalStore.masterURL
        if (!saved.isNullOrEmpty()) {
            masterUrl.value = saved
            ApiClient.setBaseUrl(saved)
            val token = SecureStore.load()
            if (!token.isNullOrEmpty()) {
                ApiClient.setToken(token)
                isLoggedIn.value = true
                phase.value = Phase.Main
                scope.launch { refreshUser() }
                startStatusPolling()
            } else {
                phase.value = Phase.Auth
            }
        } else {
            phase.value = Phase.Setup
        }
    }

    /** 校验并保存主控地址（可达即视为合法主控） */
    suspend fun configureMaster(url: String) {
        val normalized = normalize(url)
        val probeUrl = (normalized + "/api/v1/lines").toHttpUrlOrNull()
            ?: throw APIError("主控地址无效")

        val request = Request.Builder()
            .url(probeUrl)
            .header("Accept", "application/json")
            .build()
        val client = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .build()

        val status: Int
        val bodyText: String
        try {
            val result = withContext(Dispatchers.IO) {
                client.newCall(request).execute().use { response ->
                    response.code to response.body?.string().orEmpty()
                }
            }
            status = result.first
            bodyText = result.second
        } catch (e: CancellationException) {
            throw APIError("已取消", cancelled = true)
        } catch (e: IOException) {
            throw APIError("无法连接该地址：${e.message ?: "网络异常"}")
        }

        // 主控对未登录请求会返回 401 + 统一包裹；只要能解析出 code 字段即认定为主控
        val decoded = try {
            ApiClient.json.parseToJsonElement(bodyText).jsonObject
        } catch (e: Exception) {
            null
        }
        val isMaster = decoded?.get("code") != null
        if (!isMaster && status !in 200..299) {
            throw APIError("该地址不是有效的主控（HTTP $status）")
        }

        masterUrl.value = normalized
        LocalStore.masterURL = normalized
        ApiClient.setBaseUrl(normalized)
        phase.value = Phase.Auth
    }

    private fun normalize(url: String): String {
        var value = url.trim()
        val lower = value.lowercase()
        if (!lower.startsWith("http://") && !lower.startsWith("https://")) {
            value = "http://$value"
        }
        while (value.endsWith("/")) value = value.dropLast(1)
        return value
    }

    suspend fun login(account: String, password: String) {
        val result = ApiService.login(account, password)
        applyAuth(result)
        LocalStore.lastAccount = account
        // 保存连接 VPN 用的登录密码（OpenVPN 采用账号密码认证）
        SecureStore.save(password, SecureStore.passwordAccount)
    }

    suspend fun register(
        username: String,
        password: String,
        email: String,
        captchaToken: String,
        captchaInput: String,
    ) {
        val result = ApiService.register(username, password, email, captchaToken, captchaInput)
        applyAuth(result)
        LocalStore.lastAccount = username
        SecureStore.save(password, SecureStore.passwordAccount)
    }

    private fun applyAuth(result: AuthResult) {
        ApiClient.setToken(result.token)
        SecureStore.save(result.token)
        user.value = result.user
        isLoggedIn.value = true
        phase.value = Phase.Main
        startStatusPolling()
    }

    suspend fun refreshUser() {
        try {
            val center = ApiService.fetchUserCenter()
            user.value = center.user
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val message = (e as? APIError)?.message ?: ""
            if (message.contains("未登录")) {
                logout()
            }
        }
    }

    fun logout() {
        stopStatusPolling()
        ApiClient.setToken(null)
        SecureStore.clear()
        user.value = null
        isLoggedIn.value = false
        phase.value = Phase.Auth
        dismissToast()
    }

    // MARK: - 账号异常状态轮询（被管理员断开 / 套餐到期 / 流量耗尽 / 封禁）

    fun startStatusPolling() {
        statusTask?.cancel()
        lastNoticeKey = null
        statusTask = scope.launch {
            while (isActive) {
                pollStatus()
                // 轮询间隔 8s：被管理员断开等异常能较快以横幅提示
                delay(8_000L)
            }
        }
    }

    fun stopStatusPolling() {
        statusTask?.cancel()
        statusTask = null
    }

    /** 立即检查一次（连接失败、下单后等需要即时反馈的场景） */
    suspend fun checkStatusNow() {
        pollStatus()
    }

    private suspend fun pollStatus() {
        if (phase.value != Phase.Main) return
        val payload = try {
            ApiService.fetchUserStatus()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return
        }

        val notice = payload.notice
        if (notice == null) {
            // 状态恢复正常，允许下次同样的问题重新提示
            lastNoticeKey = null
            return
        }
        if (notice.key == lastNoticeKey) return
        lastNoticeKey = notice.key

        val kind = if (notice.code == "blocked" || notice.code == "banned" ||
            notice.code == "expired" || notice.code == "over_quota"
        ) BannerKind.Error else BannerKind.Warning
        showToast(notice.message, kind)

        // 被管理员断开 / 封禁：iOS 原版会本地同步断开隧道（VPNManager.disconnect()）。
        // 本次移植不涉及 VPN 类型，相关断开交由后续 VPN 层处理，此处省略。
        if (payload.quota?.valid != true) refreshUser()
    }

    /** 切换主控（回到配置页） */
    fun resetMaster() {
        logout()
        LocalStore.masterURL = null
        masterUrl.value = ""
        phase.value = Phase.Setup
        isLoggedIn.value = false
    }

    // MARK: - 全局横幅提示（与 Web 端 toast 一致）

    /** 非隔离入口：任何上下文都能直接调用（内部通过 StateFlow 通知 UI） */
    fun showToast(message: String, kind: BannerKind = BannerKind.Info) {
        val value = message.trim()
        if (value.isEmpty()) return
        val token = toastToken.incrementAndGet()
        toast.value = ToastMessage(token, value, kind)
        val duration: Long = if (kind == BannerKind.Error) 3_600L else 2_600L
        scope.launch {
            delay(duration)
            if (toastToken.get() == token) dismissToast()
        }
    }

    /** 统一错误上报：取消类错误静默忽略，其余以红色横幅提示 */
    fun report(error: Throwable) {
        val apiError = asApiError(error)
        lastError.value = apiError
        if (apiError.cancelled) return
        showToast(apiError.message ?: "操作失败", BannerKind.Error)
    }

    fun dismissToast() {
        toastToken.incrementAndGet()
        toast.value = null
    }

    /** 取消类错误检测助手（对应 iOS `APIError.isCancelled`） */
    fun isCancelled(error: Throwable): Boolean = asApiError(error).cancelled

    private fun asApiError(error: Throwable): APIError = when (error) {
        is APIError -> error
        is CancellationException -> APIError("已取消", cancelled = true)
        else -> APIError(error.message ?: "操作失败")
    }
}