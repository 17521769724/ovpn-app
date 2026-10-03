package com.ovpn.panel.features

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.ovpn.panel.core.APIError
import com.ovpn.panel.core.ApiService
import com.ovpn.panel.core.AppState
import com.ovpn.panel.core.BannerKind
import com.ovpn.panel.core.DS
import com.ovpn.panel.core.Format
import com.ovpn.panel.core.LineConfig
import com.ovpn.panel.core.LinesPayload
import com.ovpn.panel.core.LocalPalette
import com.ovpn.panel.core.MonospaceDigits
import com.ovpn.panel.core.Palette
import com.ovpn.panel.core.SecureStore
import com.ovpn.panel.core.ServerNode
import com.ovpn.panel.core.VPNLine
import com.ovpn.panel.core.VpnManager
import com.ovpn.panel.core.VpnStatus
import com.ovpn.panel.core.vpnStatusText
import com.ovpn.panel.ui.AppButton
import com.ovpn.panel.ui.AppCard
import com.ovpn.panel.ui.AppTextField
import com.ovpn.panel.ui.BannerBar
import com.ovpn.panel.ui.ButtonStyleKind
import com.ovpn.panel.ui.EmptyHint
import com.ovpn.panel.ui.IconTile
import com.ovpn.panel.ui.LoadingBlock
import com.ovpn.panel.ui.ScreenScaffold
import com.ovpn.panel.ui.SectionHeader
import com.ovpn.panel.ui.StatusBadge
import com.ovpn.panel.ui.pressableScale
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.Locale

// MARK: - 主页：线路连接（对应 iOS `HomeView`）

/**
 * 主页：选择服务器 → 选择线路 → 连接（VPN 隧道）。
 * 连接中/已连接时整页切换为彩色泡泡圆环状态页。
 *
 * 对应 iOS `struct HomeView: View`。
 *
 * @param onOpen 跳转子页面（本屏幕当前无子路由，保留参数以统一各 Tab 根页面签名）。
 */
@Composable
fun HomeView(onOpen: (String) -> Unit) {
    // onOpen 当前未被使用：线路页没有需要跳转的子页面，保留参数以统一各 Tab 根页面签名。
    val palette = LocalPalette.current
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()

    // 隧道状态（对应 iOS `@ObservedObject private var vpn = VPNManager.shared`）
    val status by VpnManager.status.collectAsState()
    val connectedAt by VpnManager.connectedAt.collectAsState()
    val activeServerName by VpnManager.activeServerName.collectAsState()
    val activeLineName by VpnManager.activeLineName.collectAsState()
    val activeNodeId by VpnManager.activeNodeId.collectAsState()

    // 数据与选择状态
    var payload by remember { mutableStateOf<LinesPayload?>(null) }
    var loading by remember { mutableStateOf(true) }
    var selectedNodeId by remember { mutableStateOf<Int?>(null) }
    var selectedLineId by remember { mutableStateOf<Int?>(null) }
    var category by remember { mutableStateOf("全部") }
    /** 正在准备的地址族（v4 / v6）：两个连接按钮各自独立显示加载状态 */
    var connectingFamily by remember { mutableStateOf<String?>(null) }
    var showServerPicker by remember { mutableStateOf(false) }
    /** 是否处于一次「用户主动发起」的连接尝试中，用于识别失败 */
    var attemptActive by remember { mutableStateOf(false) }

    // 当前会话的实时网速与流量（每次重新连接都会重新计数）
    var sessionRx by remember { mutableStateOf(0L) }
    var sessionTx by remember { mutableStateOf(0L) }
    var downSpeed by remember { mutableStateOf(0.0) }
    var upSpeed by remember { mutableStateOf(0.0) }
    var connectedSince by remember { mutableStateOf<Long?>(null) }
    var lastSample by remember { mutableStateOf<Sample?>(null) }
    var statsJob by remember { mutableStateOf<Job?>(null) }
    /** 每秒心跳：驱动连接时长计时的刷新 */
    var nowTick by remember { mutableStateOf(System.currentTimeMillis()) }

    // 输入一次密码后保存，后续连接自动使用
    var passwordInput by remember { mutableStateOf("") }
    var pendingProfile by remember { mutableStateOf<LineConfig?>(null) }
    var showPasswordSheet by remember { mutableStateOf(false) }
    var savingPassword by remember { mutableStateOf(false) }

    // MARK: 派生值
    val selectedNode: ServerNode? = payload?.nodes?.firstOrNull { it.id == selectedNodeId }
    val selectedLine: VPNLine? = payload?.lines?.firstOrNull { it.id == selectedLineId }
    val categories: List<String> = buildCategories(payload)
    val visibleLines: List<VPNLine> = payload?.lines.orEmpty().let { lines ->
        if (category == "全部") lines else lines.filter { it.category == category }
    }
    /** 未选服务器，或用户主动点「更换服务器」时展示服务器列表 */
    val showingServerPicker = selectedNode == null || showServerPicker
    /** 连接中 / 已连接 / 正在断开：整页切换为连接状态页 */
    val connectionActive = status == VpnStatus.Connecting || status == VpnStatus.Connected ||
        status == VpnStatus.Reasserting || status == VpnStatus.Disconnecting

    /** 当前会话的起始时间（毫秒）：优先系统隧道记录，其次本地兜底 */
    val sessionStart: Long? = connectedAt ?: connectedSince

    fun currentDurationText(): String {
        val start = sessionStart ?: return "--:--"
        val seconds = maxOf(0, ((nowTick - start) / 1000).toInt())
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
        else String.format(Locale.US, "%02d:%02d", m, s)
    }

    // MARK: 数据与动作（对应 iOS 私有方法）

    /** 加载服务器与线路；clearSelection=true 时清空已选线路（底部连接栏随之收起） */
    suspend fun load(clearSelection: Boolean = false) {
        loading = true
        try {
            val result = ApiService.fetchLines()
            payload = result
            if (clearSelection) selectedLineId = null
            selectedNodeId?.let { sel ->
                if (result.nodes.none { it.id == sel }) {
                    selectedNodeId = null
                    selectedLineId = null
                }
            }
            selectedLineId?.let { line ->
                if (result.lines.none { it.id == line }) selectedLineId = null
            }
        } catch (e: Exception) {
            // 下拉刷新取消请求时静默处理，避免弹出「已取消」错误
            if (AppState.isCancelled(e)) return
            AppState.report(e)
        } finally {
            loading = false
        }
    }

    /** 重新连接时清空计数（流量按当前会话统计） */
    fun resetSessionStats() {
        sessionRx = 0
        sessionTx = 0
        downSpeed = 0.0
        upSpeed = 0.0
        lastSample = null
    }

    /** 轮询主控获取当前会话的流量，换算为实时网速 */
    suspend fun sampleStats() {
        if (VpnManager.status.value != VpnStatus.Connected) return
        val center = try {
            ApiService.fetchUserCenter()
        } catch (e: Exception) {
            return
        }
        // 绑定到当前连接的服务器，避免连到别的节点时统计串台
        val session = center.onlineSessions.firstOrNull { it.nodeId == VpnManager.activeNodeId.value }
            ?: center.onlineSessions.firstOrNull() ?: return

        // 从主控会话时间恢复计时（例如在系统设置里连接后回到 App）
        if (connectedSince == null) {
            Format.parse(session.connectedAt)?.let { connectedSince = it.toEpochMilli() }
        }

        val rx = session.rxBytes
        val tx = session.txBytes
        sessionRx = rx
        sessionTx = tx

        val now = System.currentTimeMillis()
        lastSample?.let { last ->
            val elapsed = (now - last.at) / 1000.0
            if (elapsed > 0.5) {
                val downDelta = maxOf(0L, tx - last.tx).toDouble()
                val upDelta = maxOf(0L, rx - last.rx).toDouble()
                val down = downDelta / elapsed
                val up = upDelta / elapsed
                // 指数平滑，避免读数跳动
                downSpeed = downSpeed * 0.4 + down * 0.6
                upSpeed = upSpeed * 0.4 + up * 0.6
            }
        }
        lastSample = Sample(rx, tx, now)
    }

    fun startStats() {
        statsJob?.cancel()
        statsJob = scope.launch {
            while (isActive) {
                sampleStats()
                delay(2_000L)
            }
        }
    }

    fun stopStats() {
        statsJob?.cancel()
        statsJob = null
    }

    /** 发起隧道连接（对应 iOS `startTunnel`，失败向上抛） */
    suspend fun startTunnel(profile: LineConfig, password: String) {
        val username = AppState.user.value?.username
        if (username.isNullOrEmpty()) throw APIError("登录状态异常，请重新登录")
        attemptActive = true
        try {
            VpnManager.connect(profile, username, password)
        } catch (e: Exception) {
            attemptActive = false
            throw e
        }
    }

    /** 选择线路后连接（family: v4 / v6） */
    suspend fun connect(family: String) {
        val node = selectedNode ?: return
        val line = selectedLine ?: return
        if (connectingFamily != null) return
        if (payload?.quota?.valid != true) {
            val reason = payload?.quota?.reason.orEmpty()
            AppState.showToast(reason.ifEmpty { "当前订阅状态不可用" }, BannerKind.Warning)
            return
        }

        // 连接前先检查账号状态：被拉黑 / 封禁 / 到期 / 超流量直接拦截
        val notice = try {
            ApiService.fetchUserStatus().notice
        } catch (e: Exception) {
            null
        }
        if (notice != null) {
            val isBlock = notice.code == "blocked" || notice.code == "banned"
            AppState.showToast(notice.message, if (isBlock) BannerKind.Error else BannerKind.Warning)
            return
        }

        connectingFamily = family
        try {
            val config = ApiService.fetchLineConfig(line.id, node.id, family)
            val saved = SecureStore.load(SecureStore.passwordAccount).orEmpty()
            if (saved.isEmpty()) {
                pendingProfile = config
                passwordInput = ""
                showPasswordSheet = true
                return
            }
            startTunnel(config, saved)
        } catch (e: Exception) {
            if (AppState.isCancelled(e)) return
            AppState.report(e)
        } finally {
            connectingFamily = null
        }
    }

    /** 密码输入完成后保存并连接（对应 iOS `confirmPasswordAndConnect`） */
    suspend fun confirmPasswordAndConnect() {
        val profile = pendingProfile ?: return
        if (passwordInput.isEmpty()) {
            AppState.showToast("请输入登录密码", BannerKind.Warning)
            return
        }
        savingPassword = true
        try {
            SecureStore.save(passwordInput, SecureStore.passwordAccount)
            val password = passwordInput
            passwordInput = ""
            showPasswordSheet = false
            pendingProfile = null
            startTunnel(profile, password)
        } catch (e: Exception) {
            AppState.report(e)
        } finally {
            savingPassword = false
        }
    }

    fun disconnect() {
        attemptActive = false
        VpnManager.disconnect()
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        stopStats()
        AppState.showToast("已断开连接", BannerKind.Info)
    }

    /** 监听隧道状态：只有真正连接成功才进入「已连接」；失败则回到选择页并提示 */
    fun handleStatusChange(newStatus: VpnStatus) {
        when (newStatus) {
            VpnStatus.Connected -> {
                connectingFamily = null
                if (attemptActive) {
                    attemptActive = false
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    val name = VpnManager.activeServerName.value
                    AppState.showToast(if (name.isEmpty()) "已连接" else "已连接到 $name", BannerKind.Success)
                    resetSessionStats()
                }
                if (sessionStart == null) connectedSince = System.currentTimeMillis()
                startStats()
            }

            VpnStatus.Disconnected -> {
                if (attemptActive) {
                    attemptActive = false
                    connectingFamily = null
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    AppState.showToast("连接失败，请检查账号状态或稍后重试", BannerKind.Error)
                    // 立即拉取账号状态，若存在具体异常（被踢 / 到期 / 超流量）则用更精确的提示覆盖
                    scope.launch { AppState.checkStatusNow() }
                }
                stopStats()
                connectedSince = null
            }

            else -> Unit
        }
    }

    // MARK: 生命周期（对应 iOS `.task` / `.onReceive` / `.onChange` / `.onDisappear`）

    LaunchedEffect(Unit) {
        VpnManager.prepare()
        load()
        // 冷启动时隧道可能已由「系统设置」建立：直接进入已连接状态（含计时与实时统计）
        if (VpnManager.status.value == VpnStatus.Connected) {
            if (connectedAt == null) connectedSince = System.currentTimeMillis()
            startStats()
        }
    }

    // 服务器列表自动刷新（10s）：让「实时带宽 / 负载」保持实时（不打断已选线路）
    LaunchedEffect(Unit) {
        while (isActive) {
            delay(10_000L)
            val active = VpnManager.status.value == VpnStatus.Connecting ||
                VpnManager.status.value == VpnStatus.Connected ||
                VpnManager.status.value == VpnStatus.Reasserting ||
                VpnManager.status.value == VpnStatus.Disconnecting
            if (!active && !loading && payload != null) load()
        }
    }

    // 每秒心跳：仅连接状态页需要驱动计时
    LaunchedEffect(Unit) {
        while (isActive) {
            delay(1_000L)
            if (sessionStart != null) nowTick = System.currentTimeMillis()
        }
    }

    // onChange(of: vpn.status)：仅状态真正变化时处理
    var lastHandledStatus by remember { mutableStateOf<VpnStatus?>(null) }
    LaunchedEffect(status) {
        val previous = lastHandledStatus
        lastHandledStatus = status
        if (previous != null && previous != status) handleStatusChange(status)
    }

    DisposableEffect(Unit) {
        onDispose { stopStats() }
    }

    // MARK: UI
    ScreenScaffold(title = "线路连接") {
        if (connectionActive) {
            ConnectionPage(
                status = status,
                duration = currentDurationText(),
                downSpeed = downSpeed,
                upSpeed = upSpeed,
                sessionRx = sessionRx,
                sessionTx = sessionTx,
                serverName = activeServerName,
                lineName = activeLineName,
                statusText = vpnStatusText(status),
                onDisconnect = { disconnect() },
            )
        } else {
            Column(modifier = Modifier.fillMaxSize()) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = DS.Size.pagePadding)
                        .padding(top = 8.dp, bottom = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
                ) {
                    StepHint(showingServerPicker = showingServerPicker, level = payload?.level)

                    payload?.let { p ->
                        if (!p.quota.valid) {
                            BannerBar(
                                message = p.quota.reason.ifEmpty { "订阅状态异常，暂时无法连接" },
                                kind = BannerKind.Error,
                            )
                        } else {
                            val limit = if (p.deviceLimit > 0) "${p.deviceLimit} 台" else "不限"
                            BannerBar(
                                message = "订阅正常｜限速 ${Format.speed(p.speedLimitKbps)}｜设备上限 $limit",
                                kind = BannerKind.Success,
                            )
                        }
                    }

                    if (loading && payload == null) {
                        LoadingBlock(text = "正在获取服务器与线路…")
                    } else if (showingServerPicker) {
                        ServerSection(
                            nodes = payload?.nodes.orEmpty(),
                            selectedNodeId = selectedNodeId,
                            hasSelectedNode = selectedNode != null,
                            onBackToLines = {
                                showServerPicker = false
                                selectedLineId = null
                            },
                            onSelectNode = { id ->
                                selectedNodeId = id
                                selectedLineId = null
                                showServerPicker = false
                            },
                        )
                    } else {
                        LineSection(
                            node = selectedNode,
                            lines = visibleLines,
                            categories = categories,
                            category = category,
                            selectedLineId = selectedLineId,
                            onCategory = { category = it },
                            onChangeServer = {
                                showServerPicker = true
                                selectedLineId = null
                            },
                            onSelectLine = { selectedLineId = it },
                        )
                    }

                    Spacer(Modifier.height(12.dp))
                }

                val node = selectedNode
                val line = selectedLine
                if (node != null && line != null) {
                    BottomBar(
                        node = node,
                        line = line,
                        connectingFamily = connectingFamily,
                        onConnect = { family -> scope.launch { connect(family) } },
                    )
                }
            }
        }
    }

    if (showPasswordSheet) {
        PasswordSheet(
            username = AppState.user.value?.username.orEmpty(),
            password = passwordInput,
            onPasswordChange = { passwordInput = it },
            saving = savingPassword,
            onCancel = {
                showPasswordSheet = false
                pendingProfile = null
                passwordInput = ""
            },
            onConfirm = { scope.launch { confirmPasswordAndConnect() } },
        )
    }
}

/** 会话流量采样（对应 iOS `(rx: Int64, tx: Int64, at: Date)` 元组） */
private data class Sample(val rx: Long, val tx: Long, val at: Long)

/** 分类列表（对应 iOS `categories` 计算属性） */
private fun buildCategories(payload: LinesPayload?): List<String> {
    if (payload == null) return listOf("全部")
    val preset = payload.categories
    if (!preset.isNullOrEmpty()) {
        val list = mutableListOf("全部")
        for (name in preset) if (!list.contains(name)) list.add(name)
        return list
    }
    val list = mutableListOf("全部")
    for (line in payload.lines) if (!list.contains(line.category)) list.add(line.category)
    return list
}

// MARK: - 选择流程（服务器 → 线路）

/** 步骤提示（对应 iOS `stepHint`） */
@Composable
private fun StepHint(showingServerPicker: Boolean, level: Int?) {
    val palette = LocalPalette.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = if (showingServerPicker) Icons.Filled.LooksOne else Icons.Filled.LooksTwo,
            contentDescription = null,
            tint = palette.primary,
            modifier = Modifier.size(14.dp),
        )
        Text(
            text = if (showingServerPicker) "第 1 步" else "第 2 步",
            style = DS.Font.caption,
            color = palette.mutedForeground,
        )
        VLine(height = 10.dp)
        Text(
            text = if (showingServerPicker) "选择服务器" else "选择线路并连接",
            style = DS.Font.caption,
            color = palette.mutedForeground,
        )
        Spacer(Modifier.weight(1f))
        if (level != null) {
            StatusBadge(
                text = "Lv.$level",
                background = DS.IconColor.teal.copy(alpha = 0.14f),
                foreground = DS.IconColor.teal,
            )
        }
    }
}

// MARK: - 连接状态页（对应 iOS `connectionPage`）

@Composable
private fun ConnectionPage(
    status: VpnStatus,
    duration: String,
    downSpeed: Double,
    upSpeed: Double,
    sessionRx: Long,
    sessionTx: Long,
    serverName: String,
    lineName: String,
    statusText: String,
    onDisconnect: () -> Unit,
) {
    val palette = LocalPalette.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = DS.Size.pagePadding)
            .padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Box(modifier = Modifier.fillMaxWidth().padding(top = 12.dp), contentAlignment = Alignment.Center) {
            ConnectRing(status = status, palette = palette, duration = duration, diameter = 224.dp)
        }

        // 实时网速 + 本次会话流量
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(DS.Size.gap),
        ) {
            SpeedTile(modifier = Modifier.weight(1f), downSpeed = downSpeed, upSpeed = upSpeed)
            TrafficTile(modifier = Modifier.weight(1f), sessionRx = sessionRx, sessionTx = sessionTx)
        }

        InfoPanel(
            serverName = serverName,
            lineName = lineName,
            statusText = statusText,
            isConnected = status == VpnStatus.Connected,
        )

        when (status) {
            VpnStatus.Connected -> AppButton(
                title = "断开连接",
                icon = Icons.Filled.StopCircle,
                style = ButtonStyleKind.Destructive,
                onClick = onDisconnect,
            )

            VpnStatus.Connecting, VpnStatus.Reasserting -> AppButton(
                title = "取消连接",
                icon = Icons.Filled.Cancel,
                style = ButtonStyleKind.Secondary,
                onClick = onDisconnect,
            )

            VpnStatus.Disconnecting -> AppButton(
                title = "正在断开…",
                icon = Icons.Filled.StopCircle,
                style = ButtonStyleKind.Secondary,
                loading = true,
                onClick = {},
            )

            else -> Unit
        }

        Spacer(Modifier.height(16.dp))
    }
}

/** 实时网速卡片（对应 iOS `speedTile`） */
@Composable
private fun SpeedTile(modifier: Modifier = Modifier, downSpeed: Double, upSpeed: Double) {
    val palette = LocalPalette.current
    AppCard(modifier = modifier, padding = 14.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.Speed,
                    contentDescription = null,
                    tint = DS.IconColor.green,
                    modifier = Modifier.size(12.dp),
                )
                Text(text = "实时网速", style = DS.Font.caption, color = palette.mutedForeground)
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.ArrowDownward,
                    contentDescription = null,
                    tint = DS.IconColor.green,
                    modifier = Modifier.size(13.dp),
                )
                Text(
                    text = Format.speedValue(downSpeed),
                    style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.SemiBold).merge(MonospaceDigits),
                    color = palette.foreground,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.ArrowUpward,
                    contentDescription = null,
                    tint = DS.IconColor.teal,
                    modifier = Modifier.size(13.dp),
                )
                Text(
                    text = Format.speedValue(upSpeed),
                    style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium).merge(MonospaceDigits),
                    color = palette.secondaryText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/** 本次流量卡片（对应 iOS `trafficTile`） */
@Composable
private fun TrafficTile(modifier: Modifier = Modifier, sessionRx: Long, sessionTx: Long) {
    val palette = LocalPalette.current
    AppCard(modifier = modifier, padding = 14.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.BarChart,
                    contentDescription = null,
                    tint = DS.IconColor.cyan,
                    modifier = Modifier.size(12.dp),
                )
                Text(text = "本次流量", style = DS.Font.caption, color = palette.mutedForeground)
            }
            Text(
                text = Format.bytes(sessionTx + sessionRx),
                style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.SemiBold).merge(MonospaceDigits),
                color = palette.foreground,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    text = "↑ ${Format.bytes(sessionRx)}",
                    style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium).merge(MonospaceDigits),
                    color = DS.IconColor.green,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                VLine(height = 9.dp)
                Text(
                    text = "↓ ${Format.bytes(sessionTx)}",
                    style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium).merge(MonospaceDigits),
                    color = DS.IconColor.teal,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/** 当前服务器 / 当前路线 / 连接状态（对应 iOS `infoPanel`） */
@Composable
private fun InfoPanel(serverName: String, lineName: String, statusText: String, isConnected: Boolean) {
    val palette = LocalPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(DS.Radius.xl))
            .background(palette.card)
            .border(1.dp, palette.border, RoundedCornerShape(DS.Radius.xl)),
    ) {
        InfoLine(
            icon = Icons.Filled.Dns,
            label = "当前服务器",
            value = if (serverName.isEmpty()) "-" else serverName,
        )
        DividerLine()
        InfoLine(
            icon = Icons.Filled.Route,
            label = "当前路线",
            value = if (lineName.isEmpty()) "-" else lineName,
        )
        DividerLine()
        InfoLine(
            icon = Icons.Filled.WifiTethering,
            label = "连接状态",
            value = statusText,
            valueColor = if (isConnected) palette.onlineText else palette.warningText,
        )
    }
}

/** 信息行（对应 iOS `infoLine`） */
@Composable
private fun InfoLine(icon: ImageVector, label: String, value: String, valueColor: Color? = null) {
    val palette = LocalPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier
                .size(26.dp)
                .clip(RoundedCornerShape(DS.Radius.sm))
                .background(palette.primary.copy(alpha = 0.10f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = palette.primary,
                modifier = Modifier.size(13.dp),
            )
        }
        Text(text = label, style = DS.Font.bodySmall, color = palette.mutedForeground)
        Spacer(Modifier.weight(1f))
        Text(
            text = value,
            style = DS.Font.value,
            color = valueColor ?: palette.secondaryText,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** 分隔线（对应 iOS `divider`） */
@Composable
private fun DividerLine() {
    val palette = LocalPalette.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 50.dp)
            .height(1.dp)
            .background(palette.border),
    )
}

// MARK: - 服务器列表（对应 iOS `serverSection` / `serverCard`）

@Composable
private fun ServerSection(
    nodes: List<ServerNode>,
    selectedNodeId: Int?,
    hasSelectedNode: Boolean,
    onBackToLines: () -> Unit,
    onSelectNode: (Int) -> Unit,
) {
    val palette = LocalPalette.current
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(DS.Size.gap),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SectionHeader(title = "选择服务器", subtitle = "显示实时状态与负载，共 ${nodes.size} 台")
            Spacer(Modifier.weight(1f))
            if (hasSelectedNode) {
                // 非白底按钮：主题色浅底胶囊，明确可点
                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(palette.primary.copy(alpha = 0.14f))
                        .pressableScale()
                        .clickable(onClick = onBackToLines)
                        .height(DS.Size.buttonHeightSmall)
                        .padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        imageVector = Icons.Filled.ChevronLeft,
                        contentDescription = null,
                        tint = palette.primary,
                        modifier = Modifier.size(11.dp),
                    )
                    Text(
                        text = "返回线路",
                        style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold),
                        color = palette.primary,
                    )
                }
            }
        }

        if (nodes.isEmpty()) {
            EmptyHint(
                icon = Icons.Filled.Dns,
                title = "暂无可用服务器",
                subtitle = "请联系管理员添加节点",
            )
        } else {
            for (node in nodes) {
                val modifier = if (node.usable) {
                    Modifier.pressableScale(scale = 0.98f).clickable { onSelectNode(node.id) }
                } else {
                    Modifier
                }
                ServerCard(
                    modifier = modifier,
                    node = node,
                    isSelected = node.id == selectedNodeId,
                )
            }
        }
    }
}

/** 服务器卡片（对应 iOS `serverCard`） */
@Composable
private fun ServerCard(modifier: Modifier = Modifier, node: ServerNode, isSelected: Boolean) {
    val palette = LocalPalette.current
    val isOnline = node.status == "online"
    // 不可用（离线 / 等级不足）：整卡使用不可点击的灰底，弱化展示
    Box(
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayerAlpha(if (node.usable) 1f else 0.8f),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    if (isSelected) {
                        Modifier.border(1.5.dp, palette.primary, RoundedCornerShape(DS.Radius.xl))
                    } else {
                        Modifier
                    },
                ),
        ) {
            AppCard(background = if (node.usable) null else palette.muted) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            IconTile(
                                icon = if (isOnline) Icons.Filled.Dns else Icons.Filled.CloudOff,
                                color = if (isOnline) DS.IconColor.green else DS.IconColor.slate,
                            )
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    Text(
                                        text = node.name,
                                        style = DS.Font.section,
                                        color = palette.foreground,
                                    )
                                    if (node.dcoEnabled) {
                                        StatusBadge(
                                            text = "DCO",
                                            background = palette.onlineBg,
                                            foreground = palette.onlineText,
                                        )
                                    }
                                }
                                val region = node.region
                                if (!region.isNullOrEmpty()) {
                                    Text(text = region, style = DS.Font.caption, color = palette.mutedForeground)
                                }
                            }
                        }
                        Spacer(Modifier.weight(1f))
                        NodeStatusBadge(status = node.status)
                    }

                    // 已配置的 IPv4 / IPv6 地址（服务器离线时隐藏）
                    val v4 = node.displayIPv4
                    val v6 = node.displayIPv6
                    if (isOnline && (v4 != null || v6 != null)) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(DS.Radius.md))
                                .background(palette.muted.copy(alpha = 0.5f))
                                .padding(horizontal = 10.dp, vertical = 7.dp),
                            verticalArrangement = Arrangement.spacedBy(5.dp),
                        ) {
                            if (v4 != null) AddressRow(label = "IPv4", value = v4, color = DS.IconColor.green)
                            if (v6 != null) AddressRow(label = "IPv6", value = v6, color = DS.IconColor.teal)
                        }
                    }

                    Row(modifier = Modifier.fillMaxWidth()) {
                        MetricCell(modifier = Modifier.weight(1f), title = "在线人数", value = "${node.onlineCount}")
                        MetricCell(
                            modifier = Modifier.weight(1f),
                            title = "流量倍率",
                            value = String.format(Locale.US, "×%.2f", node.ratio),
                        )
                        MetricCell(modifier = Modifier.weight(1f), title = "等级要求", value = "Lv.${node.levelRequired}")
                    }

                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        StatBar(label = "CPU", value = node.cpuUsage, icon = Icons.Filled.DeveloperBoard)
                        StatBar(label = "内存", value = node.memUsage, icon = Icons.Filled.Memory)
                        StatBar(label = "磁盘", value = node.diskUsage, icon = Icons.Filled.Storage)
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(7.dp),
                    ) {
                        Text(text = "实时", style = DS.Font.caption, color = palette.mutedForeground)
                        Text(
                            text = "↑ ${Format.bytes(node.rxRateValue)}/s",
                            style = DS.Font.caption,
                            color = DS.IconColor.green,
                        )
                        VLine(height = 10.dp)
                        Text(
                            text = "↓ ${Format.bytes(node.txRateValue)}/s",
                            style = DS.Font.caption,
                            color = DS.IconColor.teal,
                        )
                        Spacer(Modifier.weight(1f))
                        if (!node.usable) {
                            Text(
                                text = node.unusableReason,
                                style = DS.Font.caption,
                                color = palette.offlineText,
                            )
                        } else if (isSelected) {
                            Text(text = "已选择", style = DS.Font.caption, color = palette.onlineText)
                        }
                    }
                }
            }
        }
    }
}

/** 单行地址展示（对应 iOS `addressRow`） */
@Composable
private fun AddressRow(label: String, value: String, color: Color) {
    val palette = LocalPalette.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            modifier = Modifier
                .height(16.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(color.copy(alpha = 0.14f))
                .padding(horizontal = 6.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = label,
                style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold),
                color = color,
            )
        }
        Text(
            text = value,
            style = TextStyle(fontSize = 12.sp, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace),
            color = palette.secondaryText,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** 指标单元格（对应 iOS `metricCell`） */
@Composable
private fun MetricCell(modifier: Modifier = Modifier, title: String, value: String) {
    val palette = LocalPalette.current
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(text = title, style = DS.Font.caption, color = palette.mutedForeground)
        Text(text = value, style = DS.Font.number, color = palette.foreground)
    }
}

// MARK: - 线路列表（对应 iOS `lineSection` / `lineCard`）

@Composable
private fun LineSection(
    node: ServerNode?,
    lines: List<VPNLine>,
    categories: List<String>,
    category: String,
    selectedLineId: Int?,
    onCategory: (String) -> Unit,
    onChangeServer: () -> Unit,
    onSelectLine: (Int) -> Unit,
) {
    val palette = LocalPalette.current
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(DS.Size.gap),
    ) {
        if (node != null) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(DS.Radius.xl))
                    .background(palette.muted.copy(alpha = 0.5f))
                    .padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                IconTile(icon = Icons.Filled.Dns, color = DS.IconColor.green, size = 38.dp)
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(text = node.name, style = DS.Font.section, color = palette.foreground)
                    // 离线服务器不展示地址（IPv4 / IPv6 都隐藏）
                    if (node.status == "online") {
                        val v4 = node.displayIPv4
                        val v6 = node.displayIPv6
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            if (v4 != null) {
                                Text(
                                    text = v4,
                                    style = DS.Font.caption,
                                    color = palette.mutedForeground,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            if (v4 != null && v6 != null) VLine(height = 9.dp)
                            if (v6 != null) {
                                Text(
                                    text = v6,
                                    style = DS.Font.caption,
                                    color = palette.mutedForeground,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(palette.accentGradient)
                        .pressableScale()
                        .clickable(onClick = onChangeServer)
                        .height(DS.Size.buttonHeightSmall)
                        .padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(11.dp),
                    )
                    Text(
                        text = "更换",
                        style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold),
                        color = Color.White,
                    )
                }
            }
        }

        if (categories.size > 1) {
            // 「全部」与竖线固定在左侧不参与滑动，其余分类单独横向滚动
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                ChipButton(title = "全部", selected = category == "全部") { onCategory("全部") }
                VLine(height = 16.dp)
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 1.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    for (item in categories.drop(1)) {
                        ChipButton(title = item, selected = item == category) { onCategory(item) }
                    }
                }
            }
        }

        SectionHeader(
            title = "选择线路",
            subtitle = if (node?.supportsIPv6 == true) {
                "该服务器支持 IPv6，选好路线后可分别用 IPv4 / IPv6 连接"
            } else {
                "点击线路卡片后使用底部「连接」按钮"
            },
        )

        if (lines.isEmpty()) {
            EmptyHint(
                icon = Icons.Filled.SettingsInputAntenna,
                title = "暂无可用的线路",
                subtitle = "线路正在维护或尚未配置",
            )
        } else {
            for (line in lines) {
                LineCard(
                    modifier = Modifier.pressableScale(scale = 0.98f).clickable { onSelectLine(line.id) },
                    line = line,
                    node = node,
                    isSelected = line.id == selectedLineId,
                )
            }
        }
    }
}

/** 线路卡片（对应 iOS `lineCard`） */
@Composable
private fun LineCard(modifier: Modifier = Modifier, line: VPNLine, node: ServerNode?, isSelected: Boolean) {
    val palette = LocalPalette.current
    val isUDP = line.protocol.lowercase() == "udp"
    val accent = if (isUDP) DS.IconColor.amber else DS.IconColor.tealDeep
    Box(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (isSelected) {
                    Modifier.border(1.5.dp, palette.primary, RoundedCornerShape(DS.Radius.xl))
                } else {
                    Modifier
                },
            ),
    ) {
        AppCard {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    IconTile(
                        icon = if (isUDP) Icons.Filled.Bolt else Icons.Filled.Shield,
                        color = accent,
                    )
                    Text(text = line.name, style = DS.Font.section, color = palette.foreground)
                    Spacer(Modifier.weight(1f))
                    StatusBadge(
                        text = line.protocolUpper,
                        background = accent.copy(alpha = 0.14f),
                        foreground = accent,
                    )
                }
                val remark = line.remark
                if (!remark.isNullOrEmpty()) {
                    Text(
                        text = remark,
                        style = DS.Font.caption,
                        color = palette.secondaryText,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(text = "协议 / 端口", style = DS.Font.caption, color = palette.mutedForeground)
                    Spacer(Modifier.weight(1f))
                    Text(
                        text = "${line.protocolUpper} ${line.port}",
                        style = DS.Font.number,
                        color = palette.foreground,
                    )
                }
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(text = "服务器", style = DS.Font.caption, color = palette.mutedForeground)
                    Spacer(Modifier.weight(1f))
                    Text(
                        text = node?.name ?: "-",
                        style = DS.Font.bodySmall,
                        color = palette.foreground,
                    )
                }
            }
        }
    }
}

// MARK: - 底部连接栏（对应 iOS `bottomBar`）

@Composable
private fun BottomBar(
    node: ServerNode,
    line: VPNLine,
    connectingFamily: String?,
    onConnect: (String) -> Unit,
) {
    val palette = LocalPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(palette.background)
            .padding(horizontal = DS.Size.pagePadding)
            .padding(top = 10.dp, bottom = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = node.name,
                style = DS.Font.bodySmall,
                color = palette.secondaryText,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            VLine(height = 10.dp)
            Text(
                text = line.name,
                style = DS.Font.bodySmall,
                color = palette.secondaryText,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = "${line.protocolUpper} ${line.port}",
                style = DS.Font.caption,
                color = palette.mutedForeground,
            )
        }

        if (node.supportsIPv6) {
            // 服务器支持 IPv6：IPv4 / IPv6 两个按钮并排，加载状态相互独立
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                AppButton(
                    title = "IPv4 连接",
                    modifier = Modifier.weight(1f),
                    icon = Icons.Filled.Looks4,
                    loading = connectingFamily == "v4",
                    disabled = !node.supportsIPv4 || connectingFamily == "v6",
                    onClick = { onConnect("v4") },
                )
                AppButton(
                    title = "IPv6 连接",
                    modifier = Modifier.weight(1f),
                    icon = Icons.Filled.Looks6,
                    style = ButtonStyleKind.Teal,
                    loading = connectingFamily == "v6",
                    disabled = !node.supportsIPv6 || connectingFamily == "v4",
                    onClick = { onConnect("v6") },
                )
            }
        } else {
            AppButton(
                title = if (connectingFamily == "v4") "正在准备线路…" else "连接",
                icon = Icons.Filled.Bolt,
                loading = connectingFamily == "v4",
                onClick = { onConnect("v4") },
            )
        }
    }
}

// MARK: - 密码输入（对应 iOS `passwordSheet`）

@Composable
private fun PasswordSheet(
    username: String,
    password: String,
    onPasswordChange: (String) -> Unit,
    saving: Boolean,
    onCancel: () -> Unit,
    onConfirm: () -> Unit,
) {
    val palette = LocalPalette.current
    Dialog(
        onDismissRequest = onCancel,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(320.dp)
                    .clip(RoundedCornerShape(topStart = DS.Radius.xxl, topEnd = DS.Radius.xxl))
                    .background(palette.background)
                    .padding(DS.Size.pagePadding),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(text = "输入连接密码", style = DS.Font.section, color = palette.foreground)
                    Spacer(Modifier.weight(1f))
                    Text(
                        text = "取消",
                        style = DS.Font.body,
                        color = palette.primary,
                        modifier = Modifier
                            .clip(RoundedCornerShape(DS.Radius.sm))
                            .clickable(onClick = onCancel)
                            .padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                }

                BannerBar(
                    message = "连接需要账号密码认证，密码仅保存在本机，不会上传。",
                    kind = BannerKind.Info,
                )
                AppTextField(
                    title = "账号",
                    value = username,
                    onValueChange = {},
                    enabled = false,
                )
                AppTextField(
                    title = "登录密码",
                    value = password,
                    onValueChange = onPasswordChange,
                    placeholder = "请输入登录密码",
                    secure = true,
                )
                AppButton(
                    title = "保存并连接",
                    icon = Icons.Filled.Bolt,
                    loading = saving,
                    onClick = onConfirm,
                )
            }
        }
    }
}

// MARK: - 连接状态圆环（对应 iOS `ConnectRing`：极光光环 + 中心计时）

/**
 * 连接状态圆环（对应 iOS `private struct ConnectRing`）。
 * 极光光环：渐变描边 + 光晕呼吸 + 中心计时；固定 224dp，越界绘制被裁剪。
 */
@Composable
private fun ConnectRing(status: VpnStatus, palette: Palette, duration: String, diameter: Dp = 224.dp) {
    val isConnected = status == VpnStatus.Connected
    val isBusy = status == VpnStatus.Connecting || status == VpnStatus.Reasserting ||
        status == VpnStatus.Disconnecting
    val tint = when {
        isConnected -> DS.IconColor.green
        isBusy -> DS.IconColor.teal
        else -> palette.mutedForeground
    }
    val ringWidth = 9.dp
    val label = when (status) {
        VpnStatus.Connected -> "已连接"
        VpnStatus.Connecting -> "连接中…"
        VpnStatus.Reasserting -> "重连中…"
        VpnStatus.Disconnecting -> "断开中…"
        else -> "未连接"
    }

    val transition = rememberInfiniteTransition(label = "connectRing")
    // 渐变主环旋转（连接中快速，已连接缓慢）
    val sweep by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = if (isBusy) 1_600 else 16_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "ringSweep",
    )
    // 高光彗尾巡游
    val comet by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = if (isBusy) 1_300 else 6_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "cometSweep",
    )
    // 光晕呼吸
    val breathe by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 2_600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "breathe",
    )
    val glowOpacity = when {
        isConnected -> 0.5f + 0.4f * breathe
        isBusy -> 0.35f + 0.25f * breathe
        else -> 0.16f
    }

    Box(
        modifier = Modifier
            .size(diameter)
            .clipToBounds(),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val px = diameter.toPx()
            val rw = ringWidth.toPx()
            val gradient = Brush.sweepGradient(
                colors = palette.connectionGradientColors,
                center = Offset(px / 2f, px / 2f),
            )

            // 外层光晕：两层低透明度粗描边模拟柔光（不使用模糊，避免离屏渲染杂色）
            drawGradientRing(px - 44.dp.toPx(), 30.dp.toPx(), gradient, glowOpacity * 0.45f, -90f)
            drawGradientRing(px - 40.dp.toPx(), 18.dp.toPx(), gradient, glowOpacity * 0.6f, -90f)

            // 底环
            drawSolidRing(px - rw, rw, palette.muted)

            // 内部柔和径向底色
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(
                        tint.copy(alpha = if (isConnected) 0.16f else 0.07f),
                        tint.copy(alpha = 0.015f),
                    ),
                    center = Offset(px / 2f, px / 2f),
                    radius = 100.dp.toPx(),
                ),
                radius = (px - 22.dp.toPx()) / 2f,
                center = Offset(px / 2f, px / 2f),
            )

            // 渐变主环（缓慢流转；未连接时淡显）
            val ringAlpha = if (isConnected) 1f else if (isBusy) 0.9f else 0.32f
            drawGradientRing(px - rw, rw, gradient, ringAlpha, sweep - 90f)

            // 高光彗尾：连接中快速巡游，已连接缓慢扫过
            if (isConnected || isBusy) {
                drawComet(px - rw, rw, comet, if (isBusy) 0.9f else 0.45f)
            }
        }

        // 中心：已连接显示计时；连接中显示状态
        if (isConnected) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = duration,
                    style = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.SemiBold).merge(MonospaceDigits),
                    color = palette.foreground,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .shadow(
                                elevation = 3.dp,
                                shape = CircleShape,
                                ambientColor = DS.IconColor.green.copy(alpha = 0.6f),
                                spotColor = DS.IconColor.green.copy(alpha = 0.6f),
                            )
                            .clip(CircleShape)
                            .background(DS.IconColor.green),
                    )
                    Text(
                        text = label,
                        style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium),
                        color = DS.IconColor.green,
                    )
                }
            }
        } else {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = if (isBusy) Icons.Filled.Refresh else Icons.Filled.PowerSettingsNew,
                    contentDescription = null,
                    tint = tint,
                    modifier = Modifier
                        .size(30.dp)
                        .graphicsLayer { rotationZ = if (isBusy) sweep else 0f },
                )
                Text(
                    text = label,
                    style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
                    color = tint,
                )
            }
        }
    }
}

/** 渐变描边整圆（对应 SwiftUI `Circle().stroke(gradient, ...)`） */
private fun DrawScope.drawGradientRing(
    diameter: Float,
    strokeWidth: Float,
    brush: Brush,
    alpha: Float,
    rotation: Float,
) {
    val topLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
    rotate(rotation) {
        drawArc(
            brush = brush,
            startAngle = 0f,
            sweepAngle = 360f,
            useCenter = false,
            topLeft = topLeft,
            size = Size(diameter, diameter),
            alpha = alpha,
            style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
        )
    }
}

/** 纯色描边整圆 */
private fun DrawScope.drawSolidRing(diameter: Float, strokeWidth: Float, color: Color) {
    val topLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
    drawArc(
        color = color,
        startAngle = 0f,
        sweepAngle = 360f,
        useCenter = false,
        topLeft = topLeft,
        size = Size(diameter, diameter),
        style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
    )
}

/** 高光彗尾（对应 SwiftUI `.trim(from: 0, to: 0.14)` + 白色线性渐变） */
private fun DrawScope.drawComet(diameter: Float, strokeWidth: Float, rotation: Float, alpha: Float) {
    val topLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
    rotate(rotation) {
        drawArc(
            brush = Brush.linearGradient(
                colors = listOf(Color.White.copy(alpha = 0f), Color.White.copy(alpha = 0.85f)),
                start = Offset(size.width / 2f, 0f),
                end = Offset(size.width / 2f, size.height),
            ),
            startAngle = 0f,
            sweepAngle = 360f * 0.14f,
            useCenter = false,
            topLeft = topLeft,
            size = Size(diameter, diameter),
            alpha = alpha,
            style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
        )
    }
}

// MARK: - UI 缺失组件补齐（对应 iOS Components.swift 中 HomeView 依赖的部分）

/** 小尺寸标签按钮（分类筛选），对应 iOS `ChipButton`。 */
@Composable
private fun ChipButton(title: String, selected: Boolean, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Box(
        modifier = Modifier
            .height(DS.Size.buttonHeightSmall)
            .clip(RoundedCornerShape(DS.Radius.md))
            .background(if (selected) palette.accentGradient else Brush.linearGradient(listOf(palette.card, palette.card)))
            .then(if (selected) Modifier else Modifier.border(1.dp, palette.border, RoundedCornerShape(DS.Radius.md)))
            .pressableScale()
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = title,
            style = TextStyle(fontSize = 13.sp, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal),
            color = if (selected) Color.White else palette.foreground,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** 竖线分隔符（全局替代 "·" 点分割），对应 iOS `VLine`。 */
@Composable
private fun VLine(height: Dp = 10.dp, color: Color? = null) {
    val palette = LocalPalette.current
    Box(
        modifier = Modifier
            .width(1.dp)
            .height(height)
            .background(color ?: palette.mutedForeground.copy(alpha = 0.38f)),
    )
}

/** 服务器状态徽章，对应 iOS `NodeStatusBadge`。 */
@Composable
private fun NodeStatusBadge(status: String) {
    val palette = LocalPalette.current
    val (text, bg, fg) = when (status) {
        "online" -> Triple("在线", palette.onlineBg, palette.onlineText)
        "disabled" -> Triple("已停用", palette.pendingBg, palette.pendingText)
        // 离线 / 未对接（pending）统一显示为「离线」，不暴露安装状态
        else -> Triple("离线", palette.offlineBg, palette.offlineText)
    }
    StatusBadge(text = text, background = bg, foreground = fg)
}

/** 细进度条，对应 iOS `StatBar`（Web 端 MiniStat）。 */
@Composable
private fun StatBar(label: String, value: Double, icon: ImageVector? = null) {
    val palette = LocalPalette.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier.width(56.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            if (icon != null) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = palette.mutedForeground,
                    modifier = Modifier.size(11.dp),
                )
            }
            Text(text = label, style = DS.Font.caption, color = palette.mutedForeground)
        }
        Box(
            modifier = Modifier
                .weight(1f)
                .height(6.dp)
                .clip(CircleShape)
                .background(palette.muted),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth((value / 100.0).coerceIn(0.0, 1.0).toFloat())
                    .clip(CircleShape)
                    .background(palette.accentGradient),
            )
        }
        Text(
            text = String.format(Locale.US, "%.0f%%", value),
            style = DS.Font.caption.merge(MonospaceDigits),
            color = palette.mutedForeground,
            modifier = Modifier.width(36.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.End,
        )
    }
}

/** 仅调整不透明度的辅助（对应 iOS `.opacity(...)`），避免额外导入 `alpha`。 */
private fun Modifier.graphicsLayerAlpha(value: Float): Modifier =
    this.then(Modifier.graphicsLayer { alpha = value })