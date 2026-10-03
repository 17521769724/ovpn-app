@file:OptIn(
    androidx.compose.material3.ExperimentalMaterial3Api::class,
    androidx.compose.foundation.layout.ExperimentalLayoutApi::class,
)

package com.ovpn.panel.features

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.CurrencyBitcoin
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.ovpn.panel.core.ApiService
import com.ovpn.panel.core.AppState
import com.ovpn.panel.core.BannerKind
import com.ovpn.panel.core.DS
import com.ovpn.panel.core.Format
import com.ovpn.panel.core.LocalPalette
import com.ovpn.panel.core.OrderItem
import com.ovpn.panel.core.OrdersPayload
import com.ovpn.panel.core.Palette
import com.ovpn.panel.core.PaymentChannelItem
import com.ovpn.panel.core.PlanItem
import com.ovpn.panel.core.PlansPayload
import com.ovpn.panel.ui.AppButton
import com.ovpn.panel.ui.AppCard
import com.ovpn.panel.ui.AppTextField
import com.ovpn.panel.ui.BannerBar
import com.ovpn.panel.ui.ButtonStyleKind
import com.ovpn.panel.ui.EmptyHint
import com.ovpn.panel.ui.InfoRow
import com.ovpn.panel.ui.IconTile
import com.ovpn.panel.ui.LoadingBlock
import com.ovpn.panel.ui.ScreenScaffold
import com.ovpn.panel.ui.StatusBadge
import com.ovpn.panel.ui.pressableScale
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.util.Locale
import kotlin.math.round
import kotlin.math.roundToInt

// ============================================================================
// 套餐 / 订单 / 充值（Android 端移植，对应 iOS Features/PlansView.swift）
//
// 覆盖 iOS 的三个视图：
//   PlansView    （套餐 Tab，navigationTitle「套餐中心」）
//   OrdersView   （我的订单，navigationTitle「我的订单」）
//   RechargeView （余额充值，navigationTitle「余额充值」）
// 以及共享的支付方式 / 支付接口 / 倒计时等辅助逻辑。
//
// 注：iOS 的内置浏览器 SafariSheet 在 Android 端改为 Intent(ACTION_VIEW) 打开外部浏览器；
// 支付页关闭后的刷新用 Lifecycle ON_RESUME 观察实现（见 RefreshOnResume）。
// ============================================================================

// MARK: - 支付方式（对应 iOS private struct PayOption）

/** 支付方式（易支付：alipay / wxpay / qqpay），对应 iOS `PayOption`。 */
private data class PayOption(
    val id: String,
    val name: String,
    val icon: ImageVector,
    val tint: Color,
) {
    companion object {
        // 顺序与 iOS PayOption.all 完全一致（alipay / wxpay / qqpay）
        val all: List<PayOption> = listOf(
            PayOption("alipay", "支付宝", Icons.Filled.AccountCircle, DS.IconColor.cyan),
            PayOption("wxpay", "微信支付", Icons.Filled.Chat, DS.IconColor.green),
            PayOption("qqpay", "QQ 钱包", Icons.Filled.AccountBalanceWallet, DS.IconColor.teal),
        )
    }
}

/** 已确认的支付请求（对应 iOS `PendingPay`）：支付方式弹窗关闭后再创建订单。 */
private data class PendingPay(
    val plan: PlanItem,
    val method: String,
    /** 所选支付接口（余额抵扣时为 null） */
    val channelId: Int?,
    /** 是否使用余额全额抵扣（此时不再携带支付方式与接口） */
    val useBalance: Boolean,
)

/** 支付接口选项（对应 iOS `PayTargetOption`）：管理后台配置的接口 + 「余额抵扣」。 */
private data class PayTargetOption(
    val id: String, // "balance" 或 "channel:<id>"
    val name: String,
    val detail: String,
    val icon: ImageVector,
    val tint: Color,
    /** 不可选（如余额不足） */
    val disabled: Boolean,
)

/**
 * 构造支付接口选项列表（余额抵扣排在最后；余额不足时标记为不可选）。
 * 对应 iOS `payTargetOptions(amountCents:balanceCents:channels:)`。
 */
private fun payTargetOptions(
    amountCents: Int,
    balanceCents: Int,
    channels: List<PaymentChannelItem>,
): List<PayTargetOption> {
    val list = channels.map { channel ->
        val names = (channel.methods ?: emptyList()).mapNotNull { id ->
            PayOption.all.firstOrNull { it.id == id }?.name
        }
        PayTargetOption(
            id = "channel:${channel.id}",
            name = channel.name,
            detail = if (names.isEmpty()) "支持全部支付方式" else names.joinToString(" / "),
            icon = Icons.Filled.CreditCard,
            tint = DS.IconColor.cyan,
            disabled = false,
        )
    }.toMutableList()
    if (amountCents > 0) {
        val enough = balanceCents >= amountCents
        list.add(
            PayTargetOption(
                id = "balance",
                name = "余额抵扣",
                detail = if (enough) "使用账户余额全额支付，无需选择支付方式" else "余额不足，请先充值后再抵扣",
                icon = Icons.Filled.AccountBalanceWallet,
                tint = DS.IconColor.green,
                disabled = !enough,
            ),
        )
    }
    return list
}

/**
 * 某支付接口支持的支付方式（未配置方式时兜底展示全部标准方式）。
 * 对应 iOS `methodsForTarget(_:channels:)`。
 */
private fun methodsForTarget(target: String, channels: List<PaymentChannelItem>): List<PayOption> {
    if (!target.startsWith("channel:")) return PayOption.all
    val id = target.removePrefix("channel:").toIntOrNull() ?: return PayOption.all
    val channel = channels.firstOrNull { it.id == id } ?: return PayOption.all
    val list = PayOption.all.filter { (channel.methods ?: emptyList()).contains(it.id) }
    return if (list.isEmpty()) PayOption.all else list
}

// MARK: - 共享 UI 片段

/**
 * 支付接口行（对应 iOS `targetRow` / `rechargeTargetRow`，两者仅在「禁用态」上有差异）。
 * 禁用时：图标置灰、文字变 muted、整行 60% 透明且不可点击。
 */
@Composable
private fun PayTargetRow(
    palette: Palette,
    option: PayTargetOption,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(DS.Radius.lg)
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (selected) palette.primary.copy(alpha = 0.10f) else palette.card)
            .border(1.dp, if (selected) palette.primary else palette.border, shape)
            .then(if (!option.disabled) Modifier.pressableScale(scale = 0.98f) else Modifier)
            .then(
                if (!option.disabled) {
                    Modifier.clickable(interactionSource = interaction, indication = null) { onClick() }
                } else {
                    Modifier
                },
            )
            .alpha(if (option.disabled) 0.6f else 1f)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        IconTile(
            icon = option.icon,
            color = if (option.disabled) DS.IconColor.slate else option.tint,
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = option.name,
                style = DS.Font.body,
                color = if (option.disabled) palette.mutedForeground else palette.foreground,
            )
            Text(
                text = option.detail,
                style = DS.Font.caption,
                color = palette.mutedForeground,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Spacer(Modifier.width(8.dp))
        Icon(
            imageVector = if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
            contentDescription = null,
            tint = if (selected) palette.primary else palette.mutedForeground.copy(alpha = 0.5f),
            modifier = Modifier.size(18.dp),
        )
    }
}

/** 支付方式胶囊（对应 iOS 付款方式弹窗 / 充值页内的支付方式按钮）。 */
@Composable
private fun MethodChip(
    palette: Palette,
    option: PayOption,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val fg = if (selected) Color.White else palette.secondaryText
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .height(34.dp)
            .clip(CircleShape)
            .background(if (selected) palette.primary else palette.muted.copy(alpha = 0.6f))
            .pressableScale(scale = 0.96f)
            .clickable(interactionSource = interaction, indication = null) { onClick() }
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Icon(
                imageVector = option.icon,
                contentDescription = null,
                tint = fg,
                modifier = Modifier.size(12.dp),
            )
            Text(
                text = option.name,
                style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium),
                color = fg,
            )
        }
    }
}

/** 快捷金额胶囊（对应 iOS 充值页的 FlowLayout 内按钮）。 */
@Composable
private fun QuickAmountChip(text: String, selected: Boolean, onClick: () -> Unit) {
    val palette = LocalPalette.current
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .height(32.dp)
            .clip(CircleShape)
            .background(if (selected) palette.primary else palette.muted.copy(alpha = 0.6f))
            .pressableScale(scale = 0.96f)
            .clickable(interactionSource = interaction, indication = null) { onClick() }
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "$text 元",
            style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium),
            color = if (selected) Color.White else palette.secondaryText,
            maxLines = 1,
        )
    }
}

/**
 * 打开外部支付页（对应 iOS `SafariSheet`）。
 * 用 `Intent(ACTION_VIEW)` 拉起系统浏览器；[onConsume] 在拉起后清空 payUrl 状态。
 */
@Composable
private fun LaunchPayUrl(payUrl: String?, onConsume: () -> Unit) {
    val context = LocalContext.current
    LaunchedEffect(payUrl) {
        val url = payUrl ?: return@LaunchedEffect
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (e: Exception) {
            AppState.report(e)
        }
        onConsume()
    }
}

/**
 * 支付页返回后刷新（对应 iOS `SafariSheet` 的 `onDismiss`）。
 *
 * Android 端不使用 rememberLauncherForActivityResult：改用 Lifecycle 的 ON_RESUME 观察，
 * 打开外部支付页后返回应用时触发一次 [onRefresh]；[enabled] 置 true 表示「期望返回后刷新」。
 */
@Composable
private fun RefreshOnResume(enabled: Boolean, onRefresh: () -> Unit) {
    val owner = LocalLifecycleOwner.current
    val current by rememberUpdatedState(onRefresh)
    DisposableEffect(owner, enabled) {
        if (!enabled) {
            onDispose { }
        } else {
            val observer = LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) current()
            }
            owner.lifecycle.addObserver(observer)
            onDispose { owner.lifecycle.removeObserver(observer) }
        }
    }
}

// MARK: - 套餐购买（对应 iOS struct PlansView）

/**
 * 套餐购买（套餐 Tab 根页面，无返回按钮）。
 * 对应 iOS `PlansView`，navigationTitle「套餐中心」。
 */
@Suppress("UNUSED_PARAMETER")
@Composable
fun PlansView(onOpen: (String) -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()

    var payload by remember { mutableStateOf<PlansPayload?>(null) }
    var loading by remember { mutableStateOf(true) }
    var paying by remember { mutableStateOf(false) }
    var payUrl by remember { mutableStateOf<String?>(null) }
    /** 正在选择付款方式的套餐（非空时弹出付款方式选择） */
    var pickerPlan by remember { mutableStateOf<PlanItem?>(null) }
    /** 所选支付接口（"balance" 表示余额抵扣） */
    var payTarget by remember { mutableStateOf("") }
    var selectedMethod by remember { mutableStateOf(PayOption.all.first().id) }
    var pendingPay by remember { mutableStateOf<PendingPay?>(null) }
    var refreshOnReturn by remember { mutableStateOf(false) }

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // 对应 iOS load()
    suspend fun load() {
        loading = true
        try {
            payload = ApiService.fetchPlans()
        } catch (e: Exception) {
            if (AppState.isCancelled(e)) return
            AppState.report(e)
        } finally {
            loading = false
        }
    }

    // 对应 iOS buy(plan:method:channelId:useBalance:)
    suspend fun buy(plan: PlanItem, method: String, channelId: Int?, useBalance: Boolean) {
        paying = true
        try {
            val result = ApiService.createOrder(
                planId = plan.id,
                method = method,
                payWithBalance = useBalance,
                channelId = channelId,
            )
            if (result.paidValue) {
                AppState.showToast(result.message.ifEmpty { "支付成功" }, BannerKind.Success)
                AppState.refreshUser()
                load()
            } else if (result.payUrl.isEmpty()) {
                AppState.showToast(
                    result.message.ifEmpty { "订单已创建，请联系管理员完成支付" },
                    BannerKind.Warning,
                )
            } else {
                payUrl = result.payUrl
                refreshOnReturn = true
                AppState.showToast("订单已创建，请在 10 分钟内完成支付", BannerKind.Info)
            }
        } catch (e: Exception) {
            AppState.report(e)
        } finally {
            paying = false
        }
    }

    // 对应 iOS redeemWithCoins(plan:)（主控直接发货）
    suspend fun redeemWithCoins(plan: PlanItem) {
        if (plan.coinPriceValue <= 0) return
        if ((payload?.user?.coins ?: 0) < plan.coinPriceValue) {
            AppState.showToast("金币不足，需要 ${plan.coinPriceValue} 金币", BannerKind.Warning)
            return
        }
        paying = true
        try {
            val result = ApiService.createOrder(planId = plan.id, method = "coins", useCoins = true)
            AppState.showToast(result.message.ifEmpty { "兑换成功" }, BannerKind.Success)
            AppState.refreshUser()
            load()
        } catch (e: Exception) {
            AppState.report(e)
        } finally {
            paying = false
        }
    }

    // 对应 iOS 付款方式弹窗 onDismiss：确认后先关闭弹窗，再创建订单
    fun processPending() {
        val pending = pendingPay ?: return
        pendingPay = null
        scope.launch { buy(pending.plan, pending.method, pending.channelId, pending.useBalance) }
    }

    // 支付页关闭后刷新一次：主控异步回调到账后，套餐状态即刻可见
    RefreshOnResume(enabled = refreshOnReturn) {
        refreshOnReturn = false
        scope.launch { load() }
    }
    LaunchPayUrl(payUrl) { payUrl = null }

    // 对应 iOS .task { await load() }
    LaunchedEffect(Unit) { load() }

    // 对应 iOS 付款方式弹窗 .onAppear：默认选中第一个可用支付接口（无接口时退回余额抵扣）
    LaunchedEffect(pickerPlan) {
        val plan = pickerPlan ?: return@LaunchedEffect
        val channels = payload?.paymentChannels ?: emptyList()
        val balanceCents = payload?.user?.balanceCents ?: 0
        val available = payTargetOptions(plan.priceCents, balanceCents, channels).filter { !it.disabled }
        if (available.none { it.id == payTarget }) {
            payTarget = available.firstOrNull()?.id ?: ""
        }
        val methods = methodsForTarget(payTarget, channels)
        if (methods.none { it.id == selectedMethod }) {
            selectedMethod = methods.firstOrNull()?.id ?: "alipay"
        }
    }

    ScreenScaffold(title = "套餐中心", onBack = null) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Size.pagePadding)
                .padding(top = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            val current = payload
            if (current != null && !current.purchaseEnabled) {
                BannerBar(message = "站点当前已关闭购买功能", kind = BannerKind.Warning)
            }

            val plans = current?.plans
            if (loading && current == null) {
                LoadingBlock(text = "正在获取套餐…")
            } else if (plans != null && plans.isEmpty()) {
                EmptyHint(
                    icon = Icons.Filled.Inventory2,
                    title = "暂无可购买套餐",
                    subtitle = "请联系管理员配置套餐",
                )
            } else {
                (plans ?: emptyList()).forEach { plan ->
                    PlanCard(
                        palette = palette,
                        plan = plan,
                        currencySymbol = current?.currencySymbol ?: "¥",
                        purchaseEnabled = current?.purchaseEnabled ?: false,
                        paying = paying,
                        onRedeem = { scope.launch { redeemWithCoins(plan) } },
                        onBuy = { pickerPlan = plan },
                    )
                }
            }
        }
    }

    // 付款方式选择弹窗（对应 iOS .sheet(item: $pickerPlan)）
    val plan = pickerPlan
    if (plan != null) {
        ModalBottomSheet(
            onDismissRequest = {
                pickerPlan = null
                processPending()
            },
            sheetState = sheetState,
            containerColor = palette.card,
        ) {
            PaymentMethodSheetContent(
                palette = palette,
                plan = plan,
                payload = payload,
                payTarget = payTarget,
                selectedMethod = selectedMethod,
                paying = paying,
                onSelectTarget = { id ->
                    payTarget = id
                    // 切换接口后，默认选中该接口的第一个可用支付方式
                    val available = methodsForTarget(id, payload?.paymentChannels ?: emptyList())
                    if (available.none { it.id == selectedMethod }) {
                        selectedMethod = available.firstOrNull()?.id ?: "alipay"
                    }
                },
                onSelectMethod = { selectedMethod = it },
                onConfirm = {
                    val useBalance = payTarget == "balance"
                    val channelId = if (useBalance) null else payTarget.removePrefix("channel:").toIntOrNull()
                    pendingPay = PendingPay(plan, selectedMethod, channelId, useBalance)
                    scope.launch {
                        sheetState.hide()
                        pickerPlan = null
                        processPending()
                    }
                },
            )
        }
    }
}

/** 付款方式选择弹窗内容（对应 iOS private func paymentMethodSheet(_:plan:)）。 */
@Composable
private fun PaymentMethodSheetContent(
    palette: Palette,
    plan: PlanItem,
    payload: PlansPayload?,
    payTarget: String,
    selectedMethod: String,
    paying: Boolean,
    onSelectTarget: (String) -> Unit,
    onSelectMethod: (String) -> Unit,
    onConfirm: () -> Unit,
) {
    val channels = payload?.paymentChannels ?: emptyList()
    val balanceCents = payload?.user?.balanceCents ?: 0
    val symbol = payload?.currencySymbol ?: "¥"
    val options = payTargetOptions(amountCents = plan.priceCents, balanceCents = balanceCents, channels = channels)
    val methods = methodsForTarget(payTarget, channels)
    val useBalance = payTarget == "balance"
    val balanceEnough = plan.priceCents > 0 && balanceCents >= plan.priceCents
    // 无任何可用接口且余额不足：仅提示，不产生订单
    val canPay = if (useBalance) balanceEnough else (payTarget.isNotEmpty() && methods.isNotEmpty())

    Column(
        modifier = Modifier.fillMaxWidth().padding(DS.Size.pagePadding),
        verticalArrangement = Arrangement.spacedBy(DS.Size.gap),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("选择支付接口", style = DS.Font.section, color = palette.foreground)
            Text(
                "${plan.name} · 应付 ${Format.money(plan.priceCents, symbol)}",
                style = DS.Font.bodySmall,
                color = palette.mutedForeground,
            )
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 360.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Size.gap)) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    options.forEach { option ->
                        PayTargetRow(
                            palette = palette,
                            option = option,
                            selected = payTarget == option.id,
                        ) { onSelectTarget(option.id) }
                    }
                }

                if (options.isEmpty()) {
                    BannerBar(
                        message = "站点暂未配置支付接口，请联系管理员完成支付",
                        kind = BannerKind.Warning,
                    )
                }

                // 余额抵扣：不再展示支付方式选择
                if (useBalance) {
                    Text(
                        "将使用账户余额全额支付 ${Format.money(plan.priceCents, symbol)}，确认后立即开通套餐",
                        style = DS.Font.caption,
                        color = palette.mutedForeground,
                    )
                } else if (methods.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("支付方式", style = DS.Font.bodySmall, color = palette.secondaryText)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            methods.forEach { option ->
                                MethodChip(
                                    palette = palette,
                                    option = option,
                                    selected = selectedMethod == option.id,
                                ) { onSelectMethod(option.id) }
                            }
                            Spacer(Modifier.weight(1f))
                        }
                    }
                }

                if (balanceCents > 0 && !balanceEnough) {
                    Text(
                        "账户余额 ¥${String.format(Locale.US, "%.2f", balanceCents / 100.0)}，" +
                            "不足以全额抵扣本套餐，可先到「我的 → 余额充值」充值后再使用",
                        style = DS.Font.caption,
                        color = palette.mutedForeground,
                    )
                }
            }
        }

        AppButton(
            title = if (paying) "正在创建订单…" else "支付 ${Format.money(plan.priceCents, symbol)}",
            icon = Icons.Filled.CreditCard,
            style = ButtonStyleKind.Primary,
            loading = paying,
            disabled = paying || !canPay,
        ) {
            if (canPay) onConfirm()
        }

        Text(
            if (useBalance) {
                "确认后将直接从账户余额扣款并开通套餐"
            } else {
                "点击支付后将打开内置浏览器，在支付页面完成付款"
            },
            style = DS.Font.caption,
            color = palette.mutedForeground,
        )
    }
}

/** 套餐卡片（对应 iOS private func planCard(_:plan:)）。 */
@Composable
private fun PlanCard(
    palette: Palette,
    plan: PlanItem,
    currencySymbol: String,
    purchaseEnabled: Boolean,
    paying: Boolean,
    onRedeem: () -> Unit,
    onBuy: () -> Unit,
) {
    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    IconTile(
                        icon = if (plan.isCurrent) Icons.Filled.Verified else Icons.Filled.CardGiftcard,
                        color = if (plan.isCurrent) DS.IconColor.green else DS.IconColor.teal,
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Text(plan.name, style = DS.Font.section, color = palette.foreground)
                            if (plan.isCurrent) {
                                StatusBadge(
                                    text = "当前套餐",
                                    background = palette.onlineBg,
                                    foreground = palette.onlineText,
                                )
                            }
                        }
                        StatusBadge(
                            text = "赠 Lv.${plan.levelValue}",
                            background = DS.IconColor.teal.copy(alpha = 0.14f),
                            foreground = DS.IconColor.teal,
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
                Text(
                    Format.money(plan.priceCents, currencySymbol),
                    style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.SemiBold),
                    color = DS.IconColor.orange,
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                InfoRow(label = "时长", value = "${plan.durationDays} 天")
                InfoRow(label = "流量", value = Format.traffic(plan.trafficBytes))
                InfoRow(label = "限速", value = Format.speed(plan.speedLimitKbps))
                InfoRow(label = "设备数", value = if (plan.deviceLimit > 0) "${plan.deviceLimit} 台" else "不限")
                InfoRow(label = "赠送等级", value = "Lv.${plan.levelValue} 等级")
                if (plan.bonusCoinsValue > 0) {
                    InfoRow(
                        label = "赠送金币",
                        value = "${plan.bonusCoinsValue} 金币",
                        valueColor = DS.IconColor.orange,
                    )
                }
            }

            // 套餐备注：置于设备数等信息下方
            val description = plan.description
            if (!description.isNullOrEmpty()) {
                Column(
                    modifier = Modifier.padding(top = 2.dp),
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Text("备注", style = DS.Font.caption, color = palette.mutedForeground)
                    Text(description, style = DS.Font.bodySmall, color = palette.secondaryText)
                }
            }

            // 金币兑换与立即购买同一行显示
            if (plan.exchangeable) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    AppButton(
                        title = "金币兑换 ${plan.coinPriceValue}",
                        modifier = Modifier.weight(1f),
                        icon = Icons.Filled.CurrencyBitcoin,
                        style = ButtonStyleKind.Secondary,
                        loading = paying,
                        onClick = onRedeem,
                    )
                    AppButton(
                        title = "立即购买",
                        modifier = Modifier.weight(1f),
                        icon = Icons.Filled.ShoppingCart,
                        style = ButtonStyleKind.Primary,
                        loading = paying,
                        disabled = !purchaseEnabled,
                        onClick = onBuy,
                    )
                }
            } else {
                AppButton(
                    title = "立即购买",
                    icon = Icons.Filled.ShoppingCart,
                    style = ButtonStyleKind.Primary,
                    loading = paying,
                    disabled = !purchaseEnabled,
                    onClick = onBuy,
                )
            }
        }
    }
}

// MARK: - 我的订单（对应 iOS struct OrdersView）

/**
 * 我的订单（10 分钟支付窗口 + 继续支付 + 取消），从「我的」进入。
 * 对应 iOS `OrdersView`，navigationTitle「我的订单」。
 */
@Composable
fun OrdersView(onBack: () -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()

    var payload by remember { mutableStateOf<OrdersPayload?>(null) }
    var loading by remember { mutableStateOf(true) }
    var payUrl by remember { mutableStateOf<String?>(null) }
    var busyId by remember { mutableStateOf<Int?>(null) }
    var now by remember { mutableStateOf(Instant.now()) }
    var refreshedExpired by remember { mutableStateOf(false) }

    // 对应 iOS remainingSeconds(_:)：按当前时间实时计算剩余秒数
    fun remainingSeconds(order: OrderItem): Int {
        if (order.status != "pending") return 0
        val expiresAt = order.expiresAt
        if (expiresAt.isNullOrEmpty()) return 0
        val date = Format.parse(expiresAt) ?: return 0
        return maxOf(0, round(Duration.between(now, date).toMillis() / 1000.0).toInt())
    }

    // 对应 iOS load()
    suspend fun load() {
        loading = true
        try {
            payload = ApiService.fetchOrders()
            refreshedExpired = false
        } catch (e: Exception) {
            if (AppState.isCancelled(e)) return
            AppState.report(e)
        } finally {
            loading = false
        }
    }

    // 对应 iOS pay(_:)（复用原订单，10 分钟内有效）
    suspend fun pay(order: OrderItem) {
        busyId = order.id
        try {
            val result = ApiService.payOrder(order.id)
            if (result.payUrl.isEmpty()) {
                AppState.showToast(
                    result.message.ifEmpty { "订单已创建，请联系管理员完成支付" },
                    BannerKind.Warning,
                )
            } else {
                payUrl = result.payUrl
            }
        } catch (e: Exception) {
            AppState.report(e)
            load()
        } finally {
            busyId = null
        }
    }

    // 对应 iOS cancel(_:)
    suspend fun cancel(order: OrderItem) {
        busyId = order.id
        try {
            ApiService.cancelOrder(order.id)
            AppState.showToast("订单已取消", BannerKind.Success)
            load()
        } catch (e: Exception) {
            AppState.report(e)
        } finally {
            busyId = null
        }
    }

    LaunchPayUrl(payUrl) { payUrl = null }

    // 对应 iOS .task { await load() }
    LaunchedEffect(Unit) { load() }

    // 对应 iOS TimelineView/Timer.publish(every: 1)：每秒刷新 now，并在倒计时结束时自动刷新一次列表
    LaunchedEffect(Unit) {
        while (isActive) {
            delay(1000L)
            now = Instant.now()
            if (!refreshedExpired) {
                val expired = (payload?.orders ?: emptyList()).any {
                    it.status == "pending" && remainingSeconds(it) <= 1
                }
                if (expired) {
                    refreshedExpired = true
                    load()
                }
            }
        }
    }

    ScreenScaffold(title = "我的订单", onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Size.pagePadding)
                .padding(top = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            val orders = payload?.orders
            if (loading && payload == null) {
                LoadingBlock(text = "正在获取订单…")
            } else if (orders.isNullOrEmpty()) {
                EmptyHint(icon = Icons.Filled.Description, title = "暂无订单")
            } else {
                orders.forEach { order ->
                    OrderCard(
                        palette = palette,
                        order = order,
                        remaining = remainingSeconds(order),
                        busyId = busyId,
                        onPay = { scope.launch { pay(order) } },
                        onCancel = { scope.launch { cancel(order) } },
                    )
                }
            }
        }
    }
}

/** 订单卡片（对应 iOS private func orderCard(_:order:)）。 */
@Composable
private fun OrderCard(
    palette: Palette,
    order: OrderItem,
    remaining: Int,
    busyId: Int?,
    onPay: () -> Unit,
    onCancel: () -> Unit,
) {
    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                IconTile(icon = orderIcon(order), color = orderColor(order))
                Text(order.planName ?: "套餐", style = DS.Font.section, color = palette.foreground)
                Spacer(Modifier.weight(1f))
                StatusBadge(
                    text = order.statusText,
                    background = orderStatusBackground(palette, order),
                    foreground = orderStatusForeground(palette, order),
                )
            }
            InfoRow(label = "订单号", value = order.orderNo)
            InfoRow(label = "金额", value = Format.money(order.amountCents))
            InfoRow(label = "创建时间", value = Format.dateTime(order.createdAt))
            order.paidAt?.let { InfoRow(label = "支付时间", value = Format.dateTime(it)) }

            if (order.status == "pending") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("剩余支付时间", style = DS.Font.bodySmall, color = palette.mutedForeground)
                    Spacer(Modifier.weight(1f))
                    if (remaining > 0) {
                        Text(
                            Format.countdown(remaining),
                            style = DS.Font.number,
                            color = DS.IconColor.amber,
                        )
                    } else {
                        Text("已过期", style = DS.Font.number, color = palette.offlineText)
                    }
                }
            }

            if (order.status == "pending") {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (remaining > 0) {
                        ContinuePayButton(
                            modifier = Modifier.weight(1f),
                            busy = busyId == order.id,
                            disabled = busyId != null,
                            onClick = onPay,
                        )
                    }
                    CancelOrderButton(
                        palette = palette,
                        modifier = Modifier.weight(1f),
                        disabled = busyId != null,
                        onClick = onCancel,
                    )
                }
            }
        }
    }
}

/** 「继续支付」按钮（对应 iOS orderCard 内的绿色按钮）。 */
@Composable
private fun ContinuePayButton(
    modifier: Modifier,
    busy: Boolean,
    disabled: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(DS.Radius.lg)
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = modifier
            .height(38.dp)
            .clip(shape)
            .background(DS.IconColor.green)
            .then(if (!disabled) Modifier.pressableScale(scale = 0.97f) else Modifier)
            .then(
                if (!disabled) {
                    Modifier.clickable(interactionSource = interaction, indication = null) { onClick() }
                } else {
                    Modifier
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (busy) {
                CircularProgressIndicator(
                    modifier = Modifier.size(14.dp),
                    color = Color.White,
                    strokeWidth = 2.dp,
                )
            } else {
                Icon(
                    imageVector = Icons.Filled.CreditCard,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(13.dp),
                )
            }
            Text("继续支付", style = DS.Font.bodySmall, color = Color.White)
        }
    }
}

/** 「取消订单」按钮（对应 iOS orderCard 内的描边按钮）。 */
@Composable
private fun CancelOrderButton(
    palette: Palette,
    modifier: Modifier,
    disabled: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(DS.Radius.lg)
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = modifier
            .height(38.dp)
            .clip(shape)
            .background(palette.card)
            .border(1.dp, palette.border, shape)
            .then(if (!disabled) Modifier.pressableScale(scale = 0.97f) else Modifier)
            .then(
                if (!disabled) {
                    Modifier.clickable(interactionSource = interaction, indication = null) { onClick() }
                } else {
                    Modifier
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        Text("取消订单", style = DS.Font.bodySmall, color = palette.foreground)
    }
}

/** 订单状态图标（对应 iOS orderIcon(_:)）。 */
private fun orderIcon(order: OrderItem): ImageVector = when (order.status) {
    "paid" -> Icons.Filled.Verified
    "pending" -> Icons.Filled.AccessTime
    "cancelled" -> Icons.Filled.Cancel
    "expired" -> Icons.Filled.HourglassEmpty
    "refunded" -> Icons.Filled.Replay
    else -> Icons.Filled.Description
}

/** 订单状态配色（对应 iOS orderColor(_:)）。 */
private fun orderColor(order: OrderItem): Color = when (order.status) {
    "paid" -> DS.IconColor.green
    "pending" -> DS.IconColor.amber
    "cancelled", "expired" -> DS.IconColor.slate
    else -> DS.IconColor.cyan
}

/** 订单状态徽章底色（对应 iOS statusBackground(_:order:)）。 */
private fun orderStatusBackground(palette: Palette, order: OrderItem): Color = when (order.status) {
    "paid" -> palette.onlineBg
    "pending" -> palette.warningBg
    else -> palette.muted
}

/** 订单状态徽章文字色（对应 iOS statusForeground(_:order:)）。 */
private fun orderStatusForeground(palette: Palette, order: OrderItem): Color = when (order.status) {
    "paid" -> palette.onlineText
    "pending" -> palette.warningText
    else -> palette.mutedForeground
}

// MARK: - 余额充值（对应 iOS struct RechargeView）

/**
 * 余额充值（个人中心 → 余额充值）：先选支付接口，再选该接口支持的支付方式，
 * 确认后在内置浏览器打开支付页面；到账后余额可用于购买套餐抵扣。
 * 对应 iOS `RechargeView`，navigationTitle「余额充值」。
 */
@Composable
fun RechargeView(onBack: () -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()

    var payload by remember { mutableStateOf<PlansPayload?>(null) }
    var loading by remember { mutableStateOf(true) }
    var amountText by remember { mutableStateOf("30") }
    var payTarget by remember { mutableStateOf("") }
    var selectedMethod by remember { mutableStateOf(PayOption.all.first().id) }
    var paying by remember { mutableStateOf(false) }
    var payUrl by remember { mutableStateOf<String?>(null) }
    var refreshOnReturn by remember { mutableStateOf(false) }

    val quickAmounts = listOf(10.0, 30.0, 50.0, 100.0, 200.0, 500.0)

    fun amountYuan(): Double = amountText.trim().toDoubleOrNull() ?: 0.0

    // 对应 iOS 默认选中逻辑（onAppear / load 后补选）
    fun applyDefaults(channels: List<PaymentChannelItem>) {
        val available = payTargetOptions(amountCents = 0, balanceCents = 0, channels = channels)
        if (available.none { it.id == payTarget }) {
            payTarget = available.firstOrNull()?.id ?: ""
        }
        val methods = methodsForTarget(payTarget, channels)
        if (methods.none { it.id == selectedMethod }) {
            selectedMethod = methods.firstOrNull()?.id ?: "alipay"
        }
    }

    // 对应 iOS load()
    suspend fun load() {
        loading = true
        try {
            val value = ApiService.fetchPlans()
            payload = value
            applyDefaults(value.paymentChannels ?: emptyList())
        } catch (e: Exception) {
            if (AppState.isCancelled(e)) return
            AppState.report(e)
        } finally {
            loading = false
        }
    }

    // 对应 iOS recharge()
    suspend fun recharge() {
        val yuan = amountYuan()
        if (yuan < 1) {
            AppState.showToast("单次充值金额不得少于 1 元", BannerKind.Warning)
            return
        }
        if (payTarget.isEmpty()) {
            AppState.showToast("请选择支付接口", BannerKind.Warning)
            return
        }
        paying = true
        try {
            val channelId = payTarget.removePrefix("channel:").toIntOrNull()
            val result = ApiService.rechargeBalance(
                amountYuan = yuan,
                method = selectedMethod,
                channelId = channelId,
            )
            if (result.payUrl.isEmpty()) {
                AppState.showToast(
                    result.message.ifEmpty { "订单已创建，请联系管理员完成支付" },
                    BannerKind.Warning,
                )
            } else {
                payUrl = result.payUrl
                refreshOnReturn = true
                AppState.showToast("订单已创建，请在 10 分钟内完成支付", BannerKind.Info)
            }
        } catch (e: Exception) {
            AppState.report(e)
        } finally {
            paying = false
        }
    }

    // 支付页关闭后刷新余额（异步回调到账后即可见）
    RefreshOnResume(enabled = refreshOnReturn) {
        refreshOnReturn = false
        scope.launch {
            AppState.refreshUser()
            load()
        }
    }
    LaunchPayUrl(payUrl) { payUrl = null }

    // 对应 iOS .task { await load() }
    LaunchedEffect(Unit) { load() }

    ScreenScaffold(title = "余额充值", onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Size.pagePadding)
                .padding(top = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            if (loading && payload == null) {
                LoadingBlock(text = "正在获取充值信息…")
            } else {
                val channels = payload?.paymentChannels ?: emptyList()
                // 充值场景不展示「余额抵扣」选项（amountCents 传 0）
                val options = payTargetOptions(amountCents = 0, balanceCents = 0, channels = channels)
                val methods = methodsForTarget(payTarget, channels)
                val balanceCents = payload?.user?.balanceCents ?: 0
                val symbol = payload?.currencySymbol ?: "¥"

                // 余额概览
                AppCard {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        IconTile(
                            icon = Icons.Filled.AccountBalanceWallet,
                            color = DS.IconColor.green,
                            size = 40.dp,
                        )
                        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text("账户余额", style = DS.Font.caption, color = palette.mutedForeground)
                            Text(
                                Format.money(balanceCents, symbol),
                                style = TextStyle(
                                    fontSize = 20.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    fontFeatureSettings = "tnum",
                                ),
                                color = palette.foreground,
                            )
                        }
                        Spacer(Modifier.weight(1f))
                        StatusBadge(
                            text = "可用于抵扣套餐",
                            background = palette.onlineBg,
                            foreground = palette.onlineText,
                        )
                    }
                }

                // 充值金额
                AppCard {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        AppTextField(
                            title = "充值金额（元）",
                            value = amountText,
                            onValueChange = { amountText = it },
                            placeholder = "请输入充值金额（最少 1 元）",
                            keyboardType = KeyboardType.Decimal,
                        )
                        // 快捷金额：一行放不下时整块自动换行
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            quickAmounts.forEach { value ->
                                val text = String.format(Locale.US, "%.0f", value)
                                QuickAmountChip(
                                    text = text,
                                    selected = amountText == text,
                                ) { amountText = text }
                            }
                        }
                    }
                }

                // 支付接口 + 支付方式
                AppCard {
                    Column(verticalArrangement = Arrangement.spacedBy(DS.Size.gap)) {
                        Text("支付接口", style = DS.Font.bodySmall, color = palette.secondaryText)
                        if (options.isEmpty()) {
                            BannerBar(
                                message = "站点暂未配置支付接口，请联系管理员完成充值",
                                kind = BannerKind.Warning,
                            )
                        } else {
                            options.forEach { option ->
                                PayTargetRow(
                                    palette = palette,
                                    option = option,
                                    selected = payTarget == option.id,
                                ) {
                                    payTarget = option.id
                                    val available = methodsForTarget(option.id, channels)
                                    if (available.none { it.id == selectedMethod }) {
                                        selectedMethod = available.firstOrNull()?.id ?: "alipay"
                                    }
                                }
                            }
                        }

                        if (methods.isNotEmpty() && payTarget.isNotEmpty()) {
                            Text(
                                "支付方式",
                                style = DS.Font.bodySmall,
                                color = palette.secondaryText,
                                modifier = Modifier.padding(top = 2.dp),
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                methods.forEach { option ->
                                    MethodChip(
                                        palette = palette,
                                        option = option,
                                        selected = selectedMethod == option.id,
                                    ) { selectedMethod = option.id }
                                }
                                Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                }

                AppButton(
                    title = if (paying) {
                        "正在创建订单…"
                    } else {
                        "去支付 ${Format.money((amountYuan() * 100).roundToInt(), symbol)}"
                    },
                    icon = Icons.Filled.CreditCard,
                    style = ButtonStyleKind.Primary,
                    loading = paying,
                    disabled = paying || amountYuan() < 1 || payTarget.isEmpty(),
                    onClick = { scope.launch { recharge() } },
                )

                Text(
                    "充值成功后余额将实时到账，可在购买套餐时选择「余额抵扣」全额支付",
                    style = DS.Font.caption,
                    color = palette.mutedForeground,
                )
            }
        }
    }
}