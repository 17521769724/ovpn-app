package com.ovpn.panel.core

import android.content.Context
import android.content.Intent
import android.net.VpnService
import com.tim.basevpn.state.ConnectionState
import com.tim.openvpn.OpenVPNConfigParser
import com.tim.openvpn.configuration.OpenVPNConfig
import com.tim.openvpn.connection.OpenVPNConnection
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** 隧道连接状态（对应 iOS NEVPNStatus 的语义子集） */
enum class VpnStatus { Disconnected, Connecting, Connected, Disconnecting, Reasserting }

/** 与 iOS `VPNManager.statusText` 完全一致的文案 */
fun vpnStatusText(status: VpnStatus): String = when (status) {
    VpnStatus.Connected -> "已连接"
    VpnStatus.Connecting -> "连接中…"
    VpnStatus.Disconnecting -> "断开中…"
    VpnStatus.Reasserting -> "重新连接中…"
    VpnStatus.Disconnected -> "未连接"
}

/**
 * OpenVPN 隧道管理（对应 iOS VPNManager，底层使用 OpenVPN 3 内核 / tim06 openvpn 库）。
 * 连接成功后由系统 VpnService 接管流量；这里只负责下发配置、订阅状态与暴露状态给 UI。
 */
object VpnManager {

    private val _status = MutableStateFlow(VpnStatus.Disconnected)
    val status: StateFlow<VpnStatus> = _status

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError

    private val _connectedAt = MutableStateFlow<Long?>(null)
    val connectedAt: StateFlow<Long?> = _connectedAt

    private val _activeServerName = MutableStateFlow("")
    val activeServerName: StateFlow<String> = _activeServerName

    private val _activeLineName = MutableStateFlow("")
    val activeLineName: StateFlow<String> = _activeLineName

    private val _activeNodeId = MutableStateFlow(0)
    val activeNodeId: StateFlow<Int> = _activeNodeId

    val isConnected: Boolean get() = _status.value == VpnStatus.Connected

    val isBusy: Boolean
        get() = _status.value == VpnStatus.Connecting ||
            _status.value == VpnStatus.Reasserting ||
            _status.value == VpnStatus.Disconnecting

    private var connection: OpenVPNConnection? = null
    private var appContext: Context? = null

    private val stateListener: (ConnectionState) -> Unit = { state ->
        _status.value = when (state) {
            ConnectionState.CONNECTED -> VpnStatus.Connected
            ConnectionState.CONNECTING, ConnectionState.READYFORCONNECT -> VpnStatus.Connecting
            ConnectionState.DISCONNECTING -> VpnStatus.Disconnecting
            ConnectionState.DISCONNECTED, ConnectionState.IDLE -> VpnStatus.Disconnected
            ConnectionState.PERMISSION_NOT_GRANTED -> VpnStatus.Disconnected
            else -> _status.value
        }
        if (_status.value == VpnStatus.Connected && _connectedAt.value == null) {
            _connectedAt.value = System.currentTimeMillis()
        }
        if (_status.value == VpnStatus.Disconnected) {
            _connectedAt.value = null
            _activeServerName.value = ""
            _activeLineName.value = ""
            _activeNodeId.value = 0
        }
    }

    /** 首次使用前注入 Context（Application 级） */
    fun init(context: Context) {
        appContext = context.applicationContext
        if (connection == null) {
            connection = OpenVPNConnection(context.applicationContext, stateListener)
        }
    }

    /** 冷启动 / 回到前台时同步状态（VpnService 是否已在运行） */
    suspend fun refreshStatus() {
        val context = appContext ?: return
        val running = VpnService.prepare(context) == null && isServiceRunning(context)
        _status.value = if (running) VpnStatus.Connected else VpnStatus.Disconnected
        if (running && _connectedAt.value == null) {
            _connectedAt.value = System.currentTimeMillis()
        }
    }

    suspend fun prepare() {
        refreshStatus()
    }

    /**
     * 建立隧道：解析主控下发的 .ovpn 配置并交给 OpenVPN 3 内核。
     * @param profile 主控返回的线路配置（含 ovpn 文本）
     * @param username 平台账号（用于 auth-user-pass）
     * @param password 平台密码
     */
    suspend fun connect(profile: LineConfig, username: String, password: String) {
        val context = appContext ?: throw APIError("客户端未初始化，请重启 App")
        val ovpnText = profile.content.ifEmpty { throw APIError("线路配置为空，请重新下载") }

        // 未授权时先请求系统 VPN 授权（首次弹窗）
        val prepareIntent = VpnService.prepare(context)
        if (prepareIntent != null) {
            _lastError.value = "需要授权 VPN 连接，请在弹出的系统窗口中允许"
            throw APIError("需要授权 VPN 连接，请在弹出的系统窗口中允许后重试")
        }

        _lastError.value = null
        _status.value = VpnStatus.Connecting
        _activeServerName.value = profile.nodeName
        _activeLineName.value = profile.lineName
        _activeNodeId.value = profile.nodeId

        // 追加 auth-user-pass：OpenVPN 3 支持内联凭据块
        val withCreds = buildString {
            append(ovpnText.trimEnd())
            append("\n<auth-user-pass>\n")
            append(username).append('\n')
            append(password).append('\n')
            append("</auth-user-pass>\n")
        }

        val config: OpenVPNConfig = try {
            OpenVPNConfigParser.parse(withCreds)
        } catch (e: Exception) {
            _status.value = VpnStatus.Disconnected
            throw APIError("线路配置解析失败：${e.message ?: "格式不支持"}")
        }

        connection = OpenVPNConnection(context, stateListener)
        connection?.start(config)
    }

    /** 断开隧道（对应 iOS disconnect） */
    fun disconnect() {
        _status.value = VpnStatus.Disconnecting
        connection?.stop()
        _status.value = VpnStatus.Disconnected
        _connectedAt.value = null
        _activeServerName.value = ""
        _activeLineName.value = ""
        _activeNodeId.value = 0
    }

    private fun isServiceRunning(context: Context): Boolean {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
            ?: return false
        @Suppress("DEPRECATION")
        return manager.getRunningServices(Int.MAX_VALUE).any {
            it.service.className == "com.tim.openvpn.service.OpenVPNService"
        }
    }
}