package com.ovpn.panel

import android.content.Intent
import android.net.VpnService
import com.tim.basevpn.state.ConnectionState
import com.tim.openvpn.OpenVPNConfigParser
import com.tim.openvpn.connection.OpenVPNConnection
import java.util.Date

/**
 * Swift（Skip 转译层）与 OpenVPN 3 内核之间的桥。
 *
 * 对应关系：iOS `VPNManager`（NetworkExtension + TunnelKit）
 * ↔ Android `VpnBridge`（VpnService + OpenVPN 3 / tim06 openvpn 库）。
 *
 * Swift 侧的调用形式：
 * ```swift
 * #if SKIP
 * VpnBridge.shared.observe { status in ... }
 * try VpnBridge.shared.connect(ovpn:user:password:title:)
 * VpnBridge.shared.disconnect()
 * #endif
 * ```
 * Kotlin `object` 在 Skip 中映射为 Swift 的 `Xxx.shared`，参数名即 Swift 实参标签。
 */
object VpnBridge {

    /** 与 Swift 侧 `VpnStatus` 的字符串约定：connected / connecting / disconnecting / reasserting / invalid / disconnected */
    private const val S_DISCONNECTED = "disconnected"
    private const val S_CONNECTING = "connecting"
    private const val S_CONNECTED = "connected"
    private const val S_DISCONNECTING = "disconnecting"
    private const val S_REASSERTING = "reasserting"
    private const val S_INVALID = "invalid"

    private var connection: OpenVPNConnection? = null
    private val listeners = mutableListOf<(String) -> Unit>()

    @Volatile
    private var statusValue: String = S_DISCONNECTED

    @Volatile
    private var connectedAtValue: Date? = null

    @Volatile
    private var activeTitleValue: String = ""

    /** 当前状态（Swift 侧 `syncStatus()` 读取） */
    val currentStatus: String get() = statusValue

    /** 连接建立时间（Swift 侧用于计算已连接时长并持久化） */
    val connectedAt: Date? get() = connectedAtValue

    /** 当前连接的「服务器 ｜ 线路」标题，用于页面重建后恢复展示 */
    val activeTitle: String get() = activeTitleValue

    private val stateListener: (ConnectionState) -> Unit = { state ->
        val mapped = when (state) {
            ConnectionState.CONNECTED -> S_CONNECTED
            ConnectionState.CONNECTING, ConnectionState.READYFORCONNECT -> S_CONNECTING
            ConnectionState.DISCONNECTING -> S_DISCONNECTING
            ConnectionState.DISCONNECTED, ConnectionState.IDLE -> S_DISCONNECTED
            ConnectionState.PERMISSION_NOT_GRANTED -> S_INVALID
            else -> statusValue
        }
        // 与 iOS 一致：连接成功时记录建立时间；断开时清空
        if (mapped == S_CONNECTED && connectedAtValue == null) {
            connectedAtValue = Date()
        }
        if (mapped == S_DISCONNECTED || mapped == S_INVALID) {
            connectedAtValue = null
        }
        statusValue = mapped
        listeners.toList().forEach { it(mapped) }
    }

    /** 订阅状态变更（对应 iOS 的 `.NEVPNStatusDidChange` 通知） */
    fun observe(callback: (String) -> Unit) {
        listeners += callback
    }

    /** 冷启动 / 回到前台时同步系统 VpnService 的真实运行状态 */
    fun refreshStatus() {
        statusValue = S_DISCONNECTED
        connectedAtValue = null
        notifyCurrent()
    }

    /**
     * 建立隧道。
     * 与 iOS 相同：首次连接会触发系统授权，授权后再调用一次即可。
     */
    @Throws(Exception::class)
    fun connect(ovpn: String, username: String, password: String, title: String) {
        val context = AppEnv.appContext
        if (ovpn.isBlank()) throw IllegalStateException("线路配置为空，请重新下载")

        // 未授权时先请求系统 VPN 授权（等价于 iOS 的系统授权弹窗）
        val consent = VpnService.prepare(context)
        if (consent != null) {
            runCatching {
                consent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(consent)
            }
            statusValue = S_DISCONNECTED
            notifyCurrent()
            throw IllegalStateException("需要授权 VPN 连接，请在弹出的系统窗口中允许后重试")
        }

        activeTitleValue = title
        statusValue = S_CONNECTING
        notifyCurrent()

        // 追加 auth-user-pass：OpenVPN 3 支持内联凭据块
        val withCreds = buildString {
            append(ovpn.trimEnd())
            append("\n<auth-user-pass>\n")
            append(username).append('\n')
            append(password).append('\n')
            append("</auth-user-pass>\n")
        }

        val config = try {
            OpenVPNConfigParser.parse(withCreds)
        } catch (e: Exception) {
            statusValue = S_DISCONNECTED
            notifyCurrent()
            throw IllegalStateException("线路配置解析失败：${e.message ?: "格式不支持"}")
        }

        connection = OpenVPNConnection(context, stateListener)
        connection?.start(config)
    }

    /** 断开隧道（对应 iOS `VPNManager.disconnect()`） */
    fun disconnect() {
        statusValue = S_DISCONNECTING
        notifyCurrent()
        connection?.stop()
        connection = null
        statusValue = S_DISCONNECTED
        connectedAtValue = null
        activeTitleValue = ""
        notifyCurrent()
    }

    private fun notifyCurrent() {
        listeners.toList().forEach { it(statusValue) }
    }
}
