package com.ovpn.panel.core

import java.time.Duration
import java.time.Instant
import kotlin.math.round

// MARK: - 通用
// 注：iOS 的 Envelope<T> 未移植，{ code, message, data } 包裹由 ApiClient 统一处理。

/** APP 端用户信息（对应主控 buildAppUserPayload） */
@kotlinx.serialization.Serializable
data class AppUser(
    val id: Int = 0,
    val username: String = "",
    val email: String? = null,
    val role: String = "",
    val status: String = "",
    val planId: Int? = null,
    val planName: String? = null,
    val planExpiresAt: String? = null,
    val trafficLimitBytes: Long = 0,
    val trafficUsedBytes: Long = 0,
    val remainBytes: Long = 0,
    val speedLimitKbps: Int = 0,
    val deviceLimit: Int = 0,
    // 用户等级 / 金币 / 余额（老版本主控可能不下发）
    val level: Int? = null,
    val coins: Int? = null,
    val balanceCents: Int? = null,
    val balanceYuan: Double? = null,
) {
    val isBanned: Boolean get() = status == "banned"
    val levelValue: Int get() = level ?: 1
    val coinsValue: Int get() = coins ?: 0
    val balanceYuanValue: Double get() = balanceYuan ?: (balanceCents ?: 0).toDouble() / 100
}

@kotlinx.serialization.Serializable
data class Quota(
    val valid: Boolean = false,
    val reason: String = "",
    val expired: Boolean = false,
    val overQuota: Boolean = false,
    val hasPlan: Boolean = false,
)

@kotlinx.serialization.Serializable
data class AuthResult(
    val token: String = "",
    val expiresIn: Int = 0,
    val user: AppUser = AppUser(),
)

/** 注册验证码（与 Web 端一致：主控返回明文码 + 签名 token） */
@kotlinx.serialization.Serializable
data class CaptchaPayload(
    val enabled: Boolean = false,
    val code: String = "",
    val token: String = "",
)

// MARK: - 服务器与线路

@kotlinx.serialization.Serializable
data class ServerNode(
    val id: Int = 0,
    val name: String = "",
    val address: String = "",
    val region: String? = null,
    val status: String = "",
    val onlineCount: Int = 0,
    val cpuUsage: Double = 0.0,
    val memUsage: Double = 0.0,
    val diskUsage: Double = 0.0,
    val load1: Double = 0.0,
    val ratio: Double = 0.0,
    val levelRequired: Int = 0,
    val levelOk: Boolean = false,
    val dcoEnabled: Boolean = false,
    // 实时速率（老版本主控可能不下发，缺失时按 0 处理，避免整表解析失败）
    val rxRate: Long? = null,
    val txRate: Long? = null,
    val usable: Boolean = false,
    val unusableReason: String = "",
    // IPv6 地址（v6 优先连接用，未配置则为空/缺失）
    val addressV6: String? = null,
    // 注：属性名必须与 SnakeCase 映射一致（has_ipv4 → hasIpv4），
    // 否则该字段会被静默忽略。
    val hasIpv4: Boolean? = null,
    val hasIpv6: Boolean? = null,
) {
    val rxRateValue: Long get() = rxRate ?: 0
    val txRateValue: Long get() = txRate ?: 0

    /** 用于展示的 IPv4 地址（未配置返回 null） */
    val displayIPv4: String? get() = address.trim().ifEmpty { null }

    /** 用于展示的 IPv6 地址（未配置返回 null） */
    val displayIPv6: String? get() = (addressV6 ?: "").trim().ifEmpty { null }

    /** 是否支持 IPv6（兼容老版本主控：缺失该字段时按 address_v6 是否有值判断） */
    val supportsIPv6: Boolean get() = hasIpv6 ?: (addressV6 ?: "").trim().isNotEmpty()

    /** 是否支持 IPv4（老主控默认支持） */
    val supportsIPv4: Boolean get() = hasIpv4 ?: address.trim().isNotEmpty()

    val statusText: String get() = when (status) {
        "online" -> "在线"
        "offline" -> "离线"
        // 未对接（未安装 Agent）的节点对用户统一按「离线」展示，不暴露安装状态
        "pending" -> "离线"
        "disabled" -> "已停用"
        else -> status
    }
}

@kotlinx.serialization.Serializable
data class VPNLine(
    val id: Int = 0,
    val name: String = "",
    val protocol: String = "",
    val port: Int = 0,
    val remark: String? = null,
    val category: String = "",
) {
    val protocolUpper: String get() = protocol.uppercase()
}

@kotlinx.serialization.Serializable
data class LinesPayload(
    val nodes: List<ServerNode> = emptyList(),
    val lines: List<VPNLine> = emptyList(),
    val level: Int = 0,
    val quota: Quota = Quota(),
    val speedLimitKbps: Int = 0,
    val deviceLimit: Int = 0,
    // 分类顺序（按管理后台排序下发；老版本主控可能不返回）
    val categories: List<String>? = null,
)

/** 线路配置文件内容（.ovpn 文本，由主控生成） */
@kotlinx.serialization.Serializable
data class LineConfig(
    val lineId: Int = 0,
    val lineName: String = "",
    val nodeId: Int = 0,
    val nodeName: String = "",
    val filename: String = "",
    val format: String = "",
    val content: String = "",
)

// MARK: - 用户中心

@kotlinx.serialization.Serializable
data class UserPlan(
    val id: Int = 0,
    val name: String = "",
    val description: String? = null,
    val priceCents: Int = 0,
    val durationDays: Int = 0,
    val trafficBytes: Long = 0,
    val speedLimitKbps: Int = 0,
    val deviceLimit: Int = 0,
    val isActive: Boolean = false,
)

@kotlinx.serialization.Serializable
data class TrafficSummary(
    val usedBytes: Long = 0,
    val limitBytes: Long = 0,
    val remainBytes: Long = 0,
    val percent: Double = 0.0,
)

@kotlinx.serialization.Serializable
data class OnlineSession(
    val sessionKey: String = "",
    val nodeId: Int = 0,
    val nodeName: String? = null,
    val clientIp: String = "",
    val virtualIp: String = "",
    val rxBytes: Long = 0,
    val txBytes: Long = 0,
    val connectedAt: String = "",
) {
    val id: String get() = sessionKey
}

@kotlinx.serialization.Serializable
data class UserCenterPayload(
    val user: AppUser = AppUser(),
    val plan: UserPlan? = null,
    val quota: Quota = Quota(),
    val traffic: TrafficSummary = TrafficSummary(),
    val onlineSessions: List<OnlineSession> = emptyList(),
    val serverTime: String = "",
)

@kotlinx.serialization.Serializable
data class TrafficDay(
    val day: String = "",
    val rxBytes: Long = 0,
    val txBytes: Long = 0,
    val totalBytes: Long = 0,
) {
    val id: String get() = day
}

@kotlinx.serialization.Serializable
data class TrafficPayload(
    val days: List<TrafficDay> = emptyList(),
    val totalBytes: Long = 0,
    val daysCount: Int = 0,
)

// MARK: - 套餐与订单

@kotlinx.serialization.Serializable
data class PlanItem(
    val id: Int = 0,
    val name: String = "",
    val description: String? = null,
    val priceCents: Int = 0,
    val durationDays: Int = 0,
    val trafficBytes: Long = 0,
    val speedLimitKbps: Int = 0,
    val deviceLimit: Int = 0,
    val isCurrent: Boolean = false,
    // 赠送等级（购买后解锁的服务器等级）
    val level: Int? = null,
    // 金币兑换所需金币，0 或空表示不可金币兑换
    val coinPrice: Int? = null,
    // 赠送金币
    val bonusCoins: Int? = null,
    val coinExchangeEnabled: Boolean? = null,
    val canExchange: Boolean? = null,
    val canUseBalance: Boolean? = null,
) {
    val coinPriceValue: Int get() = coinPrice ?: 0
    val bonusCoinsValue: Int get() = bonusCoins ?: 0
    val levelValue: Int get() = level ?: 1

    /**
     * 是否可用金币兑换：以主控下发的「是否支持兑换」为准
     * （余额不足时按钮仍展示，点击后提示还差多少金币）
     */
    val exchangeable: Boolean get() = coinExchangeEnabled ?: canExchange ?: (coinPriceValue > 0)
}

@kotlinx.serialization.Serializable
data class PlansPayload(
    val plans: List<PlanItem> = emptyList(),
    val purchaseEnabled: Boolean = false,
    val currencySymbol: String = "",
    val nodeOnline: Int = 0,
    val nodeTotal: Int = 0,
    val user: PlanUser? = null,
    // 站点可用支付方式（主控下发；老版本主控可能不返回，此时展示全部标准方式）
    val paymentMethods: List<String>? = null,
    // 可选支付接口（主控下发；先选接口再选该接口支持的支付方式）
    val paymentChannels: List<PaymentChannelItem>? = null,
) {
    @kotlinx.serialization.Serializable
    data class PlanUser(
        val level: Int = 0,
        val coins: Int = 0,
        val balanceCents: Int = 0,
        val balanceYuan: Double = 0.0,
    )
}

/** 支付接口（管理后台配置的启用中通道） */
@kotlinx.serialization.Serializable
data class PaymentChannelItem(
    val id: Int = 0,
    val name: String = "",
    // 该接口支持的支付方式（alipay / wxpay / qqpay）
    val methods: List<String>? = null,
)

@kotlinx.serialization.Serializable
data class OrderItem(
    val id: Int = 0,
    val orderNo: String = "",
    val planId: Int? = null,
    val planName: String? = null,
    val amountCents: Int = 0,
    val status: String = "",
    val paymentMethod: String? = null,
    val tradeNo: String? = null,
    val paidAt: String? = null,
    val createdAt: String = "",
    val expiresAt: String? = null,
    // 主控新版本下发：该订单当前是否还能继续支付
    val canPay: Boolean? = null,
    // 主控新版本下发：继续支付链接（复用原订单）
    val payUrl: String? = null,
) {
    val statusText: String get() = when (status) {
        "pending" -> "待支付"
        "paid" -> "已支付"
        "cancelled" -> "已取消"
        "expired" -> "已过期"
        "refunded" -> "已退款"
        else -> status
    }

    /** 兼容老版本主控（无 can_pay 字段）：待支付即视为可支付 */
    val payable: Boolean get() = canPay ?: (status == "pending" && remainingSeconds > 0)

    /** 剩余支付秒数（无有效期或已过期返回 0） */
    val remainingSeconds: Int get() {
        if (status != "pending" || expiresAt.isNullOrEmpty()) return 0
        val date = Format.parse(expiresAt) ?: return 0
        val seconds = Duration.between(Instant.now(), date).toMillis() / 1000.0
        return maxOf(0, round(seconds).toInt())
    }
}

@kotlinx.serialization.Serializable
data class OrdersPayload(
    val orders: List<OrderItem> = emptyList(),
    val total: Int = 0,
    val page: Int = 0,
    val pageSize: Int = 0,
)

@kotlinx.serialization.Serializable
data class CreateOrderPayload(
    val order: OrderBrief = OrderBrief(),
    val payUrl: String = "",
    val method: String = "",
    val needManual: Boolean = false,
    val message: String = "",
    // 金币全额兑换 / 余额全额抵扣时由主控直接发货
    val paid: Boolean? = null,
    val coins: Int? = null,
    val payableCents: Int? = null,
    val balanceUsedCents: Int? = null,
) {
    val paidValue: Boolean get() = paid ?: false

    @kotlinx.serialization.Serializable
    data class OrderBrief(
        val id: Int = 0,
        val orderNo: String = "",
        val amountCents: Int = 0,
        val status: String = "",
        val expiresAt: String? = null,
        val planName: String = "",
    )
}

// MARK: - 账号状态与通知

@kotlinx.serialization.Serializable
data class UserBlock(
    val blocked: Boolean = false,
    val reason: String = "",
    val blockedUntil: String? = null,
    val remainingMinutes: Int = 0,
)

@kotlinx.serialization.Serializable
data class StatusNotice(
    val code: String = "",
    val message: String = "",
    val at: String? = null,
) {
    /** 去重键：同一状态必须稳定，避免轮询重复弹窗 */
    val key: String get() = "$code|${at ?: ""}"
}

@kotlinx.serialization.Serializable
data class UserStatusPayload(
    val status: String? = null,
    val quota: Quota? = null,
    val block: UserBlock? = null,
    val recentKick: RecentKick? = null,
    val notice: StatusNotice? = null,
    val serverTime: String? = null,
) {
    @kotlinx.serialization.Serializable
    data class RecentKick(
        val at: String? = null,
    )
}

// MARK: - 公告 / 激活码 / 金币 / 反馈

@kotlinx.serialization.Serializable
data class Announcement(
    val id: Int = 0,
    val title: String = "",
    val content: String = "",
    val isTop: Boolean = false,
    val createdAt: String = "",
    val read: Boolean = false,
)

@kotlinx.serialization.Serializable
data class AnnouncementsPayload(
    val announcements: List<Announcement> = emptyList(),
    val unreadCount: Int = 0,
    val unreadIds: List<Int> = emptyList(),
)

@kotlinx.serialization.Serializable
data class ActivationRecord(
    val id: Int = 0,
    val code: String = "",
    val planName: String = "",
    val durationDays: Int = 0,
    val trafficBytes: Long = 0,
    val level: Int = 0,
    val batchNo: String = "",
    val usedAt: String? = null,
)

@kotlinx.serialization.Serializable
data class ActivationRecordsPayload(
    val records: List<ActivationRecord> = emptyList(),
)

@kotlinx.serialization.Serializable
data class ActivationPreview(
    val valid: Boolean = false,
    val message: String = "",
    val planName: String? = null,
    val durationDays: Int? = null,
    val trafficBytes: Long? = null,
    val level: Int? = null,
)

@kotlinx.serialization.Serializable
data class ActivationRedeemResult(
    val planName: String = "",
    val expiresAt: String? = null,
    val extend: Boolean = false,
    val durationDays: Int = 0,
    val trafficBytes: Long = 0,
)

@kotlinx.serialization.Serializable
data class CoinLog(
    val id: Int = 0,
    val amount: Int = 0,
    val balance: Int = 0,
    val reason: String = "",
    val refType: String = "",
    val createdAt: String = "",
)

@kotlinx.serialization.Serializable
data class CoinsPayload(
    val coins: Int = 0,
    val inviteCode: String = "",
    val inviteUrl: String = "",
    val inviteEnabled: Boolean = false,
    val inviteRewardCoins: Int = 0,
    val inviteeRewardCoins: Int = 0,
    val coinExchangeEnabled: Boolean = false,
    val registerCoins: Int = 0,
    val rechargeCoinsPerYuan: Int = 0,
    val logs: List<CoinLog> = emptyList(),
)

@kotlinx.serialization.Serializable
data class FeedbackItem(
    val id: Int = 0,
    val lineId: Int? = null,
    val lineName: String? = null,
    val nodeName: String? = null,
    val title: String = "",
    val content: String = "",
    val status: String = "",
    val reply: String = "",
    val createdAt: String = "",
    val handledAt: String? = null,
) {
    val statusText: String get() = when (status) {
        "pending" -> "待处理"
        "handled" -> "已处理"
        "rejected" -> "已驳回"
        else -> status
    }
}

@kotlinx.serialization.Serializable
data class FeedbackListPayload(
    val feedback: List<FeedbackItem> = emptyList(),
)

// MARK: - 简单结果

@kotlinx.serialization.Serializable
data class SimpleResult(
    val ok: Boolean? = null,
    val question: String? = null,
    val marked: Int? = null,
    val inviteCode: String? = null,
)