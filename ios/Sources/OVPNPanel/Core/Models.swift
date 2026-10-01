import Foundation

// MARK: - 通用

/// 主控统一响应包裹 { code, message, data }
struct Envelope<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
}

/// APP 端用户信息（对应主控 buildAppUserPayload）
struct AppUser: Decodable {
    let id: Int
    let username: String
    let email: String?
    let role: String
    let status: String
    let planId: Int?
    let planName: String?
    let planExpiresAt: String?
    let trafficLimitBytes: Int64
    let trafficUsedBytes: Int64
    let remainBytes: Int64
    let speedLimitKbps: Int
    let deviceLimit: Int

    var isBanned: Bool { status == "banned" }
}

struct Quota: Decodable {
    let valid: Bool
    let reason: String
    let expired: Bool
    let overQuota: Bool
    let hasPlan: Bool
}

struct AuthResult: Decodable {
    let token: String
    let expiresIn: Int
    let user: AppUser
}

/// 注册验证码（与 Web 端一致：主控返回明文码 + 签名 token）
struct CaptchaPayload: Decodable {
    let enabled: Bool
    let code: String
    let token: String
}

// MARK: - 服务器与线路

struct ServerNode: Decodable, Identifiable {
    let id: Int
    let name: String
    let address: String
    let region: String?
    let status: String
    let onlineCount: Int
    let cpuUsage: Double
    let memUsage: Double
    let diskUsage: Double
    let load1: Double
    let ratio: Double
    let levelRequired: Int
    let levelOk: Bool
    let dcoEnabled: Bool
    /// 实时速率（老版本主控可能不下发，缺失时按 0 处理，避免整表解析失败）
    let rxRate: Int64?
    let txRate: Int64?
    let usable: Bool
    let unusableReason: String

    var rxRateValue: Int64 { rxRate ?? 0 }
    var txRateValue: Int64 { txRate ?? 0 }

    var statusText: String {
        switch status {
        case "online": return "在线"
        case "offline": return "离线"
        case "pending": return "待安装"
        case "disabled": return "已停用"
        default: return status
        }
    }
}

struct VPNLine: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let `protocol`: String
    let port: Int
    let remark: String?
    let category: String

    var protocolUpper: String { `protocol`.uppercased() }
}

struct LinesPayload: Decodable {
    let nodes: [ServerNode]
    let lines: [VPNLine]
    let level: Int
    let quota: Quota
    let speedLimitKbps: Int
    let deviceLimit: Int
}

/// 线路配置文件内容（.ovpn 文本，由主控生成）
struct LineConfig: Decodable {
    let lineId: Int
    let lineName: String
    let nodeId: Int
    let nodeName: String
    let filename: String
    let format: String
    let content: String
}

// MARK: - 用户中心

struct UserPlan: Decodable {
    let id: Int
    let name: String
    let description: String?
    let priceCents: Int
    let durationDays: Int
    let trafficBytes: Int64
    let speedLimitKbps: Int
    let deviceLimit: Int
    let isActive: Bool
}

struct TrafficSummary: Decodable {
    let usedBytes: Int64
    let limitBytes: Int64
    let remainBytes: Int64
    let percent: Double
}

struct OnlineSession: Decodable, Identifiable {
    let sessionKey: String
    let nodeId: Int
    let nodeName: String?
    let clientIp: String
    let virtualIp: String
    let rxBytes: Int64
    let txBytes: Int64
    let connectedAt: String

    var id: String { sessionKey }
}

struct UserCenterPayload: Decodable {
    let user: AppUser
    let plan: UserPlan?
    let quota: Quota
    let traffic: TrafficSummary
    let onlineSessions: [OnlineSession]
    let serverTime: String
}

struct TrafficDay: Decodable, Identifiable {
    let day: String
    let rxBytes: Int64
    let txBytes: Int64
    let totalBytes: Int64

    var id: String { day }
}

struct TrafficPayload: Decodable {
    let days: [TrafficDay]
    let totalBytes: Int64
    let daysCount: Int
}

// MARK: - 套餐与订单

struct PlanItem: Decodable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let priceCents: Int
    let durationDays: Int
    let trafficBytes: Int64
    let speedLimitKbps: Int
    let deviceLimit: Int
    let isCurrent: Bool
}

struct PlansPayload: Decodable {
    let plans: [PlanItem]
    let purchaseEnabled: Bool
    let currencySymbol: String
    let nodeOnline: Int
    let nodeTotal: Int
}

struct OrderItem: Decodable, Identifiable {
    let id: Int
    let orderNo: String
    let planId: Int?
    let planName: String?
    let amountCents: Int
    let status: String
    let paymentMethod: String?
    let tradeNo: String?
    let paidAt: String?
    let createdAt: String
    let expiresAt: String?
    /// 主控新版本下发：该订单当前是否还能继续支付
    let canPay: Bool?
    /// 主控新版本下发：继续支付链接（复用原订单）
    let payUrl: String?

    var statusText: String {
        switch status {
        case "pending": return "待支付"
        case "paid": return "已支付"
        case "cancelled": return "已取消"
        case "expired": return "已过期"
        case "refunded": return "已退款"
        default: return status
        }
    }

    /// 兼容老版本主控（无 can_pay 字段）：待支付即视为可支付
    var payable: Bool {
        if let canPay { return canPay }
        return status == "pending" && remainingSeconds > 0
    }

    /// 剩余支付秒数（无有效期或已过期返回 0）
    var remainingSeconds: Int {
        guard status == "pending", let expiresAt, !expiresAt.isEmpty else { return 0 }
        guard let date = Format.parse(expiresAt) else { return 0 }
        return max(0, Int(date.timeIntervalSinceNow.rounded()))
    }
}

struct OrdersPayload: Decodable {
    let orders: [OrderItem]
    let total: Int
    let page: Int
    let pageSize: Int
}

struct CreateOrderPayload: Decodable {
    let order: OrderBrief
    let payUrl: String
    let method: String
    let needManual: Bool
    let message: String

    struct OrderBrief: Decodable {
        let id: Int
        let orderNo: String
        let amountCents: Int
        let status: String
        let expiresAt: String?
        let planName: String
    }
}

// MARK: - 公告 / 激活码 / 金币 / 反馈

struct Announcement: Decodable, Identifiable {
    let id: Int
    let title: String
    let content: String
    let isTop: Bool
    let createdAt: String
    let read: Bool
}

struct AnnouncementsPayload: Decodable {
    let announcements: [Announcement]
    let unreadCount: Int
    let unreadIds: [Int]
}

struct ActivationRecord: Decodable, Identifiable {
    let id: Int
    let code: String
    let planName: String
    let durationDays: Int
    let trafficBytes: Int64
    let level: Int
    let batchNo: String
    let usedAt: String?
}

struct ActivationRecordsPayload: Decodable {
    let records: [ActivationRecord]
}

struct ActivationPreview: Decodable {
    let valid: Bool
    let message: String
    let planName: String?
    let durationDays: Int?
    let trafficBytes: Int64?
    let level: Int?
}

struct ActivationRedeemResult: Decodable {
    let planName: String
    let expiresAt: String?
    let extend: Bool
    let durationDays: Int
    let trafficBytes: Int64
}

struct CoinLog: Decodable, Identifiable {
    let id: Int
    let amount: Int
    let balance: Int
    let reason: String
    let refType: String
    let createdAt: String
}

struct CoinsPayload: Decodable {
    let coins: Int
    let inviteCode: String
    let inviteUrl: String
    let inviteEnabled: Bool
    let inviteRewardCoins: Int
    let inviteeRewardCoins: Int
    let coinExchangeEnabled: Bool
    let registerCoins: Int
    let rechargeCoinsPerYuan: Int
    let logs: [CoinLog]
}

struct FeedbackItem: Decodable, Identifiable {
    let id: Int
    let lineId: Int?
    let lineName: String?
    let nodeName: String?
    let title: String
    let content: String
    let status: String
    let reply: String
    let createdAt: String
    let handledAt: String?

    var statusText: String {
        switch status {
        case "pending": return "待处理"
        case "handled": return "已处理"
        case "rejected": return "已驳回"
        default: return status
        }
    }
}

struct FeedbackListPayload: Decodable {
    let feedback: [FeedbackItem]
}

// MARK: - 简单结果

struct SimpleResult: Decodable {
    let ok: Bool?
    let question: String?
    let marked: Int?
    let inviteCode: String?
}

// MARK: - 展示辅助

enum Format {
    static func bytes(_ value: Int64) -> String {
        if value <= 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var size = Double(value)
        var index = 0
        while size >= 1024 && index < units.count - 1 {
            size /= 1024
            index += 1
        }
        let digits = size >= 100 || index == 0 ? 0 : (size >= 10 ? 1 : 2)
        return String(format: "%.\(digits)f %@", size, units[index])
    }

    static func money(_ cents: Int, symbol: String = "¥") -> String {
        String(format: "%@%.2f", symbol, Double(cents) / 100.0)
    }

    static func speed(_ kbps: Int) -> String {
        if kbps <= 0 { return "不限速" }
        if kbps >= 1024 { return String(format: "%.1f Mbps", Double(kbps) / 1024.0) }
        return "\(kbps) Kbps"
    }

    static func traffic(_ value: Int64) -> String {
        value <= 0 ? "不限量" : bytes(value)
    }

    /// ISO8601 → 简短本地时间
    static func dateTime(_ iso: String?) -> String {
        guard let date = parse(iso) else { return iso?.isEmpty == false ? (iso ?? "-") : "-" }
        let out = DateFormatter()
        out.dateFormat = "yyyy-MM-dd HH:mm"
        return out.string(from: date)
    }

    static func dateOnly(_ iso: String?) -> String {
        guard let date = parse(iso) else { return iso?.isEmpty == false ? (iso ?? "-") : "-" }
        let out = DateFormatter()
        out.dateFormat = "yyyy-MM-dd"
        return out.string(from: date)
    }

    /// ISO8601 字符串 → Date（兼容带/不带毫秒）
    static func parse(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
    }

    /// 秒数 → mm:ss（用于订单支付倒计时）
    static func countdown(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}