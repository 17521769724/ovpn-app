using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace OVPNPanel.Core
{
    // MARK: - 通用

    /// <summary>APP 端用户信息（对应主控 buildAppUserPayload）</summary>
    public class AppUser
    {
        public int Id;
        public string Username = "";
        public string Email;
        public string Role = "";
        public string Status = "";
        public int? PlanId;
        public string PlanName;
        public string PlanExpiresAt;
        public long TrafficLimitBytes;
        public long TrafficUsedBytes;
        public long RemainBytes;
        public int SpeedLimitKbps;
        public int DeviceLimit;
        public int? Level;
        public int? Coins;
        public int? BalanceCents;
        public double? BalanceYuan;

        public bool IsBanned => Status == "banned";
        public int LevelValue => Level ?? 1;
        public int CoinsValue => Coins ?? 0;
        public double BalanceYuanValue => BalanceYuan ?? (BalanceCents ?? 0) / 100.0;

        public static AppUser From(Dictionary<string, object> d) => new AppUser
        {
            Id = J.Int(d, "id"),
            Username = J.Str(d, "username"),
            Email = J.OptStr(d, "email"),
            Role = J.Str(d, "role"),
            Status = J.Str(d, "status"),
            PlanId = J.OptInt(d, "plan_id"),
            PlanName = J.OptStr(d, "plan_name"),
            PlanExpiresAt = J.OptStr(d, "plan_expires_at"),
            TrafficLimitBytes = J.Long(d, "traffic_limit_bytes"),
            TrafficUsedBytes = J.Long(d, "traffic_used_bytes"),
            RemainBytes = J.Long(d, "remain_bytes"),
            SpeedLimitKbps = J.Int(d, "speed_limit_kbps"),
            DeviceLimit = J.Int(d, "device_limit"),
            Level = J.OptInt(d, "level"),
            Coins = J.OptInt(d, "coins"),
            BalanceCents = J.OptInt(d, "balance_cents"),
            BalanceYuan = J.OptLong(d, "balance_yuan") != null ? J.Dbl(d, "balance_yuan") : (double?)null,
        };
    }

    public class Quota
    {
        public bool Valid;
        public string Reason = "";
        public bool Expired;
        public bool OverQuota;
        public bool HasPlan;

        public static Quota From(Dictionary<string, object> d) => d == null ? null : new Quota
        {
            Valid = J.Bool(d, "valid"),
            Reason = J.Str(d, "reason"),
            Expired = J.Bool(d, "expired"),
            OverQuota = J.Bool(d, "over_quota"),
            HasPlan = J.Bool(d, "has_plan"),
        };
    }

    public class AuthResult
    {
        public string Token = "";
        public int ExpiresIn;
        public AppUser User;

        public static AuthResult From(Dictionary<string, object> d) => new AuthResult
        {
            Token = J.Str(d, "token"),
            ExpiresIn = J.Int(d, "expires_in"),
            User = AppUser.From(J.D(d, "user")),
        };
    }

    /// <summary>注册验证码（主控返回明文码 + 签名 token）</summary>
    public class CaptchaPayload
    {
        public bool Enabled;
        public string Code = "";
        public string Token = "";

        public static CaptchaPayload From(Dictionary<string, object> d) => new CaptchaPayload
        {
            Enabled = J.Bool(d, "enabled"),
            Code = J.Str(d, "code"),
            Token = J.Str(d, "token"),
        };
    }

    // MARK: - 服务器与线路

    public class ServerNode
    {
        public int Id;
        public string Name = "";
        public string Address = "";
        public string Region;
        public string Status = "";
        public int OnlineCount;
        public double CpuUsage;
        public double MemUsage;
        public double DiskUsage;
        public double Load1;
        public double Ratio;
        public int LevelRequired;
        public bool LevelOk;
        public bool DcoEnabled;
        public long? RxRate;
        public long? TxRate;
        public bool Usable;
        public string UnusableReason = "";
        public string AddressV6;
        public bool? HasIpv4;
        public bool? HasIpv6;

        public long RxRateValue => RxRate ?? 0;
        public long TxRateValue => TxRate ?? 0;

        public string DisplayIPv4 => string.IsNullOrWhiteSpace(Address) ? null : Address.Trim();

        public string DisplayIPv6
        {
            get
            {
                var value = (AddressV6 ?? "").Trim();
                return value.Length == 0 ? null : value;
            }
        }

        public bool SupportsIPv6
        {
            get
            {
                if (HasIpv6.HasValue) return HasIpv6.Value;
                return !string.IsNullOrWhiteSpace(AddressV6);
            }
        }

        public bool SupportsIPv4
        {
            get
            {
                if (HasIpv4.HasValue) return HasIpv4.Value;
                return !string.IsNullOrWhiteSpace(Address);
            }
        }

        public string StatusText
        {
            get
            {
                switch (Status)
                {
                    case "online": return "在线";
                    case "offline": return "离线";
                    case "pending": return "离线";
                    case "disabled": return "已停用";
                    default: return Status;
                }
            }
        }

        public static ServerNode From(Dictionary<string, object> d) => new ServerNode
        {
            Id = J.Int(d, "id"),
            Name = J.Str(d, "name"),
            Address = J.Str(d, "address"),
            Region = J.OptStr(d, "region"),
            Status = J.Str(d, "status"),
            OnlineCount = J.Int(d, "online_count"),
            CpuUsage = J.Dbl(d, "cpu_usage"),
            MemUsage = J.Dbl(d, "mem_usage"),
            DiskUsage = J.Dbl(d, "disk_usage"),
            Load1 = J.Dbl(d, "load1"),
            Ratio = J.Dbl(d, "ratio"),
            LevelRequired = J.Int(d, "level_required"),
            LevelOk = J.Bool(d, "level_ok"),
            DcoEnabled = J.Bool(d, "dco_enabled"),
            RxRate = J.OptLong(d, "rx_rate"),
            TxRate = J.OptLong(d, "tx_rate"),
            Usable = J.Bool(d, "usable"),
            UnusableReason = J.Str(d, "unusable_reason"),
            AddressV6 = J.OptStr(d, "address_v6"),
            HasIpv4 = J.OptBool(d, "has_ipv4"),
            HasIpv6 = J.OptBool(d, "has_ipv6"),
        };
    }

    public class VPNLine
    {
        public int Id;
        public string Name = "";
        public string Protocol = "";
        public int Port;
        public string Remark;
        public string Category = "";

        public string ProtocolUpper => (Protocol ?? "").ToUpperInvariant();

        public static VPNLine From(Dictionary<string, object> d) => new VPNLine
        {
            Id = J.Int(d, "id"),
            Name = J.Str(d, "name"),
            Protocol = J.Str(d, "protocol"),
            Port = J.Int(d, "port"),
            Remark = J.OptStr(d, "remark"),
            Category = J.Str(d, "category"),
        };
    }

    public class LinesPayload
    {
        public List<ServerNode> Nodes = new List<ServerNode>();
        public List<VPNLine> Lines = new List<VPNLine>();
        public int Level;
        public Quota Quota;
        public int SpeedLimitKbps;
        public int DeviceLimit;
        public List<string> Categories;

        public static LinesPayload From(Dictionary<string, object> d) => new LinesPayload
        {
            Nodes = J.MapList(J.A(d, "nodes"), ServerNode.From),
            Lines = J.MapList(J.A(d, "lines"), VPNLine.From),
            Level = J.Int(d, "level"),
            Quota = Quota.From(J.D(d, "quota")),
            SpeedLimitKbps = J.Int(d, "speed_limit_kbps"),
            DeviceLimit = J.Int(d, "device_limit"),
            Categories = J.A(d, "categories") == null ? null : J.A(d, "categories").ConvertAll(x => Convert.ToString(x)),
        };
    }

    /// <summary>线路配置文件内容（.ovpn 文本，由主控生成）</summary>
    public class LineConfig
    {
        public int LineId;
        public string LineName = "";
        public int NodeId;
        public string NodeName = "";
        public string Filename = "";
        public string Format = "";
        public string Content = "";

        public static LineConfig From(Dictionary<string, object> d) => new LineConfig
        {
            LineId = J.Int(d, "line_id"),
            LineName = J.Str(d, "line_name"),
            NodeId = J.Int(d, "node_id"),
            NodeName = J.Str(d, "node_name"),
            Filename = J.Str(d, "filename"),
            Format = J.Str(d, "format"),
            Content = J.Str(d, "content"),
        };
    }

    // MARK: - 用户中心

    public class UserPlan
    {
        public int Id;
        public string Name = "";
        public string Description;
        public int PriceCents;
        public int DurationDays;
        public long TrafficBytes;
        public int SpeedLimitKbps;
        public int DeviceLimit;
        public bool IsActive;

        public static UserPlan From(Dictionary<string, object> d) => d == null ? null : new UserPlan
        {
            Id = J.Int(d, "id"),
            Name = J.Str(d, "name"),
            Description = J.OptStr(d, "description"),
            PriceCents = J.Int(d, "price_cents"),
            DurationDays = J.Int(d, "duration_days"),
            TrafficBytes = J.Long(d, "traffic_bytes"),
            SpeedLimitKbps = J.Int(d, "speed_limit_kbps"),
            DeviceLimit = J.Int(d, "device_limit"),
            IsActive = J.Bool(d, "is_active"),
        };
    }

    public class TrafficSummary
    {
        public long UsedBytes;
        public long LimitBytes;
        public long RemainBytes;
        public double Percent;

        public static TrafficSummary From(Dictionary<string, object> d) => d == null ? null : new TrafficSummary
        {
            UsedBytes = J.Long(d, "used_bytes"),
            LimitBytes = J.Long(d, "limit_bytes"),
            RemainBytes = J.Long(d, "remain_bytes"),
            Percent = J.Dbl(d, "percent"),
        };
    }

    public class OnlineSession
    {
        public string SessionKey = "";
        public int NodeId;
        public string NodeName;
        public string ClientIp = "";
        public string VirtualIp = "";
        public long RxBytes;
        public long TxBytes;
        public string ConnectedAt = "";

        public static OnlineSession From(Dictionary<string, object> d) => new OnlineSession
        {
            SessionKey = J.Str(d, "session_key"),
            NodeId = J.Int(d, "node_id"),
            NodeName = J.OptStr(d, "node_name"),
            ClientIp = J.Str(d, "client_ip"),
            VirtualIp = J.Str(d, "virtual_ip"),
            RxBytes = J.Long(d, "rx_bytes"),
            TxBytes = J.Long(d, "tx_bytes"),
            ConnectedAt = J.Str(d, "connected_at"),
        };
    }

    public class UserCenterPayload
    {
        public AppUser User;
        public UserPlan Plan;
        public Quota Quota;
        public TrafficSummary Traffic;
        public List<OnlineSession> OnlineSessions = new List<OnlineSession>();
        public string ServerTime = "";

        public static UserCenterPayload From(Dictionary<string, object> d) => new UserCenterPayload
        {
            User = AppUser.From(J.D(d, "user")),
            Plan = UserPlan.From(J.D(d, "plan")),
            Quota = Quota.From(J.D(d, "quota")),
            Traffic = TrafficSummary.From(J.D(d, "traffic")),
            OnlineSessions = J.MapList(J.A(d, "online_sessions"), OnlineSession.From),
            ServerTime = J.Str(d, "server_time"),
        };
    }

    public class TrafficDay
    {
        public string Day = "";
        public long RxBytes;
        public long TxBytes;
        public long TotalBytes;

        public static TrafficDay From(Dictionary<string, object> d) => new TrafficDay
        {
            Day = J.Str(d, "day"),
            RxBytes = J.Long(d, "rx_bytes"),
            TxBytes = J.Long(d, "tx_bytes"),
            TotalBytes = J.Long(d, "total_bytes"),
        };
    }

    public class TrafficPayload
    {
        public List<TrafficDay> Days = new List<TrafficDay>();
        public long TotalBytes;
        public int DaysCount;

        public static TrafficPayload From(Dictionary<string, object> d) => new TrafficPayload
        {
            Days = J.MapList(J.A(d, "days"), TrafficDay.From),
            TotalBytes = J.Long(d, "total_bytes"),
            DaysCount = J.Int(d, "days_count"),
        };
    }

    // MARK: - 套餐与订单

    public class PlanItem
    {
        public int Id;
        public string Name = "";
        public string Description;
        public int PriceCents;
        public int DurationDays;
        public long TrafficBytes;
        public int SpeedLimitKbps;
        public int DeviceLimit;
        public bool IsCurrent;
        public int? Level;
        public int? CoinPrice;
        public int? BonusCoins;
        public bool? CoinExchangeEnabled;
        public bool? CanExchange;
        public bool? CanUseBalance;

        public int CoinPriceValue => CoinPrice ?? 0;
        public int BonusCoinsValue => BonusCoins ?? 0;
        public int LevelValue => Level ?? 1;

        public bool Exchangeable
        {
            get
            {
                if (CoinExchangeEnabled.HasValue) return CoinExchangeEnabled.Value;
                if (CanExchange.HasValue) return CanExchange.Value;
                return CoinPriceValue > 0;
            }
        }

        public static PlanItem From(Dictionary<string, object> d) => new PlanItem
        {
            Id = J.Int(d, "id"),
            Name = J.Str(d, "name"),
            Description = J.OptStr(d, "description"),
            PriceCents = J.Int(d, "price_cents"),
            DurationDays = J.Int(d, "duration_days"),
            TrafficBytes = J.Long(d, "traffic_bytes"),
            SpeedLimitKbps = J.Int(d, "speed_limit_kbps"),
            DeviceLimit = J.Int(d, "device_limit"),
            IsCurrent = J.Bool(d, "is_current"),
            Level = J.OptInt(d, "level"),
            CoinPrice = J.OptInt(d, "coin_price"),
            BonusCoins = J.OptInt(d, "bonus_coins"),
            CoinExchangeEnabled = J.OptBool(d, "coin_exchange_enabled"),
            CanExchange = J.OptBool(d, "can_exchange"),
            CanUseBalance = J.OptBool(d, "can_use_balance"),
        };
    }

    public class PlanUser
    {
        public int Level;
        public int Coins;
        public int BalanceCents;
        public double BalanceYuan;

        public static PlanUser From(Dictionary<string, object> d) => d == null ? null : new PlanUser
        {
            Level = J.Int(d, "level"),
            Coins = J.Int(d, "coins"),
            BalanceCents = J.Int(d, "balance_cents"),
            BalanceYuan = J.Dbl(d, "balance_yuan"),
        };
    }

    public class PlansPayload
    {
        public List<PlanItem> Plans = new List<PlanItem>();
        public bool PurchaseEnabled;
        public string CurrencySymbol = "¥";
        public int NodeOnline;
        public int NodeTotal;
        public PlanUser User;
        public List<string> PaymentMethods;
        public List<PaymentChannelItem> PaymentChannels;

        public static PlansPayload From(Dictionary<string, object> d) => new PlansPayload
        {
            Plans = J.MapList(J.A(d, "plans"), PlanItem.From),
            PurchaseEnabled = J.Bool(d, "purchase_enabled"),
            CurrencySymbol = J.Str(d, "currency_symbol", "¥"),
            NodeOnline = J.Int(d, "node_online"),
            NodeTotal = J.Int(d, "node_total"),
            User = PlanUser.From(J.D(d, "user")),
            PaymentMethods = J.A(d, "payment_methods") == null ? null : J.A(d, "payment_methods").ConvertAll(x => Convert.ToString(x)),
            PaymentChannels = J.MapList(J.A(d, "payment_channels"), PaymentChannelItem.From),
        };
    }

    /// <summary>支付接口（管理后台配置的启用中通道）</summary>
    public class PaymentChannelItem
    {
        public int Id;
        public string Name = "";
        public List<string> Methods;

        public static PaymentChannelItem From(Dictionary<string, object> d) => new PaymentChannelItem
        {
            Id = J.Int(d, "id"),
            Name = J.Str(d, "name"),
            Methods = J.A(d, "methods") == null ? null : J.A(d, "methods").ConvertAll(x => Convert.ToString(x)),
        };
    }

    public class OrderItem
    {
        public int Id;
        public string OrderNo = "";
        public int? PlanId;
        public string PlanName;
        public int AmountCents;
        public string Status = "";
        public string PaymentMethod;
        public string TradeNo;
        public string PaidAt;
        public string CreatedAt = "";
        public string ExpiresAt;
        public bool? CanPay;
        public string PayUrl;

        public string StatusText
        {
            get
            {
                switch (Status)
                {
                    case "pending": return "待支付";
                    case "paid": return "已支付";
                    case "cancelled": return "已取消";
                    case "expired": return "已过期";
                    case "refunded": return "已退款";
                    default: return Status;
                }
            }
        }

        public bool Payable
        {
            get
            {
                if (CanPay.HasValue) return CanPay.Value;
                return Status == "pending" && RemainingSeconds > 0;
            }
        }

        public int RemainingSeconds
        {
            get
            {
                if (Status != "pending" || string.IsNullOrEmpty(ExpiresAt)) return 0;
                var date = Format.Parse(ExpiresAt);
                if (date == null) return 0;
                return Math.Max(0, (int)Math.Round((date.Value - DateTime.Now).TotalSeconds));
            }
        }

        public static OrderItem From(Dictionary<string, object> d) => new OrderItem
        {
            Id = J.Int(d, "id"),
            OrderNo = J.Str(d, "order_no"),
            PlanId = J.OptInt(d, "plan_id"),
            PlanName = J.OptStr(d, "plan_name"),
            AmountCents = J.Int(d, "amount_cents"),
            Status = J.Str(d, "status"),
            PaymentMethod = J.OptStr(d, "payment_method"),
            TradeNo = J.OptStr(d, "trade_no"),
            PaidAt = J.OptStr(d, "paid_at"),
            CreatedAt = J.Str(d, "created_at"),
            ExpiresAt = J.OptStr(d, "expires_at"),
            CanPay = J.OptBool(d, "can_pay"),
            PayUrl = J.OptStr(d, "pay_url"),
        };
    }

    public class OrdersPayload
    {
        public List<OrderItem> Orders = new List<OrderItem>();
        public int Total;
        public int Page;
        public int PageSize;

        public static OrdersPayload From(Dictionary<string, object> d) => new OrdersPayload
        {
            Orders = J.MapList(J.A(d, "orders"), OrderItem.From),
            Total = J.Int(d, "total"),
            Page = J.Int(d, "page"),
            PageSize = J.Int(d, "page_size", 20),
        };
    }

    public class OrderBrief
    {
        public int Id;
        public string OrderNo = "";
        public int AmountCents;
        public string Status = "";
        public string ExpiresAt;
        public string PlanName = "";

        public static OrderBrief From(Dictionary<string, object> d) => d == null ? null : new OrderBrief
        {
            Id = J.Int(d, "id"),
            OrderNo = J.Str(d, "order_no"),
            AmountCents = J.Int(d, "amount_cents"),
            Status = J.Str(d, "status"),
            ExpiresAt = J.OptStr(d, "expires_at"),
            PlanName = J.Str(d, "plan_name"),
        };
    }

    public class CreateOrderPayload
    {
        public OrderBrief Order;
        public string PayUrl = "";
        public string Method = "";
        public bool NeedManual;
        public string Message = "";
        public bool? Paid;
        public int? Coins;
        public int? PayableCents;
        public int? BalanceUsedCents;

        public bool PaidValue => Paid ?? false;

        public static CreateOrderPayload From(Dictionary<string, object> d) => new CreateOrderPayload
        {
            Order = OrderBrief.From(J.D(d, "order")),
            PayUrl = J.Str(d, "pay_url"),
            Method = J.Str(d, "method"),
            NeedManual = J.Bool(d, "need_manual"),
            Message = J.Str(d, "message"),
            Paid = J.OptBool(d, "paid"),
            Coins = J.OptInt(d, "coins"),
            PayableCents = J.OptInt(d, "payable_cents"),
            BalanceUsedCents = J.OptInt(d, "balance_used_cents"),
        };
    }

    // MARK: - 账号状态与通知

    public class UserBlock
    {
        public bool Blocked;
        public string Reason = "";
        public string BlockedUntil;
        public int RemainingMinutes;

        public static UserBlock From(Dictionary<string, object> d) => d == null ? null : new UserBlock
        {
            Blocked = J.Bool(d, "blocked"),
            Reason = J.Str(d, "reason"),
            BlockedUntil = J.OptStr(d, "blocked_until"),
            RemainingMinutes = J.Int(d, "remaining_minutes"),
        };
    }

    public class StatusNotice
    {
        public string Code = "";
        public string Message = "";
        public string At;

        public string Key => Code + "|" + (At ?? "");

        public static StatusNotice From(Dictionary<string, object> d) => d == null ? null : new StatusNotice
        {
            Code = J.Str(d, "code"),
            Message = J.Str(d, "message"),
            At = J.OptStr(d, "at"),
        };
    }

    public class UserStatusPayload
    {
        public string Status;
        public Quota Quota;
        public UserBlock Block;
        public string RecentKickAt;
        public StatusNotice Notice;
        public string ServerTime;

        public static UserStatusPayload From(Dictionary<string, object> d)
        {
            var kick = J.D(d, "recent_kick");
            return new UserStatusPayload
            {
                Status = J.OptStr(d, "status"),
                Quota = Quota.From(J.D(d, "quota")),
                Block = UserBlock.From(J.D(d, "block")),
                RecentKickAt = kick == null ? null : J.OptStr(kick, "at"),
                Notice = StatusNotice.From(J.D(d, "notice")),
                ServerTime = J.OptStr(d, "server_time"),
            };
        }
    }

    // MARK: - 公告 / 激活码 / 金币 / 反馈

    public class Announcement
    {
        public int Id;
        public string Title = "";
        public string Content = "";
        public bool IsTop;
        public string CreatedAt = "";
        public bool Read;

        public static Announcement From(Dictionary<string, object> d) => new Announcement
        {
            Id = J.Int(d, "id"),
            Title = J.Str(d, "title"),
            Content = J.Str(d, "content"),
            IsTop = J.Bool(d, "is_top"),
            CreatedAt = J.Str(d, "created_at"),
            Read = J.Bool(d, "read"),
        };
    }

    public class AnnouncementsPayload
    {
        public List<Announcement> Announcements = new List<Announcement>();
        public int UnreadCount;
        public List<int> UnreadIds = new List<int>();

        public static AnnouncementsPayload From(Dictionary<string, object> d) => new AnnouncementsPayload
        {
            Announcements = J.MapList(J.A(d, "announcements"), Announcement.From),
            UnreadCount = J.Int(d, "unread_count"),
            UnreadIds = J.A(d, "unread_ids") == null
                ? new List<int>()
                : J.A(d, "unread_ids").ConvertAll(x => (int)Convert.ToInt64(x)),
        };
    }

    public class ActivationRecord
    {
        public int Id;
        public string Code = "";
        public string PlanName = "";
        public int DurationDays;
        public long TrafficBytes;
        public int Level;
        public string BatchNo = "";
        public string UsedAt;

        public static ActivationRecord From(Dictionary<string, object> d) => new ActivationRecord
        {
            Id = J.Int(d, "id"),
            Code = J.Str(d, "code"),
            PlanName = J.Str(d, "plan_name"),
            DurationDays = J.Int(d, "duration_days"),
            TrafficBytes = J.Long(d, "traffic_bytes"),
            Level = J.Int(d, "level"),
            BatchNo = J.Str(d, "batch_no"),
            UsedAt = J.OptStr(d, "used_at"),
        };
    }

    public class ActivationPreview
    {
        public bool Valid;
        public string Message = "";
        public string PlanName;
        public int? DurationDays;
        public long? TrafficBytes;
        public int? Level;

        public static ActivationPreview From(Dictionary<string, object> d) => new ActivationPreview
        {
            Valid = J.Bool(d, "valid"),
            Message = J.Str(d, "message"),
            PlanName = J.OptStr(d, "plan_name"),
            DurationDays = J.OptInt(d, "duration_days"),
            TrafficBytes = J.OptLong(d, "traffic_bytes"),
            Level = J.OptInt(d, "level"),
        };
    }

    public class ActivationRedeemResult
    {
        public string PlanName = "";
        public string ExpiresAt;
        public bool Extend;
        public int DurationDays;
        public long TrafficBytes;

        public static ActivationRedeemResult From(Dictionary<string, object> d) => new ActivationRedeemResult
        {
            PlanName = J.Str(d, "plan_name"),
            ExpiresAt = J.OptStr(d, "expires_at"),
            Extend = J.Bool(d, "extend"),
            DurationDays = J.Int(d, "duration_days"),
            TrafficBytes = J.Long(d, "traffic_bytes"),
        };
    }

    public class CoinLog
    {
        public int Id;
        public int Amount;
        public int Balance;
        public string Reason = "";
        public string RefType = "";
        public string CreatedAt = "";

        public static CoinLog From(Dictionary<string, object> d) => new CoinLog
        {
            Id = J.Int(d, "id"),
            Amount = J.Int(d, "amount"),
            Balance = J.Int(d, "balance"),
            Reason = J.Str(d, "reason"),
            RefType = J.Str(d, "ref_type"),
            CreatedAt = J.Str(d, "created_at"),
        };
    }

    public class CoinsPayload
    {
        public int Coins;
        public string InviteCode = "";
        public string InviteUrl = "";
        public bool InviteEnabled;
        public int InviteRewardCoins;
        public int InviteeRewardCoins;
        public bool CoinExchangeEnabled;
        public int RegisterCoins;
        public int RechargeCoinsPerYuan;
        public List<CoinLog> Logs = new List<CoinLog>();

        public static CoinsPayload From(Dictionary<string, object> d) => new CoinsPayload
        {
            Coins = J.Int(d, "coins"),
            InviteCode = J.Str(d, "invite_code"),
            InviteUrl = J.Str(d, "invite_url"),
            InviteEnabled = J.Bool(d, "invite_enabled"),
            InviteRewardCoins = J.Int(d, "invite_reward_coins"),
            InviteeRewardCoins = J.Int(d, "invitee_reward_coins"),
            CoinExchangeEnabled = J.Bool(d, "coin_exchange_enabled"),
            RegisterCoins = J.Int(d, "register_coins"),
            RechargeCoinsPerYuan = J.Int(d, "recharge_coins_per_yuan"),
            Logs = J.MapList(J.A(d, "logs"), CoinLog.From),
        };
    }

    public class FeedbackItem
    {
        public int Id;
        public int? LineId;
        public string LineName;
        public string NodeName;
        public string Title = "";
        public string Content = "";
        public string Status = "";
        public string Reply = "";
        public string CreatedAt = "";
        public string HandledAt;

        public string StatusText
        {
            get
            {
                switch (Status)
                {
                    case "pending": return "待处理";
                    case "handled": return "已处理";
                    case "rejected": return "已驳回";
                    default: return Status;
                }
            }
        }

        public static FeedbackItem From(Dictionary<string, object> d) => new FeedbackItem
        {
            Id = J.Int(d, "id"),
            LineId = J.OptInt(d, "line_id"),
            LineName = J.OptStr(d, "line_name"),
            NodeName = J.OptStr(d, "node_name"),
            Title = J.Str(d, "title"),
            Content = J.Str(d, "content"),
            Status = J.Str(d, "status"),
            Reply = J.Str(d, "reply"),
            CreatedAt = J.Str(d, "created_at"),
            HandledAt = J.OptStr(d, "handled_at"),
        };
    }

    public class FeedbackListPayload
    {
        public List<FeedbackItem> Feedback = new List<FeedbackItem>();

        public static FeedbackListPayload From(Dictionary<string, object> d) => new FeedbackListPayload
        {
            Feedback = J.MapList(J.A(d, "feedback"), FeedbackItem.From),
        };
    }

    /// <summary>简单结果</summary>
    public class SimpleResult
    {
        public bool? Ok;
        public string Question;
        public int? Marked;
        public string InviteCode;

        public static SimpleResult From(Dictionary<string, object> d) => new SimpleResult
        {
            Ok = J.OptBool(d, "ok"),
            Question = J.OptStr(d, "question"),
            Marked = J.OptInt(d, "marked"),
            InviteCode = J.OptStr(d, "invite_code"),
        };
    }

    // MARK: - 展示辅助

    public static class Format
    {
        public static string Bytes(long value)
        {
            if (value <= 0) return "0 B";
            var units = new[] { "B", "KB", "MB", "GB", "TB", "PB" };
            double size = value;
            int index = 0;
            while (size >= 1024 && index < units.Length - 1) { size /= 1024; index++; }
            int digits = size >= 100 || index == 0 ? 0 : (size >= 10 ? 1 : 2);
            return size.ToString("F" + digits, CultureInfo.InvariantCulture) + " " + units[index];
        }

        public static string Money(int cents, string symbol = "¥")
        {
            return symbol + (cents / 100.0).ToString("F2", CultureInfo.InvariantCulture);
        }

        public static string Speed(int kbps)
        {
            if (kbps <= 0) return "不限速";
            if (kbps >= 1024) return (kbps / 1024.0).ToString("F1", CultureInfo.InvariantCulture) + " Mbps";
            return kbps + " Kbps";
        }

        /// <summary>实时速率（字节/秒 → 可读文本）</summary>
        public static string SpeedValue(double bytesPerSecond)
        {
            if (bytesPerSecond <= 1) return "0 KB/s";
            var units = new[] { "B/s", "KB/s", "MB/s", "GB/s" };
            double value = bytesPerSecond;
            int index = 0;
            while (value >= 1024 && index < units.Length - 1) { value /= 1024; index++; }
            int digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
            return value.ToString("F" + digits, CultureInfo.InvariantCulture) + " " + units[index];
        }

        public static string Traffic(long value)
        {
            return value <= 0 ? "不限量" : Bytes(value);
        }

        public static string DateTimeText(string iso)
        {
            var date = Parse(iso);
            if (date == null) return string.IsNullOrEmpty(iso) ? "-" : iso;
            return date.Value.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
        }

        public static string DateOnly(string iso)
        {
            var date = Parse(iso);
            if (date == null) return string.IsNullOrEmpty(iso) ? "-" : iso;
            return date.Value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        }

        /// <summary>ISO8601 字符串 → 本地时间（兼容带/不带毫秒、带/不带时区）</summary>
        public static DateTime? Parse(string iso)
        {
            if (string.IsNullOrEmpty(iso)) return null;
            DateTime parsed;
            if (DateTime.TryParse(iso, CultureInfo.InvariantCulture,
                    DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out parsed))
            {
                return parsed.ToLocalTime();
            }
            return null;
        }

        /// <summary>秒数 → mm:ss</summary>
        public static string Countdown(int seconds)
        {
            int value = Math.Max(0, seconds);
            return (value / 60).ToString("D2") + ":" + (value % 60).ToString("D2");
        }

        /// <summary>已连接时长 → 时分秒</summary>
        public static string Duration(TimeSpan span)
        {
            if (span.TotalHours >= 1)
                return string.Format("{0:D2}:{1:D2}:{2:D2}", (int)span.TotalHours, span.Minutes, span.Seconds);
            return string.Format("{0:D2}:{1:D2}", span.Minutes, span.Seconds);
        }
    }
}
