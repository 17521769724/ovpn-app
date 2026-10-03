package com.ovpn.panel.features

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Feedback
import androidx.compose.material.icons.filled.MonetizationOn
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SettingsInputAntenna
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.ovpn.panel.core.ApiService
import com.ovpn.panel.core.AppState
import com.ovpn.panel.core.AppUser
import com.ovpn.panel.core.DS
import com.ovpn.panel.core.Format
import com.ovpn.panel.core.LocalPalette
import com.ovpn.panel.core.Palette
import com.ovpn.panel.core.TrafficDay
import com.ovpn.panel.core.TrafficPayload
import com.ovpn.panel.core.UserCenterPayload
import com.ovpn.panel.core.VpnManager
import com.ovpn.panel.ui.AppButton
import com.ovpn.panel.ui.AppCard
import com.ovpn.panel.ui.BannerBar
import com.ovpn.panel.ui.ButtonStyleKind
import com.ovpn.panel.ui.IconTile
import com.ovpn.panel.ui.InfoRow
import com.ovpn.panel.ui.MenuRow
import com.ovpn.panel.ui.ScreenScaffold
import com.ovpn.panel.ui.SectionHeader
import com.ovpn.panel.ui.SegmentedTabs
import com.ovpn.panel.ui.StatusBadge
import kotlinx.coroutines.launch

/**
 * 个人中心（对应 iOS `ProfileView`）。
 *
 * [onOpen] 用于功能入口菜单跳转子页面，路由字符串与 iOS 的 NavigationLink 目标一一对应：
 * "announcements" → AnnouncementsView、"activation" → ActivationView、"recharge" → RechargeView、
 * "coins" → CoinsView、"feedback" → FeedbackView、"orders" → OrdersView、
 * "account" → AccountSettingsView。
 */
@Composable
fun ProfileView(onOpen: (String) -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()

    // 对应 iOS @ObservedObject private var vpn = VPNManager.shared
    val vpnStatus by VpnManager.status.collectAsState()
    val vpnConnected = remember(vpnStatus) { VpnManager.isConnected }

    // 对应 iOS @EnvironmentObject private var app: AppState
    val user by AppState.user.collectAsState()
    val masterUrl by AppState.masterUrl.collectAsState()

    var center by remember { mutableStateOf<UserCenterPayload?>(null) }
    var traffic by remember { mutableStateOf<TrafficPayload?>(null) }
    var loading by remember { mutableStateOf(true) }
    var showLogout by remember { mutableStateOf(false) }
    var unreadCount by remember { mutableStateOf(0) }
    var trafficDays by remember { mutableStateOf(15) }
    var closingSessions by remember { mutableStateOf(false) }

    // 下拉刷新替代方案（Android 端未使用 pullRefresh）：
    // 通过 refreshTick 重新触发 LaunchedEffect 完成刷新；
    // 另在 ON_RESUME（返回该 Tab）时自增 refreshTick 再次刷新。
    var refreshTick by remember { mutableStateOf(0) }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refreshTick++
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // 对应 iOS `private func loadTraffic() async`
    // 按当前选择（近 7 / 15 天）拉取流量统计；失败或被取消时保留上一次数据，
    // 避免下拉刷新后图表短暂消失。
    suspend fun loadTraffic() {
        val days = trafficDays
        val value = try {
            ApiService.fetchTraffic(days)
        } catch (e: Exception) {
            return
        }
        if (days != trafficDays) return
        traffic = value
    }

    // 对应 iOS `private func load() async`
    suspend fun load() {
        loading = true
        try {
            val value = ApiService.fetchUserCenter()
            center = value
            AppState.user.value = value.user
        } catch (e: Exception) {
            // 对应 iOS `if APIError.from(error).isCancelled { return }`
            if (AppState.isCancelled(e)) return
            AppState.report(e)
        }
        loadTraffic()
        // 对应 iOS `if let announcements = try? await ...`
        try {
            val announcements = ApiService.fetchAnnouncements()
            unreadCount = announcements.unreadCount
        } catch (e: Exception) {
            // try?：失败时静默保留原值
        }
        loading = false
    }

    // 首次进入 / 刷新：对应 iOS `.task { await load() }` 与 `.refreshable { await load() }`
    LaunchedEffect(refreshTick) { load() }

    // 对应 iOS `.onChange(of: trafficDays) { Task { await loadTraffic() } }`（跳过首次，避免重复请求）
    var firstTrafficRun by remember { mutableStateOf(true) }
    LaunchedEffect(trafficDays) {
        if (firstTrafficRun) {
            firstTrafficRun = false
            return@LaunchedEffect
        }
        loadTraffic()
    }

    // 对应 iOS `private func closeAllSessions() async`
    fun closeAllSessions() {
        if (closingSessions) return
        closingSessions = true
        scope.launch {
            try {
                try {
                    ApiService.closeSessions()
                    AppState.showToast("已断开全部在线会话")
                } catch (e: Exception) {
                    AppState.report(e)
                }
                load()
            } finally {
                closingSessions = false
            }
        }
    }

    ScreenScaffold(title = "个人中心") {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Size.pagePadding)
                .padding(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            UserCard(palette = palette, user = user, center = center)

            AssetsStrip(palette = palette, user = user)
            TrafficCard(
                palette = palette,
                center = center,
                traffic = traffic,
                trafficDays = trafficDays,
                onSelectDays = { trafficDays = if (it == 0) 7 else 15 },
            )
            SessionCard(
                palette = palette,
                center = center,
                vpnConnected = vpnConnected,
                closingSessions = closingSessions,
                onCloseAll = { closeAllSessions() },
            )
            MenuCard(palette = palette, unreadCount = unreadCount, onOpen = onOpen)

            AppButton(
                title = "退出登录",
                icon = Icons.AutoMirrored.Filled.Logout,
                style = ButtonStyleKind.Destructive,
                modifier = Modifier.padding(top = 4.dp),
                onClick = { showLogout = true },
            )

            // 底部版本信息（对应 iOS `客户端 v{AppInfo.version} (Build {AppInfo.build})`）
            Row(
                modifier = Modifier.padding(top = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = "客户端 v${AppInfo.version} (Build ${AppInfo.build})",
                    style = DS.Font.caption,
                    color = palette.mutedForeground,
                )
                VLine(height = 10.dp)
                Text(
                    text = masterUrl,
                    style = DS.Font.caption,
                    color = palette.mutedForeground,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    // 对应 iOS `.alert("退出登录？", isPresented: $showLogout)`
    if (showLogout) {
        AlertDialog(
            onDismissRequest = { showLogout = false },
            title = { Text(text = "退出登录？", style = DS.Font.section, color = palette.foreground) },
            confirmButton = {
                TextButton(onClick = {
                    showLogout = false
                    AppState.logout()
                }) {
                    Text(text = "退出", color = palette.destructive, style = DS.Font.body)
                }
            },
            dismissButton = {
                TextButton(onClick = { showLogout = false }) {
                    Text(text = "取消", color = palette.mutedForeground, style = DS.Font.body)
                }
            },
            containerColor = palette.card,
        )
    }
}

// MARK: - 账户资产（等级 / 金币 / 余额）

/**
 * 三格资产条：与下方「流量使用」保持同一卡片底色，仅用彩色图标区分。
 * 对应 iOS `assetsStrip`。
 */
@Composable
private fun AssetsStrip(palette: Palette, user: AppUser?) {
    AppCard(padding = 0.dp) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AssetCell(
                icon = Icons.Filled.Star,
                color = DS.IconColor.teal,
                title = "等级",
                value = "Lv.${user?.levelValue ?: 1}",
                modifier = Modifier.weight(1f),
            )
            AssetDivider(palette)
            AssetCell(
                icon = Icons.Filled.MonetizationOn,
                color = DS.IconColor.amber,
                title = "金币",
                value = "${user?.coinsValue ?: 0}",
                modifier = Modifier.weight(1f),
            )
            AssetDivider(palette)
            AssetCell(
                icon = Icons.Filled.CreditCard,
                color = DS.IconColor.green,
                title = "余额",
                value = String.format(java.util.Locale.US, "%.2f", user?.balanceYuanValue ?: 0.0),
                modifier = Modifier.weight(1f),
            )
        }
    }
}

/** 对应 iOS `assetCell` */
@Composable
private fun AssetCell(
    icon: ImageVector,
    color: Color,
    title: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    val palette = LocalPalette.current
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(18.dp),
        )
        Text(
            text = value,
            style = TextStyle(
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                fontFeatureSettings = "tnum",
            ),
            color = palette.foreground,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(text = title, style = DS.Font.caption, color = palette.mutedForeground)
    }
}

/** 对应 iOS `assetDivider` */
@Composable
private fun AssetDivider(palette: Palette) {
    Box(
        modifier = Modifier
            .width(1.dp)
            .height(34.dp)
            .background(palette.border),
    )
}

// MARK: - 用户卡片（渐变底：主题色示意，作为页面视觉焦点）

/** 对应 iOS `userCard`：渐变底 + 状态徽章 + 4 行 InfoRow（未就绪时以占位符保持行数） */
@Composable
private fun UserCard(palette: Palette, user: AppUser?, center: UserCenterPayload?) {
    val shape = RoundedCornerShape(DS.Radius.xl)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(palette.card)
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        palette.primary.copy(alpha = if (palette.dark) 0.24f else 0.14f),
                        DS.Brand.teal.copy(alpha = if (palette.dark) 0.10f else 0.06f),
                        Color.Transparent,
                    ),
                ),
            )
            .border(1.dp, palette.primary.copy(alpha = 0.20f), shape)
            .padding(DS.Size.cardPadding),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.linearGradient(listOf(DS.IconColor.green, DS.IconColor.teal)),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = (user?.username?.take(1) ?: "U").uppercase(),
                    style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold),
                    color = Color.White,
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(text = user?.username ?: "-", style = DS.Font.section, color = palette.foreground)
                Text(
                    text = user?.email ?: "未绑定邮箱",
                    style = DS.Font.caption,
                    color = palette.secondaryText,
                )
            }
            Spacer(Modifier.weight(1f))
            // 数据未就绪时先占位，避免加载完成后整块插入导致布局跳动
            if (center != null) {
                StatusBadge(
                    text = if (center.quota.valid) "正常" else "受限",
                    background = if (center.quota.valid) palette.onlineBg else palette.offlineBg,
                    foreground = if (center.quota.valid) palette.onlineText else palette.offlineText,
                )
            } else {
                StatusBadge(text = "同步中", background = palette.muted, foreground = palette.mutedForeground)
            }
        }

        if (center != null && !center.quota.valid) {
            BannerBar(message = center.quota.reason)
        }

        // 固定行数：数据未就绪时以占位符展示，加载完成后仅数值变化、不发生布局跳动
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            InfoRow(label = "当前套餐", value = center?.plan?.name ?: "—")
            InfoRow(
                label = "到期时间",
                value = if (center == null) "—" else Format.dateOnly(user?.planExpiresAt),
            )
            InfoRow(
                label = "限速",
                value = if (center == null) "—" else Format.speed(user?.speedLimitKbps ?: 0),
            )
            val deviceLimit = user?.deviceLimit ?: 0
            InfoRow(
                label = "设备上限",
                value = if (center == null) "—" else if (deviceLimit > 0) "$deviceLimit 台" else "不限",
            )
        }
    }
}

// MARK: - 流量（纯绿色统计，与 Web 端一致）

/** 对应 iOS `trafficCard` */
@Composable
private fun TrafficCard(
    palette: Palette,
    center: UserCenterPayload?,
    traffic: TrafficPayload?,
    trafficDays: Int,
    onSelectDays: (Int) -> Unit,
) {
    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                IconTile(icon = Icons.Filled.BarChart, color = DS.Traffic.barStrong)
                SectionHeader(title = "流量使用")
                Spacer(Modifier.weight(1f))
                SegmentedTabs(
                    items = listOf("近7天", "近15天"),
                    selection = if (trafficDays == 7) 0 else 1,
                    onSelect = onSelectDays,
                )
            }

            // 用量区：未就绪时以占位展示，保证首屏与加载完成后布局一致（无跳动）
            val used = center?.traffic?.usedBytes ?: 0
            val limit = center?.traffic?.limitBytes ?: 0
            val percent = center?.traffic?.percent ?: 0.0
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Bottom,
            ) {
                Text(
                    text = if (center == null) "—" else Format.bytes(used),
                    style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold),
                    color = DS.Traffic.barStrong,
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    text = if (limit > 0) "/ ${Format.bytes(limit)}" else "/ 不限量",
                    style = DS.Font.bodySmall,
                    color = palette.secondaryText,
                )
                Spacer(Modifier.weight(1f))
                if (limit > 0) {
                    Text(
                        text = String.format(java.util.Locale.US, "%.1f%%", percent),
                        style = DS.Font.number,
                        color = DS.Traffic.barStrong,
                    )
                }
            }

            TrafficProgressBar(percent = percent, palette = palette)

            // 图表：固定高度占位，数据到达后仅柱形变化（无跳动）
            val days = traffic?.days
            if (days != null && days.isNotEmpty()) {
                TrafficBars(days = days, palette = palette)
            } else {
                TrafficBarsPlaceholder(palette = palette)
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = traffic?.let { "合计 ${Format.bytes(it.totalBytes)}" } ?: "合计 —",
                    style = DS.Font.caption,
                    color = palette.secondaryText,
                )
                Spacer(Modifier.weight(1f))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Legend(color = DS.Traffic.bar, title = "上传")
                    Legend(color = DS.Traffic.barSoft, title = "下载")
                }
            }
        }
    }
}

/** 流量进度条（对应 iOS trafficCard 中的 GeometryReader 胶囊进度） */
@Composable
private fun TrafficProgressBar(percent: Double, palette: Palette) {
    val fraction = (percent / 100.0).coerceIn(0.0, 1.0).toFloat()
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(8.dp)
            .clip(CircleShape)
            .background(palette.trafficTracker),
    ) {
        if (fraction > 0f) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(fraction)
                    .clip(CircleShape)
                    .background(Brush.linearGradient(listOf(DS.Traffic.bar, DS.Traffic.barStrong))),
            )
        }
    }
}

/** 对应 iOS `legend` */
@Composable
private fun Legend(color: Color, title: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(
            modifier = Modifier
                .size(10.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(color),
        )
        Text(text = title, style = DS.Font.caption, color = DS.IconColor.slate)
    }
}

/**
 * 流量柱状图占位（对应 iOS `TrafficBarsPlaceholder`）：
 * 保持与真实图表相同的高度与排布，避免加载完成后页面跳动。
 */
@Composable
private fun TrafficBarsPlaceholder(palette: Palette) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(90.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        repeat(15) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Bottom,
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(palette.trafficTracker.copy(alpha = 0.7f)),
                )
                Spacer(Modifier.height(3.dp))
                Text(
                    text = "--",
                    style = TextStyle(fontSize = 9.sp),
                    color = palette.mutedForeground.copy(alpha = 0.5f),
                )
            }
        }
    }
}

/**
 * 15 天流量柱状图（对应 iOS `TrafficBars`，纯绿色，与 Web 端配色对齐）。
 * 每根柱子按当日总量占比决定高度，柱内再按 rx 占比拆分「上传（bar）/ 下载（barSoft）」两段。
 */
@Composable
private fun TrafficBars(days: List<TrafficDay>, palette: Palette) {
    val maxValue = maxOf(days.maxOfOrNull { it.totalBytes } ?: 1L, 1L).toFloat()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(90.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        days.forEach { day ->
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Bottom,
            ) {
                BoxWithConstraints(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                ) {
                    val total = day.totalBytes.toFloat() / maxValue
                    val rxRatio = if (day.totalBytes > 0) {
                        day.rxBytes.toFloat() / maxOf(day.totalBytes, 1L).toFloat()
                    } else {
                        0.5f
                    }
                    val full = maxHeight
                    val rawHeight = full * total
                    val height = if (rawHeight > 2.dp) rawHeight else 2.dp
                    val upRaw = height * (1 - rxRatio)
                    val downRaw = height * rxRatio
                    Column(
                        modifier = Modifier.align(Alignment.BottomCenter),
                        verticalArrangement = Arrangement.spacedBy(1.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(if (upRaw > 1.dp) upRaw else 1.dp)
                                .clip(RoundedCornerShape(2.dp))
                                .background(DS.Traffic.bar),
                        )
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(if (downRaw > 1.dp) downRaw else 1.dp)
                                .clip(RoundedCornerShape(2.dp))
                                .background(DS.Traffic.barSoft),
                        )
                    }
                }
                Spacer(Modifier.height(3.dp))
                Text(
                    text = day.day.takeLast(2),
                    style = TextStyle(fontSize = 9.sp),
                    color = palette.mutedForeground,
                )
            }
        }
    }
}

// MARK: - 在线会话

/** 对应 iOS `sessionCard` */
@Composable
private fun SessionCard(
    palette: Palette,
    center: UserCenterPayload?,
    vpnConnected: Boolean,
    closingSessions: Boolean,
    onCloseAll: () -> Unit,
) {
    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                IconTile(icon = Icons.Filled.SettingsInputAntenna, color = DS.IconColor.cyan)
                SectionHeader(title = "在线会话", subtitle = "当前账号的连接")
            }

            val sessions = center?.onlineSessions ?: emptyList()
            if (sessions.isEmpty()) {
                Text(
                    text = "当前没有在线连接",
                    style = DS.Font.bodySmall,
                    color = palette.secondaryText,
                    modifier = Modifier.padding(vertical = 6.dp),
                )
            } else {
                sessions.forEachIndexed { index, session ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = session.nodeName ?: "节点",
                                style = DS.Font.bodySmall,
                                color = palette.foreground,
                            )
                            Spacer(Modifier.weight(1f))
                            Text(
                                text = Format.dateTime(session.connectedAt),
                                style = DS.Font.caption,
                                color = palette.mutedForeground,
                            )
                        }
                        InfoRow(
                            label = "虚拟 IP",
                            value = if (session.virtualIp.isEmpty()) "-" else session.virtualIp,
                        )
                        InfoRow(
                            label = "流量",
                            value = "↑ ${Format.bytes(session.rxBytes)} / ↓ ${Format.bytes(session.txBytes)}",
                        )
                    }
                    if (index != sessions.lastIndex) {
                        Divider(palette)
                    }
                }

                // 本机未连接时，这些会话多半是系统「设置」中断开留下的残留记录，
                // 提供手动兜底清理（主控会同时通知节点释放服务端连接）
                if (!vpnConnected) {
                    Divider(palette)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "断开其它设备 / 清理残留会话",
                            style = DS.Font.caption,
                            color = palette.mutedForeground,
                        )
                        Spacer(Modifier.weight(1f))
                        AppButton(
                            title = "全部断开",
                            icon = Icons.Filled.Cancel,
                            style = ButtonStyleKind.Secondary,
                            height = DS.Size.buttonHeightSmall,
                            loading = closingSessions,
                            disabled = closingSessions,
                            modifier = Modifier.width(108.dp),
                            onClick = onCloseAll,
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 功能入口（彩色图标 + 整行可点）

/** 对应 iOS `menuCard`：公告带未读徽章，其余为纯入口 */
@Composable
private fun MenuCard(palette: Palette, unreadCount: Int, onOpen: (String) -> Unit) {
    AppCard(padding = 0.dp) {
        MenuRow(
            icon = Icons.Filled.Campaign,
            iconColor = DS.IconColor.rose,
            title = "公告",
            badge = if (unreadCount > 0) "$unreadCount" else null,
            onClick = { onOpen("announcements") },
        )
        MenuDivider(palette)
        MenuRow(
            icon = Icons.Filled.ConfirmationNumber,
            iconColor = DS.IconColor.amber,
            title = "激活码",
            onClick = { onOpen("activation") },
        )
        MenuDivider(palette)
        MenuRow(
            icon = Icons.Filled.AccountBalanceWallet,
            iconColor = DS.IconColor.green,
            title = "余额充值",
            subtitle = "充值后可在购买套餐时全额抵扣",
            onClick = { onOpen("recharge") },
        )
        MenuDivider(palette)
        MenuRow(
            icon = Icons.Filled.MonetizationOn,
            iconColor = DS.IconColor.orange,
            title = "金币记录",
            onClick = { onOpen("coins") },
        )
        MenuDivider(palette)
        MenuRow(
            icon = Icons.Filled.Feedback,
            iconColor = DS.IconColor.cyan,
            title = "问题反馈",
            onClick = { onOpen("feedback") },
        )
        MenuDivider(palette)
        MenuRow(
            icon = Icons.Filled.Description,
            iconColor = DS.IconColor.cyan,
            title = "我的订单",
            onClick = { onOpen("orders") },
        )
        MenuDivider(palette)
        MenuRow(
            icon = Icons.Filled.Settings,
            iconColor = DS.IconColor.slate,
            title = "账号设置",
            onClick = { onOpen("account") },
        )
    }
}

/** 整行分割线（对应 iOS menuCard 中的 divider，左侧留出 58dp 与图标对齐） */
@Composable
private fun MenuDivider(palette: Palette) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 58.dp)
            .height(1.dp)
            .background(palette.border),
    )
}

/** 会话列表分割线（对应 iOS `Divider().overlay(palette.border)`） */
@Composable
private fun Divider(palette: Palette) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(palette.border),
    )
}

/** 竖向细线（对应 iOS `VLine`，默认 mutedForeground 38% 透明度） */
@Composable
private fun VLine(height: Dp = 10.dp) {
    val palette = LocalPalette.current
    Box(
        modifier = Modifier
            .width(1.dp)
            .height(height)
            .background(palette.mutedForeground.copy(alpha = 0.38f)),
    )
}

/**
 * 版本信息（对应 iOS `enum AppInfo`）。
 * iOS 读取 Info.plist 的 CFBundleShortVersionString / CFBundleVersion；
 * Android 端取 build.gradle.kts 中的 versionName / versionCode，改动需同步。
 */
private object AppInfo {
    const val version = "1.2.6"
    const val build = "10"
}