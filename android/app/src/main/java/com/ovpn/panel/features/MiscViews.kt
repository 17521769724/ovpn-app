package com.ovpn.panel.features

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowCircleDown
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.CurrencyBitcoin
import androidx.compose.material.icons.filled.HowToReg
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Numbers
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.ReceiptLong
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ovpn.panel.core.AnnouncementsPayload
import com.ovpn.panel.core.ApiService
import com.ovpn.panel.core.AppState
import com.ovpn.panel.core.ActivationRecord
import com.ovpn.panel.core.ActivationRedeemResult
import com.ovpn.panel.core.BannerKind
import com.ovpn.panel.core.CoinLog
import com.ovpn.panel.core.CoinsPayload
import com.ovpn.panel.core.DS
import com.ovpn.panel.core.FeedbackItem
import com.ovpn.panel.core.Format
import com.ovpn.panel.core.LocalPalette
import com.ovpn.panel.core.Palette
import com.ovpn.panel.ui.AppButton
import com.ovpn.panel.ui.AppCard
import com.ovpn.panel.ui.AppTextField
import com.ovpn.panel.ui.BannerBar
import com.ovpn.panel.ui.ButtonStyleKind
import com.ovpn.panel.ui.EmptyHint
import com.ovpn.panel.ui.IconTile
import com.ovpn.panel.ui.InfoRow
import com.ovpn.panel.ui.LoadingBlock
import com.ovpn.panel.ui.ReadOnlyField
import com.ovpn.panel.ui.ScreenScaffold
import com.ovpn.panel.ui.SectionHeader
import com.ovpn.panel.ui.StatusBadge
import com.ovpn.panel.ui.pressableScale
import kotlinx.coroutines.launch

/**
 * 公告 / 激活码 / 金币记录 / 问题反馈 / 邀请 / 账号设置。
 * 与 iOS `Sources/OVPNPanel/Features/MiscViews.swift` 一一对应（文案 / 顺序 / 间距 / 颜色一致）。
 */

// MARK: - 公告（AnnouncementsView）

/** 公告列表：未读横幅 + 列表 + 点击已读回写。对应 iOS `AnnouncementsView`。 */
@Composable
fun AnnouncementsView(onBack: () -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()

    var payload by remember { mutableStateOf<AnnouncementsPayload?>(null) }
    var loading by remember { mutableStateOf(true) }
    var expanded by remember { mutableStateOf(setOf<Int>()) }

    suspend fun load() {
        loading = true
        try {
            payload = ApiService.fetchAnnouncements()
        } catch (e: Exception) {
            if (AppState.isCancelled(e)) return
            AppState.report(e)
        } finally {
            loading = false
        }
    }

    /** 点击已读：仅在未读列表包含该 id 时回写，随后重新拉取 */
    fun markRead(id: Int) {
        val unreadIds = payload?.unreadIds ?: return
        if (!unreadIds.contains(id)) return
        scope.launch {
            try {
                ApiService.markAnnouncementsRead(listOf(id))
            } catch (_: Exception) {
                // 对应 iOS `try?`：忽略失败
            }
            load()
        }
    }

    LaunchedEffect(Unit) { load() }

    ScreenScaffold(title = "公告", onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(DS.Size.pagePadding),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gap),
        ) {
            val items = payload?.announcements ?: emptyList()
            when {
                loading && payload == null -> LoadingBlock(text = "正在获取公告…")
                items.isEmpty() -> EmptyHint(icon = Icons.Filled.Campaign, title = "暂无公告")
                else -> {
                    val unread = payload?.unreadCount ?: 0
                    if (unread > 0) {
                        BannerBar(message = "有 $unread 条未读公告", kind = BannerKind.Warning)
                    }
                    items.forEach { item ->
                        val isExpanded = expanded.contains(item.id)
                        AppCard(
                            modifier = Modifier
                                .pressableScale()
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) { markRead(item.id) },
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    if (item.isTop) {
                                        StatusBadge(
                                            text = "置顶",
                                            background = palette.muted,
                                            foreground = palette.foreground,
                                        )
                                        Spacer(Modifier.width(6.dp))
                                    }
                                    Text(
                                        text = item.title,
                                        style = DS.Font.section,
                                        color = palette.foreground,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Spacer(Modifier.weight(1f))
                                    if (!item.read) {
                                        Box(
                                            modifier = Modifier
                                                .size(7.dp)
                                                .clip(CircleShape)
                                                .background(palette.destructive),
                                        )
                                    }
                                }
                                Text(
                                    text = item.content,
                                    style = DS.Font.bodySmall,
                                    color = palette.mutedForeground,
                                    maxLines = if (isExpanded) Int.MAX_VALUE else 3,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        text = Format.dateTime(item.createdAt),
                                        style = DS.Font.caption,
                                        color = palette.mutedForeground,
                                    )
                                    Spacer(Modifier.weight(1f))
                                    Text(
                                        text = if (isExpanded) "收起" else "展开",
                                        style = DS.Font.caption,
                                        color = palette.foreground,
                                        modifier = Modifier.clickable(
                                            interactionSource = remember { MutableInteractionSource() },
                                            indication = null,
                                        ) {
                                            expanded = if (isExpanded) expanded - item.id else expanded + item.id
                                        },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 激活码（ActivationView）

/** 激活码兑换：兑换表单 + 兑换结果 + 兑换记录。对应 iOS `ActivationView`。 */
@Composable
fun ActivationView(onBack: () -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()

    var code by remember { mutableStateOf("") }
    var records by remember { mutableStateOf<List<ActivationRecord>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var submitting by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<ActivationRedeemResult?>(null) }

    suspend fun load() {
        loading = true
        records = try {
            ApiService.fetchActivationRecords()
        } catch (e: Exception) {
            emptyList()
        }
        loading = false
    }

    suspend fun redeem() {
        val value = code.trim()
        if (value.isEmpty()) {
            AppState.showToast("请输入激活码", BannerKind.Warning)
            return
        }
        submitting = true
        result = null
        try {
            val preview = ApiService.previewActivation(value)
            if (!preview.valid) {
                AppState.showToast(preview.message, BannerKind.Error)
                return
            }
            val redeemResult = ApiService.redeemActivation(value)
            result = redeemResult
            AppState.showToast("兑换成功：${redeemResult.planName}", BannerKind.Success)
            code = ""
            load()
            AppState.refreshUser()
        } catch (e: Exception) {
            AppState.report(e)
        } finally {
            submitting = false
        }
    }

    LaunchedEffect(Unit) { load() }

    ScreenScaffold(title = "激活码", onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(DS.Size.pagePadding),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            AppCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconTile(icon = Icons.Filled.ConfirmationNumber, color = DS.IconColor.amber)
                        SectionHeader(title = "兑换激活码", subtitle = "输入管理员发放的激活码")
                    }
                    AppTextField(
                        title = "激活码",
                        value = code,
                        onValueChange = { code = it },
                        placeholder = "OVPN-XXXX-XXXX-XXXX",
                    )
                    AppButton(
                        title = "立即兑换",
                        icon = Icons.Filled.ConfirmationNumber,
                        loading = submitting,
                        onClick = { scope.launch { redeem() } },
                    )
                }
            }

            val current = result
            if (current != null) {
                AppCard {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SectionHeader(title = if (current.extend) "已叠加到当前套餐" else "兑换成功")
                        InfoRow(label = "套餐", value = current.planName)
                        InfoRow(label = "时长", value = "${current.durationDays} 天")
                        InfoRow(label = "流量", value = Format.traffic(current.trafficBytes))
                        InfoRow(label = "到期时间", value = Format.dateOnly(current.expiresAt))
                    }
                }
            }

            AppCard {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SectionHeader(title = "兑换记录")
                    if (records.isEmpty()) {
                        Text(
                            text = "暂无兑换记录",
                            style = DS.Font.bodySmall,
                            color = palette.mutedForeground,
                        )
                    } else {
                        records.forEach { record ->
                            Column(
                                modifier = Modifier.padding(vertical = 5.dp),
                                verticalArrangement = Arrangement.spacedBy(5.dp),
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        text = record.code,
                                        style = TextStyle(fontSize = 12.sp, fontFamily = FontFamily.Monospace),
                                        color = palette.foreground,
                                    )
                                    Spacer(Modifier.weight(1f))
                                    Text(
                                        text = Format.dateTime(record.usedAt),
                                        style = DS.Font.caption,
                                        color = palette.mutedForeground,
                                    )
                                }
                                InfoRow(label = "套餐", value = record.planName)
                                InfoRow(label = "时长", value = "${record.durationDays} 天")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 金币记录（CoinsView）

/** 金币记录：只展示金币余额与流水（邀请相关已独立为「邀请」Tab）。对应 iOS `CoinsView`。 */
@Composable
fun CoinsView(onBack: () -> Unit) {
    val scope = rememberCoroutineScope()

    var payload by remember { mutableStateOf<CoinsPayload?>(null) }
    var loading by remember { mutableStateOf(true) }

    suspend fun load() {
        loading = true
        try {
            payload = ApiService.fetchCoins()
        } catch (e: Exception) {
            if (AppState.isCancelled(e)) return
            AppState.report(e)
        } finally {
            loading = false
        }
    }

    LaunchedEffect(Unit) { load() }

    ScreenScaffold(title = "金币记录", onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Size.pagePadding)
                .padding(top = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            CoinsBalanceCard(payload)
            CoinsLogsCard(payload = payload, loading = loading)
        }
    }
}

/** 金币余额卡片。对应 iOS `CoinsView.balanceCard`。 */
@Composable
private fun CoinsBalanceCard(payload: CoinsPayload?) {
    val palette = LocalPalette.current
    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(text = "我的金币", style = DS.Font.caption, color = palette.mutedForeground)
                    Text(
                        text = "${payload?.coins ?: 0}",
                        style = TextStyle(
                            fontSize = 28.sp,
                            fontWeight = FontWeight.SemiBold,
                            fontFeatureSettings = "tnum",
                        ),
                        color = DS.IconColor.orange,
                    )
                }
                Spacer(Modifier.weight(1f))
                Icon(
                    imageVector = Icons.Filled.CurrencyBitcoin,
                    contentDescription = null,
                    tint = DS.IconColor.orange,
                    modifier = Modifier.size(32.dp),
                )
            }
            if (payload?.coinExchangeEnabled == true) {
                BannerBar(message = "金币可在「套餐中心」兑换支持的套餐", kind = BannerKind.Info)
            }
        }
    }
}

/** 金币流水卡片。对应 iOS `CoinsView.logsCard`。 */
@Composable
private fun CoinsLogsCard(payload: CoinsPayload?, loading: Boolean) {
    val palette = LocalPalette.current
    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconTile(icon = Icons.Filled.ReceiptLong, color = DS.IconColor.teal)
                SectionHeader(title = "金币流水")
            }
            val logs = payload?.logs ?: emptyList()
            when {
                loading && payload == null -> LoadingBlock(text = "加载中…")
                logs.isEmpty() -> Text(
                    text = "暂无流水记录",
                    style = DS.Font.bodySmall,
                    color = palette.mutedForeground,
                    modifier = Modifier.padding(vertical = 4.dp),
                )
                else -> logs.forEachIndexed { index, log ->
                    if (index > 0) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(1.dp)
                                .background(palette.border),
                        )
                    }
                    CoinLogRow(log)
                }
            }
        }
    }
}

/** 单条金币流水。对应 iOS `CoinsView.logRow`。 */
@Composable
private fun CoinLogRow(log: CoinLog) {
    val palette = LocalPalette.current
    val positive = log.amount >= 0
    Row(
        modifier = Modifier.padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = if (positive) Icons.Filled.ArrowCircleDown else Icons.Filled.ArrowCircleUp,
            contentDescription = null,
            tint = if (positive) palette.onlineText else DS.IconColor.orange,
            modifier = Modifier.size(15.dp),
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = if (log.reason.isEmpty()) "金币变动" else log.reason,
                style = DS.Font.bodySmall,
                color = palette.foreground,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = Format.dateTime(log.createdAt),
                style = DS.Font.caption,
                color = palette.mutedForeground,
            )
        }
        Column(
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = if (positive) "+${log.amount}" else "${log.amount}",
                style = DS.Font.number,
                color = if (positive) palette.onlineText else palette.offlineText,
            )
            Text(
                text = "余额 ${log.balance}",
                style = DS.Font.caption,
                color = palette.mutedForeground,
            )
        }
    }
}

// MARK: - 问题反馈（FeedbackView）

/** 问题反馈：提交表单 + 我的反馈列表。对应 iOS `FeedbackView`。 */
@Composable
fun FeedbackView(onBack: () -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()

    var title by remember { mutableStateOf("") }
    var content by remember { mutableStateOf("") }
    var contact by remember { mutableStateOf("") }
    var items by remember { mutableStateOf<List<FeedbackItem>>(emptyList()) }
    var submitting by remember { mutableStateOf(false) }

    suspend fun load() {
        items = try {
            ApiService.fetchFeedback()
        } catch (e: Exception) {
            emptyList()
        }
    }

    suspend fun submit() {
        if (content.trim().length < 5) {
            AppState.showToast("请填写反馈内容（至少 5 个字）", BannerKind.Warning)
            return
        }
        submitting = true
        try {
            ApiService.submitFeedback(lineId = null, title = title, content = content, contact = contact)
            AppState.showToast("提交成功，管理员会尽快处理", BannerKind.Success)
            title = ""
            content = ""
            contact = ""
            load()
        } catch (e: Exception) {
            AppState.report(e)
        } finally {
            submitting = false
        }
    }

    LaunchedEffect(Unit) { load() }

    ScreenScaffold(title = "问题反馈", onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(DS.Size.pagePadding),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            AppCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconTile(icon = Icons.Filled.Send, color = DS.IconColor.cyan)
                        SectionHeader(title = "提交反馈", subtitle = "线路问题、建议都可以告诉我们")
                    }
                    AppTextField(
                        title = "标题",
                        value = title,
                        onValueChange = { title = it },
                        placeholder = "简要描述（选填）",
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(text = "内容", style = DS.Font.bodySmall, color = palette.mutedForeground)
                        val shape = RoundedCornerShape(DS.Radius.lg)
                        BasicTextField(
                            value = content,
                            onValueChange = { content = it },
                            textStyle = DS.Font.body.copy(color = palette.foreground),
                            cursorBrush = SolidColor(palette.primary),
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(110.dp)
                                .clip(shape)
                                .background(palette.background)
                                .border(1.dp, palette.border, shape)
                                .padding(8.dp),
                        )
                    }
                    AppTextField(
                        title = "联系方式",
                        value = contact,
                        onValueChange = { contact = it },
                        placeholder = "邮箱 / Telegram（选填）",
                    )
                    AppButton(
                        title = "提交反馈",
                        icon = Icons.Filled.Send,
                        loading = submitting,
                        onClick = { scope.launch { submit() } },
                    )
                }
            }

            AppCard {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconTile(icon = Icons.Filled.ChatBubble, color = DS.IconColor.teal)
                        SectionHeader(title = "我的反馈")
                    }
                    if (items.isEmpty()) {
                        Text(text = "暂无反馈记录", style = DS.Font.bodySmall, color = palette.mutedForeground)
                    } else {
                        items.forEach { item ->
                            Column(
                                modifier = Modifier.padding(vertical = 6.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        text = if (item.title.isEmpty()) "反馈 #${item.id}" else item.title,
                                        style = DS.Font.bodySmall,
                                        color = palette.foreground,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Spacer(Modifier.weight(1f))
                                    val handled = item.status == "handled"
                                    StatusBadge(
                                        text = item.statusText,
                                        background = if (handled) palette.onlineBg else palette.muted,
                                        foreground = if (handled) palette.onlineText else palette.mutedForeground,
                                    )
                                }
                                Text(
                                    text = item.content,
                                    style = DS.Font.caption,
                                    color = palette.mutedForeground,
                                    maxLines = 3,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                if (item.reply.isNotEmpty()) {
                                    Text(
                                        text = "回复：${item.reply}",
                                        style = DS.Font.caption,
                                        color = palette.foreground,
                                    )
                                }
                                Text(
                                    text = Format.dateTime(item.createdAt),
                                    style = DS.Font.caption,
                                    color = palette.mutedForeground,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 邀请（InviteView，独立 Tab）

/**
 * 邀请好友：展示邀请码 / 邀请链接 / 奖励规则，支持一键复制与系统分享。
 * 对应 iOS `InviteView`（Tab 根页面，无返回按钮）。
 * [onOpen] 用于点击邀请链接时打开链接（Android 端替代 iOS 无跳转的展示行为）。
 */
@Composable
fun InviteView(onOpen: (String) -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()

    var payload by remember { mutableStateOf<CoinsPayload?>(null) }
    var copiedCode by remember { mutableStateOf(false) }
    var copiedLink by remember { mutableStateOf(false) }

    suspend fun load() {
        try {
            payload = ApiService.fetchCoins()
        } catch (e: Exception) {
            if (AppState.isCancelled(e)) return
            AppState.report(e)
        }
    }

    LaunchedEffect(Unit) { load() }

    ScreenScaffold(title = "邀请好友") {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Size.pagePadding)
                .padding(top = 8.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            InviteHero(payload)

            if (payload?.inviteEnabled == false) {
                BannerBar(message = "站点当前已关闭邀请奖励", kind = BannerKind.Warning)
            } else {
                // 固定结构：数据未就绪时先以占位展示，加载完成后仅数值变化，页面不跳动
                InviteCodeCard(
                    palette = palette,
                    payload = payload,
                    copiedCode = copiedCode,
                    copiedLink = copiedLink,
                    onCopiedCode = { copiedCode = true },
                    onCopiedLink = { copiedLink = true },
                    onOpen = onOpen,
                )
                InviteRewardCard(payload)
                BannerBar(
                    message = "好友注册成功后，奖励金币会自动到账，可在「套餐」页使用金币兑换套餐。",
                    kind = BannerKind.Info,
                )
            }
        }
    }
}

/** 邀请页顶部品牌头图。对应 iOS `InviteView.hero`。 */
@Composable
private fun InviteHero(payload: CoinsPayload?) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(DS.Radius.xxl))
            .background(Brush.linearGradient(listOf(DS.Brand.green, DS.Brand.tealDeep))),
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.People,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(26.dp),
            )
            Text(
                text = "邀请好友得金币",
                style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold),
                color = Color.White,
            )
            Text(
                text = "好友通过你的邀请码注册，双方均可获得金币奖励，金币可用于兑换套餐。",
                style = DS.Font.caption,
                color = Color.White.copy(alpha = 0.9f),
            )
            Row(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.18f))
                    .padding(horizontal = 10.dp, vertical = 5.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.CurrencyBitcoin,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(15.dp),
                )
                Text(
                    text = "我的金币 ${payload?.coins ?: 0}",
                    style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold),
                    color = Color.White,
                )
            }
        }
    }
}

/** 邀请码 / 邀请链接卡片。对应 iOS `InviteView.codeCard`。 */
@Composable
private fun InviteCodeCard(
    palette: Palette,
    payload: CoinsPayload?,
    copiedCode: Boolean,
    copiedLink: Boolean,
    onCopiedCode: () -> Unit,
    onCopiedLink: () -> Unit,
    onOpen: (String) -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    val code = payload?.inviteCode ?: ""
    val urlString = payload?.inviteUrl ?: ""

    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconTile(icon = Icons.Filled.Numbers, color = DS.IconColor.teal)
                SectionHeader(title = "我的邀请码", subtitle = "分享给好友即可参与")
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = if (code.isEmpty()) "------" else code,
                    style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace),
                    color = palette.foreground,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.weight(1f))
                Box(Modifier.width(104.dp)) {
                    AppButton(
                        title = if (copiedCode) "已复制" else "复制",
                        icon = if (copiedCode) Icons.Filled.Check else Icons.Filled.ContentCopy,
                        style = ButtonStyleKind.Secondary,
                        height = DS.Size.buttonHeightSmall,
                        disabled = code.isEmpty(),
                        onClick = {
                            clipboard.setText(AnnotatedString(code))
                            onCopiedCode()
                            AppState.showToast("邀请码已复制", BannerKind.Success)
                        },
                    )
                }
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(palette.border),
            )
            Text(text = "邀请链接", style = DS.Font.caption, color = palette.mutedForeground)
            Text(
                text = if (urlString.isEmpty()) "正在获取邀请链接…" else urlString,
                style = DS.Font.caption,
                color = palette.secondaryText,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { if (urlString.isNotEmpty()) onOpen(urlString) },
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AppButton(
                    title = if (copiedLink) "已复制" else "复制链接",
                    modifier = Modifier.weight(1f),
                    icon = Icons.Filled.Link,
                    style = ButtonStyleKind.Secondary,
                    height = DS.Size.buttonHeightSmall,
                    disabled = urlString.isEmpty(),
                    onClick = {
                        clipboard.setText(AnnotatedString(urlString))
                        onCopiedLink()
                        AppState.showToast("邀请链接已复制", BannerKind.Success)
                    },
                )
                Box(Modifier.weight(1f)) {
                    InviteShareLabel(
                        enabled = urlString.isNotEmpty(),
                        onClick = { shareText(context, urlString) },
                    )
                }
            }
        }
    }
}

/** 奖励规则卡片。对应 iOS `InviteView.rewardCard`。 */
@Composable
private fun InviteRewardCard(payload: CoinsPayload?) {
    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconTile(icon = Icons.Filled.CardGiftcard, color = DS.IconColor.orange)
                SectionHeader(title = "奖励规则")
            }
            InviteRewardRow(
                icon = Icons.Filled.HowToReg,
                title = "邀请人奖励",
                value = "${payload?.inviteRewardCoins ?: 0} 金币",
                color = DS.IconColor.green,
            )
            InviteRewardRow(
                icon = Icons.Filled.PersonAdd,
                title = "被邀请人奖励",
                value = "${payload?.inviteeRewardCoins ?: 0} 金币",
                color = DS.IconColor.cyan,
            )
            InviteRewardRow(
                icon = Icons.Filled.AutoAwesome,
                title = "新用户注册赠送",
                value = "${payload?.registerCoins ?: 0} 金币",
                color = DS.IconColor.teal,
            )
        }
    }
}

/** 奖励规则单行。对应 iOS `InviteView.rewardRow`。 */
@Composable
private fun InviteRewardRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    value: String,
    color: Color,
) {
    val palette = LocalPalette.current
    Row(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(26.dp)
                .clip(RoundedCornerShape(DS.Radius.sm))
                .background(color.copy(alpha = 0.14f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(13.dp),
            )
        }
        Text(text = title, style = DS.Font.bodySmall, color = palette.secondaryText)
        Spacer(Modifier.weight(1f))
        Text(text = value, style = DS.Font.value, color = DS.IconColor.orange)
    }
}

/** 分享按钮外观（对应 iOS `InviteView.shareLabel`）：无链接时占位且不可点击。 */
@Composable
private fun InviteShareLabel(enabled: Boolean, onClick: () -> Unit) {
    val palette = LocalPalette.current
    val interactionSource = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(DS.Size.buttonHeightSmall)
            .alpha(if (enabled) 1f else 0.45f)
            .clip(RoundedCornerShape(DS.Radius.lg))
            .background(palette.accentGradient)
            .then(
                if (enabled) {
                    Modifier
                        .pressableScale()
                        .clickable(interactionSource = interactionSource, indication = null, onClick = onClick)
                } else {
                    Modifier
                },
            ),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Filled.Share,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size(13.dp),
        )
        Spacer(Modifier.width(6.dp))
        Text(
            text = "分享",
            style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold),
            color = Color.White,
        )
    }
}

/** 系统分享（对应 iOS `ShareLink`）：使用 ACTION_SEND 文本分享。 */
private fun shareText(context: Context, url: String) {
    if (url.isEmpty()) return
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, url)
    }
    context.startActivity(Intent.createChooser(intent, "分享"))
}

// MARK: - 账号设置（AccountSettingsView）

/** 账号设置：修改密码 + 密保问题（已设置后只读展示）。对应 iOS `AccountSettingsView`。 */
@Composable
fun AccountSettingsView(onBack: () -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()

    var oldPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var savingPassword by remember { mutableStateOf(false) }

    var question by remember { mutableStateOf("") }
    var answer by remember { mutableStateOf("") }
    var savingSecurity by remember { mutableStateOf(false) }
    var currentQuestion by remember { mutableStateOf<String?>(null) }
    var securityLoaded by remember { mutableStateOf(false) }
    var loaded by remember { mutableStateOf(false) }

    /** 是否已设置密保（已设置后界面只读展示，不再提供修改入口） */
    val hasSecurityQuestion = !(currentQuestion ?: "").isEmpty()

    suspend fun changePassword() {
        if (newPassword.length < 6) {
            AppState.showToast("新密码至少 6 位", BannerKind.Warning)
            return
        }
        if (newPassword != confirmPassword) {
            AppState.showToast("两次输入的新密码不一致", BannerKind.Warning)
            return
        }
        savingPassword = true
        try {
            ApiService.changePassword(oldPassword, newPassword)
            AppState.showToast("密码已更新", BannerKind.Success)
            oldPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch (e: Exception) {
            AppState.report(e)
        } finally {
            savingPassword = false
        }
    }

    suspend fun saveSecurity() {
        if (question.isEmpty() || answer.length < 2) {
            AppState.showToast("请填写密保问题与答案（答案至少 2 个字符）", BannerKind.Warning)
            return
        }
        savingSecurity = true
        try {
            ApiService.updateSecurity(question, answer)
            currentQuestion = question
            AppState.showToast("密保已保存", BannerKind.Success)
            answer = ""
        } catch (e: Exception) {
            AppState.report(e)
        } finally {
            savingSecurity = false
        }
    }

    LaunchedEffect(Unit) {
        if (loaded) return@LaunchedEffect
        loaded = true
        currentQuestion = try {
            ApiService.fetchSecurityQuestion()
        } catch (e: Exception) {
            null
        }
        securityLoaded = true
    }

    ScreenScaffold(title = "账号设置", onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(DS.Size.pagePadding)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            AppCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconTile(icon = Icons.Filled.Lock, color = DS.IconColor.amber)
                        SectionHeader(title = "修改密码")
                    }
                    AppTextField(
                        title = "原密码",
                        value = oldPassword,
                        onValueChange = { oldPassword = it },
                        placeholder = "当前登录密码",
                        secure = true,
                    )
                    AppTextField(
                        title = "新密码",
                        value = newPassword,
                        onValueChange = { newPassword = it },
                        placeholder = "至少 6 位",
                        secure = true,
                    )
                    AppTextField(
                        title = "确认新密码",
                        value = confirmPassword,
                        onValueChange = { confirmPassword = it },
                        placeholder = "再次输入新密码",
                        secure = true,
                    )
                    AppButton(
                        title = "保存新密码",
                        icon = Icons.Filled.VerifiedUser,
                        loading = savingPassword,
                        onClick = { scope.launch { changePassword() } },
                    )
                }
            }

            AppCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconTile(icon = Icons.Filled.VpnKey, color = DS.IconColor.tealDeep)
                        SectionHeader(title = "密保问题", subtitle = "用于找回密码")
                    }
                    when {
                        hasSecurityQuestion -> {
                            // 已设置密保：仅只读展示问题，答案不明文展示，输入框不可点击，不再显示保存/更新按钮
                            ReadOnlyField(title = "密保问题", value = currentQuestion ?: "")
                            ReadOnlyField(title = "密保答案", masked = true)
                            Text(
                                text = "密保答案已加密保存，不会明文展示；如需修改，请联系管理员在「用户管理」中重置密保后重新设置。",
                                style = DS.Font.caption,
                                color = palette.mutedForeground,
                            )
                        }
                        securityLoaded -> {
                            AppTextField(
                                title = "密保问题",
                                value = question,
                                onValueChange = { question = it },
                                placeholder = "例如：我的第一台服务器名字",
                            )
                            AppTextField(
                                title = "密保答案",
                                value = answer,
                                onValueChange = { answer = it },
                                placeholder = "找回密码时使用（不区分大小写）",
                            )
                            AppButton(
                                title = "保存密保",
                                icon = Icons.Filled.VerifiedUser,
                                style = ButtonStyleKind.Primary,
                                loading = savingSecurity,
                                onClick = { scope.launch { saveSecurity() } },
                            )
                        }
                        else -> LoadingBlock(text = "正在获取密保信息…")
                    }
                }
            }
        }
    }
}