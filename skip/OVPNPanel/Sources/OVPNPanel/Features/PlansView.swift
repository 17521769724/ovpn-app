import SwiftUI
import Combine

/// 支付方式（易支付：alipay / wxpay / qqpay）
private struct PayOption: Identifiable {
    let id: String
    let name: String
    let icon: String
    let tint: Color

    static let all: [PayOption] = [
        PayOption(id: "alipay", name: "支付宝", icon: "a.circle.fill", tint: DS.IconColor.cyan),
        PayOption(id: "wxpay", name: "微信支付", icon: "message.fill", tint: DS.IconColor.green),
        PayOption(id: "qqpay", name: "QQ 钱包", icon: "q.circle.fill", tint: DS.IconColor.teal),
    ]
}

/// 已确认的支付请求：支付方式弹窗关闭后再创建订单，避免与 Safari 弹窗叠加冲突
private struct PendingPay {
    let plan: PlanItem
    let method: String
    /// 所选支付接口（余额抵扣时为 nil）
    let channelId: Int?
    /// 是否使用余额全额抵扣（此时不再携带支付方式与接口）
    let useBalance: Bool
}

/// 支付接口选项：管理后台配置的接口 + 「余额抵扣」选项
private struct PayTargetOption: Identifiable {
    let id: String        // "balance" 或 "channel:<id>"
    let name: String
    let detail: String
    let icon: String
    let tint: Color
    /// 不可选（如余额不足）
    let disabled: Bool
}

/// 构造支付接口选项列表（余额抵扣排在最后；余额不足时标记为不可选）
private func payTargetOptions(amountCents: Int, balanceCents: Int,
                              channels: [PaymentChannelItem]) -> [PayTargetOption] {
    var list: [PayTargetOption] = channels.map { channel in
        let names = (channel.methods ?? []).compactMap { id in
            PayOption.all.first { $0.id == id }?.name
        }
        return PayTargetOption(
            id: "channel:\(channel.id)",
            name: channel.name,
            detail: names.isEmpty ? "支持全部支付方式" : names.joined(separator: " / "),
            icon: "creditcard.fill",
            tint: DS.IconColor.cyan,
            disabled: false
        )
    }
    if amountCents > 0 {
        let enough = balanceCents >= amountCents
        list.append(PayTargetOption(
            id: "balance",
            name: "余额抵扣",
            detail: enough
                ? "使用账户余额全额支付，无需选择支付方式"
                : "余额不足，请先充值后再抵扣",
            icon: "wallet.pass.fill",
            tint: DS.IconColor.green,
            disabled: !enough
        ))
    }
    return list
}

/// 某支付接口支持的支付方式（未配置方式时兜底展示全部标准方式）
private func methodsForTarget(_ target: String, channels: [PaymentChannelItem]) -> [PayOption] {
    guard target.hasPrefix("channel:"),
          let id = Int(target.dropFirst("channel:".count)),
          let channel = channels.first(where: { $0.id == id }) else { return PayOption.all }
    let list = PayOption.all.filter { (channel.methods ?? []).contains($0.id) }
    return list.isEmpty ? PayOption.all : list
}

/// 套餐购买
struct PlansView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: PlansPayload?
    @State private var loading = true
    @State private var paying = false
    @State private var payURL: String?
    /// 正在选择付款方式的套餐（非空时弹出付款方式选择）
    @State private var pickerPlan: PlanItem?
    /// 所选支付接口（"balance" 表示余额抵扣）
    @State private var payTarget = ""
    @State private var selectedMethod = PayOption.all[0].id
    @State private var pendingPay: PendingPay?

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                if let payload, !payload.purchaseEnabled {
                    BannerBar(message: "站点当前已关闭购买功能", kind: BannerKind.warning)
                }

                if loading && payload == nil {
                    LoadingBlock(text: "正在获取套餐…")
                } else if let plans = payload?.plans, plans.isEmpty {
                    EmptyHint(icon: "shippingbox", title: "暂无可购买套餐", detail: "请联系管理员配置套餐")
                } else {
                    ForEach(payload?.plans ?? []) { plan in
                        planCard(palette, plan: plan)
                    }
                }
            }
            .padding(.horizontal, DS.Size.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .pageBackground()
        .navigationTitle("套餐中心")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable {
            Haptics.refresh()
            await load()
        }
        // 付款方式选择：确认后先关闭本弹窗，再创建订单并展示支付页
        .sheet(item: $pickerPlan, onDismiss: {
            guard let pending = pendingPay else { return }
            pendingPay = nil
            Task {
                await buy(plan: pending.plan, method: pending.method,
                          channelId: pending.channelId, useBalance: pending.useBalance)
            }
        }) { plan in
            paymentMethodSheet(palette, plan: plan)
        }
        .sheet(isPresented: Binding(
            get: { payURL != nil },
            set: { if !$0 { payURL = nil } }
        ), onDismiss: {
            // 支付页关闭后刷新一次：主控异步回调到账后，套餐状态即刻可见
            Task { await load() }
        }) {
            if let payURL, let url = URL(string: payURL) {
                SafariSheet(url: url) { self.payURL = nil }
            }
        }
    }

    /// 付款方式选择弹窗：先选支付接口（含余额抵扣），再选该接口支持的支付方式
    private func paymentMethodSheet(_ palette: Palette, plan: PlanItem) -> some View {
        let channels = payload?.paymentChannels ?? []
        let balanceCents = payload?.user?.balanceCents ?? 0
        let options = payTargetOptions(amountCents: plan.priceCents, balanceCents: balanceCents, channels: channels)
        let methods = methodsForTarget(payTarget, channels: channels)
        let useBalance = payTarget == "balance"
        let balanceEnough = plan.priceCents > 0 && balanceCents >= plan.priceCents
        // 无任何可用接口且余额不足：仅提示，不产生订单
        let canPay = useBalance ? balanceEnough : (!payTarget.isEmpty && !methods.isEmpty)

        return VStack(alignment: .leading, spacing: DS.Size.gap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("选择支付接口")
                    .font(DS.Font.section)
                    .foregroundStyle(palette.foreground)
                Text("\(plan.name) · 应付 \(Format.money(plan.priceCents, symbol: payload?.currencySymbol ?? "¥"))")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(palette.mutedForeground)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Size.gap) {
                    VStack(spacing: 8) {
                        ForEach(options) { option in
                            Button {
                                guard !option.disabled else { return }
                                payTarget = option.id
                                // 切换接口后，默认选中该接口的第一个可用支付方式
                                let available = methodsForTarget(option.id, channels: channels)
                                if !available.contains(where: { $0.id == selectedMethod }) {
                                    selectedMethod = available.first?.id ?? "alipay"
                                }
                            } label: {
                                targetRow(palette, option: option, selected: payTarget == option.id)
                            }
                            .pressableStyle(scale: 0.98)
                            .disabled(option.disabled)
                        }
                    }

                    if options.isEmpty {
                        BannerBar(message: "站点暂未配置支付接口，请联系管理员完成支付", kind: BannerKind.warning)
                    }

                    // 余额抵扣：不再展示支付方式选择
                    if useBalance {
                        Text("将使用账户余额全额支付 \(Format.money(plan.priceCents, symbol: payload?.currencySymbol ?? "¥"))，确认后立即开通套餐")
                            .font(DS.Font.caption)
                            .foregroundStyle(palette.mutedForeground)
                    } else if !methods.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("支付方式")
                                .font(DS.Font.bodySmall)
                                .foregroundStyle(palette.secondaryText)
                            HStack(spacing: 8) {
                                ForEach(methods) { option in
                                    Button {
                                        selectedMethod = option.id
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: option.icon)
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(option.name)
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                        .foregroundStyle(selectedMethod == option.id ? .white : palette.secondaryText)
                                        .padding(.horizontal, 12)
                                        .frame(height: 34)
                                        .background(selectedMethod == option.id ? palette.primary : palette.muted.opacity(0.6))
                                        .clipShape(Capsule())
                                    }
                                    .pressableStyle(scale: 0.96)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    if balanceCents > 0 && !balanceEnough {
                        Text("账户余额 ¥\(String(format: "%.2f", Double(balanceCents) / 100))，不足以全额抵扣本套餐，可先到「我的 → 余额充值」充值后再使用")
                            .font(DS.Font.caption)
                            .foregroundStyle(palette.mutedForeground)
                    }
                }
            }

            AppButton(
                title: paying
                    ? "正在创建订单…"
                    : "支付 \(Format.money(plan.priceCents, symbol: payload?.currencySymbol ?? "¥"))",
                icon: "creditcard.fill",
                style: AppButton.Style.primary,
                loading: paying,
                disabled: paying || !canPay
            ) {
                guard canPay else { return }
                let channelId: Int? = useBalance
                    ? nil
                    : Int(payTarget.dropFirst("channel:".count))
                pendingPay = PendingPay(plan: plan, method: selectedMethod,
                                        channelId: channelId, useBalance: useBalance)
                pickerPlan = nil
            }

            Text(useBalance
                 ? "确认后将直接从账户余额扣款并开通套餐"
                 : "点击支付后将打开内置浏览器，在支付页面完成付款")
                .font(DS.Font.caption)
                .foregroundStyle(palette.mutedForeground)
        }
        .padding(DS.Size.pagePadding)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // 默认选中第一个支付接口（没有接口时退回余额抵扣）
            let available = payTargetOptions(amountCents: plan.priceCents, balanceCents: balanceCents, channels: channels)
                .filter { !$0.disabled }
            if !available.contains(where: { $0.id == payTarget }) {
                payTarget = available.first?.id ?? ""
            }
            let methods = methodsForTarget(payTarget, channels: channels)
            if !methods.contains(where: { $0.id == selectedMethod }) {
                selectedMethod = methods.first?.id ?? "alipay"
            }
        }
    }

    /// 支付接口行（余额抵扣为其中一项）
    private func targetRow(_ palette: Palette, option: PayTargetOption, selected: Bool) -> some View {
        HStack(spacing: 10) {
            IconTile(icon: option.icon, color: option.disabled ? DS.IconColor.slate : option.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(option.name)
                    .font(DS.Font.body)
                    .foregroundStyle(option.disabled ? palette.mutedForeground : palette.foreground)
                Text(option.detail)
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.mutedForeground)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selected ? palette.primary : palette.mutedForeground.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(selected ? palette.primary.opacity(0.10) : palette.card)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(selected ? palette.primary : palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .opacity(option.disabled ? 0.6 : 1.0)
    }

    /// 账户概览（等级 / 金币 / 余额）已移至「我的」页面，此处不再重复展示

    private func planCard(_ palette: Palette, plan: PlanItem) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    HStack(spacing: 10) {
                        IconTile(icon: plan.isCurrent ? "checkmark.seal.fill" : "gift.fill",
                                 color: plan.isCurrent ? DS.IconColor.green : DS.IconColor.teal)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(plan.name).font(DS.Font.section).foregroundStyle(palette.foreground)
                                if plan.isCurrent {
                                    StatusBadge(text: "当前套餐", background: palette.onlineBg, foreground: palette.onlineText)
                                }
                            }
                            StatusBadge(text: "赠 Lv.\(plan.levelValue)",
                                        background: DS.IconColor.teal.opacity(0.14),
                                        foreground: DS.IconColor.teal)
                        }
                    }
                    Spacer()
                    Text(Format.money(plan.priceCents, symbol: payload?.currencySymbol ?? "¥"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.IconColor.orange)
                }

                VStack(spacing: 6) {
                    InfoRow(label: "时长", value: "\(plan.durationDays) 天")
                    InfoRow(label: "流量", value: Format.traffic(plan.trafficBytes))
                    InfoRow(label: "限速", value: Format.speed(plan.speedLimitKbps))
                    InfoRow(label: "设备数", value: plan.deviceLimit > 0 ? "\(plan.deviceLimit) 台" : "不限")
                    InfoRow(label: "赠送等级", value: "Lv.\(plan.levelValue) 等级")
                    if plan.bonusCoinsValue > 0 {
                        InfoRow(label: "赠送金币", value: "\(plan.bonusCoinsValue) 金币", valueColor: DS.IconColor.orange)
                    }
                }

                // 套餐备注：置于设备数等信息下方
                if let description = plan.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("备注").font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
                        Text(description)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }

                // 金币兑换与立即购买同一行显示
                if plan.exchangeable {
                    HStack(spacing: 10) {
                        AppButton(
                            title: "金币兑换 \(plan.coinPriceValue)",
                            icon: "bitcoinsign.circle.fill",
                            style: AppButton.Style.secondary,
                            loading: paying
                        ) {
                            Task { await redeemWithCoins(plan: plan) }
                        }
                        AppButton(
                            title: "立即购买",
                            icon: "cart.fill",
                            style: AppButton.Style.primary,
                            loading: paying,
                            disabled: !(payload?.purchaseEnabled ?? false)
                        ) {
                            pickerPlan = plan
                        }
                    }
                } else {
                    AppButton(
                        title: "立即购买",
                        icon: "cart.fill",
                        style: AppButton.Style.primary,
                        loading: paying,
                        disabled: !(payload?.purchaseEnabled ?? false)
                    ) {
                        pickerPlan = plan
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            payload = try await APIClient.shared.fetchPlans()
        } catch {
            if APIError.from(error).isCancelled { return }
            app.report(error)
        }
    }

    private func buy(plan: PlanItem, method: String, channelId: Int?, useBalance: Bool) async {
        paying = true
        defer { paying = false }
        do {
            let result = try await APIClient.shared.createOrder(
                planId: plan.id,
                method: method,
                payWithBalance: useBalance,
                channelId: channelId
            )
            if result.paidValue {
                app.showToast(result.message.isEmpty ? "支付成功" : result.message, kind: BannerKind.success)
                await app.refreshUser()
                await load()
            } else if result.payUrl.isEmpty {
                app.showToast(result.message.isEmpty ? "订单已创建，请联系管理员完成支付" : result.message, kind: BannerKind.warning)
            } else {
                payURL = result.payUrl
                app.showToast("订单已创建，请在 10 分钟内完成支付", kind: BannerKind.info)
            }
        } catch {
            app.report(error)
        }
    }

    /// 金币全额兑换（主控直接发货）
    private func redeemWithCoins(plan: PlanItem) async {
        guard plan.coinPriceValue > 0 else { return }
        guard (payload?.user?.coins ?? 0) >= plan.coinPriceValue else {
            app.showToast("金币不足，需要 \(plan.coinPriceValue) 金币", kind: BannerKind.warning)
            return
        }
        paying = true
        defer { paying = false }
        do {
            let result = try await APIClient.shared.createOrder(planId: plan.id, method: "coins", useCoins: true)
            app.showToast(result.message.isEmpty ? "兑换成功" : result.message, kind: BannerKind.success)
            await app.refreshUser()
            await load()
        } catch {
            app.report(error)
        }
    }
}

/// 我的订单（10 分钟支付窗口 + 继续支付 + 取消）
struct OrdersView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: OrdersPayload?
    @State private var loading = true
    @State private var payURL: String?
    @State private var busyId: Int?
    @State private var now = Date()
    @State private var refreshedExpired = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gap) {
                if loading && payload == nil {
                    LoadingBlock(text: "正在获取订单…")
                } else if (payload?.orders ?? []).isEmpty {
                    EmptyHint(icon: "doc.text", title: "暂无订单")
                } else {
                    ForEach(payload?.orders ?? []) { order in
                        orderCard(palette, order: order)
                    }
                }
            }
            .padding(DS.Size.pagePadding)
        }
        .pageBackground()
        .navigationTitle("我的订单")
        .navigationBarTitleDisplayMode(.large)
        .withBackLabel()
        .task { await load() }
        .refreshable {
            Haptics.refresh()
            await load()
        }
        .onReceive(ticker) { value in
            now = value
            // 有 pending 订单倒计时结束：自动刷新一次列表状态
            if !refreshedExpired,
               (payload?.orders ?? []).contains(where: { $0.status == "pending" && $0.remainingSeconds <= 1 }) {
                refreshedExpired = true
                Task { await load() }
            }
        }
        .sheet(isPresented: Binding(
            get: { payURL != nil },
            set: { if !$0 { payURL = nil } }
        )) {
            if let payURL, let url = URL(string: payURL) {
                SafariSheet(url: url) { self.payURL = nil }
            }
        }
    }

    private func orderCard(_ palette: Palette, order: OrderItem) -> some View {
        let remaining = remainingSeconds(order)
        return AppCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    IconTile(icon: orderIcon(order), color: orderColor(order))
                    Text(order.planName ?? "套餐").font(DS.Font.section)
                        .foregroundStyle(palette.foreground)
                    Spacer()
                    StatusBadge(
                        text: order.statusText,
                        background: statusBackground(palette, order: order),
                        foreground: statusForeground(palette, order: order)
                    )
                }
                InfoRow(label: "订单号", value: order.orderNo)
                InfoRow(label: "金额", value: Format.money(order.amountCents))
                InfoRow(label: "创建时间", value: Format.dateTime(order.createdAt))
                if let paidAt = order.paidAt {
                    InfoRow(label: "支付时间", value: Format.dateTime(paidAt))
                }
                if order.status == "pending" {
                    HStack {
                        Text("剩余支付时间").font(DS.Font.bodySmall).foregroundStyle(palette.mutedForeground)
                        Spacer()
                        if remaining > 0 {
                            Text(Format.countdown(remaining))
                                .font(DS.Font.number)
                                .foregroundStyle(DS.IconColor.amber)
                        } else {
                            Text("已过期")
                                .font(DS.Font.number)
                                .foregroundStyle(palette.offlineText)
                        }
                    }
                }

                if order.status == "pending" {
                    HStack(spacing: 10) {
                        if remaining > 0 {
                            Button {
                                Task { await pay(order) }
                            } label: {
                                HStack(spacing: 6) {
                                    if busyId == order.id {
                                        ProgressView().scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "creditcard.fill").font(.system(size: 13))
                                    }
                                    Text("继续支付").font(DS.Font.bodySmall)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .foregroundStyle(.white)
                                .background(DS.IconColor.green)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                            }
                            .pressableStyle(scale: 0.97)
                            .disabled(busyId != nil)
                        }
                        Button {
                            Task { await cancel(order) }
                        } label: {
                            Text("取消订单")
                                .font(DS.Font.bodySmall)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .foregroundStyle(palette.foreground)
                                .background(palette.card)
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg).stroke(palette.border, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                        }
                        .pressableStyle(scale: 0.97)
                        .disabled(busyId != nil)
                    }
                }
            }
        }
    }

    private func orderIcon(_ order: OrderItem) -> String {
        switch order.status {
        case "paid": return "checkmark.seal.fill"
        case "pending": return "clock.fill"
        case "cancelled": return "xmark.circle.fill"
        case "expired": return "hourglass"
        case "refunded": return "arrow.uturn.backward.circle.fill"
        default: return "doc.text.fill"
        }
    }

    private func orderColor(_ order: OrderItem) -> Color {
        switch order.status {
        case "paid": return DS.IconColor.green
        case "pending": return DS.IconColor.amber
        case "cancelled", "expired": return DS.IconColor.slate
        default: return DS.IconColor.cyan
        }
    }

    private func statusBackground(_ palette: Palette, order: OrderItem) -> Color {
        switch order.status {
        case "paid": return palette.onlineBg
        case "pending": return palette.warningBg
        default: return palette.muted
        }
    }

    private func statusForeground(_ palette: Palette, order: OrderItem) -> Color {
        switch order.status {
        case "paid": return palette.onlineText
        case "pending": return palette.warningText
        default: return palette.mutedForeground
        }
    }

    /// 按当前时间实时计算剩余秒数（每秒刷新）
    private func remainingSeconds(_ order: OrderItem) -> Int {
        guard order.status == "pending", let expiresAt = order.expiresAt,
              let date = Format.parse(expiresAt) else { return 0 }
        return max(0, Int(date.timeIntervalSince(now).rounded()))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            payload = try await APIClient.shared.fetchOrders()
            refreshedExpired = false
        } catch {
            if APIError.from(error).isCancelled { return }
            app.report(error)
        }
    }

    /// 继续支付（复用原订单，10 分钟内有效）
    private func pay(_ order: OrderItem) async {
        busyId = order.id
        defer { busyId = nil }
        do {
            let result = try await APIClient.shared.payOrder(id: order.id)
            if result.payUrl.isEmpty {
                app.showToast(result.message.isEmpty ? "订单已创建，请联系管理员完成支付" : result.message, kind: BannerKind.warning)
            } else {
                payURL = result.payUrl
            }
        } catch {
            app.report(error)
            await load()
        }
    }

    private func cancel(_ order: OrderItem) async {
        busyId = order.id
        defer { busyId = nil }
        do {
            try await APIClient.shared.cancelOrder(id: order.id)
            app.showToast("订单已取消", kind: BannerKind.success)
            await load()
        } catch {
            app.report(error)
        }
    }
}

/// 余额充值（个人中心 → 余额充值）：先选支付接口，再选该接口支持的支付方式，
/// 确认后在内置浏览器打开支付页面；到账后余额可用于购买套餐抵扣。
struct RechargeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: PlansPayload?
    @State private var loading = true
    @State private var amountText = "30"
    @State private var payTarget = ""
    @State private var selectedMethod = PayOption.all[0].id
    @State private var paying = false
    @State private var payURL: String?

    private let quickAmounts: [Double] = [10.0, 30.0, 50.0, 100.0, 200.0, 500.0]

    /// 快捷金额按每行 3 个分行（Skip 不支持自定义 Layout，两端统一使用等分换行）
    private var quickAmountRows: [[Double]] {
        var rows: [[Double]] = []
        var current: [Double] = []
        for value in quickAmounts {
            current.append(value)
            if current.count == 3 {
                rows.append(current)
                current = []
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private var amountYuan: Double { Double(amountText.trimmingCharacters(in: .whitespaces)) ?? 0.0 }

    var body: some View {
        let palette = Palette(scheme: scheme)
        let channels = payload?.paymentChannels ?? []
        // 充值场景不展示「余额抵扣」选项（amountCents 传 0）
        let options = payTargetOptions(amountCents: 0, balanceCents: 0, channels: channels)
        let methods = methodsForTarget(payTarget, channels: channels)
        let balanceCents = payload?.user?.balanceCents ?? 0

        return ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                if loading && payload == nil {
                    LoadingBlock(text: "正在获取充值信息…")
                } else {
                    // 余额概览
                    AppCard {
                        HStack(spacing: 12) {
                            IconTile(icon: "wallet.pass.fill", color: DS.IconColor.green, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("账户余额").font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
                                Text(Format.money(balanceCents, symbol: payload?.currencySymbol ?? "¥"))
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(palette.foreground)
                            }
                            Spacer()
                            StatusBadge(text: "可用于抵扣套餐",
                                        background: palette.onlineBg, foreground: palette.onlineText)
                        }
                    }

                    // 充值金额
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            AppTextField(title: "充值金额（元）", placeholder: "请输入充值金额（最少 1 元）",
                                         text: $amountText, keyboard: UIKeyboardType.decimalPad)
                            // 快捷金额：金额与单位同一行展示，每行 3 个（三端一致）
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(quickAmountRows.indices), id: \.self) { rowIndex in
                                    let rowValues = quickAmountRows[rowIndex]
                                    HStack(spacing: 8) {
                                        ForEach(rowValues, id: \.self) { value in
                                            let text = String(format: "%.0f", value)
                                            Button {
                                                amountText = text
                                            } label: {
                                                Text("\(text) 元")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .lineLimit(1)
                                                    .fixedSize()
                                                    .foregroundStyle(amountText == text ? .white : palette.secondaryText)
                                                    .padding(.horizontal, 12)
                                                    .frame(height: 32)
                                                    .background(amountText == text ? palette.primary : palette.muted.opacity(0.6))
                                                    .clipShape(Capsule())
                                            }
                                            .pressableStyle(scale: 0.96)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }

                    // 支付接口 + 支付方式
                    AppCard {
                        VStack(alignment: .leading, spacing: DS.Size.gap) {
                            Text("支付接口")
                                .font(DS.Font.bodySmall)
                                .foregroundStyle(palette.secondaryText)
                            if options.isEmpty {
                                BannerBar(message: "站点暂未配置支付接口，请联系管理员完成充值", kind: BannerKind.warning)
                            } else {
                                ForEach(options) { option in
                                    Button {
                                        payTarget = option.id
                                        let available = methodsForTarget(option.id, channels: channels)
                                        if !available.contains(where: { $0.id == selectedMethod }) {
                                            selectedMethod = available.first?.id ?? "alipay"
                                        }
                                    } label: {
                                        rechargeTargetRow(palette, option: option, selected: payTarget == option.id)
                                    }
                                    .pressableStyle(scale: 0.98)
                                }
                            }

                            if !methods.isEmpty && !payTarget.isEmpty {
                                Text("支付方式")
                                    .font(DS.Font.bodySmall)
                                    .foregroundStyle(palette.secondaryText)
                                    .padding(.top, 2)
                                HStack(spacing: 8) {
                                    ForEach(methods) { option in
                                        Button {
                                            selectedMethod = option.id
                                        } label: {
                                            HStack(spacing: 5) {
                                                Image(systemName: option.icon)
                                                    .font(.system(size: 12, weight: .semibold))
                                                Text(option.name)
                                                    .font(.system(size: 13, weight: .medium))
                                            }
                                            .foregroundStyle(selectedMethod == option.id ? .white : palette.secondaryText)
                                            .padding(.horizontal, 12)
                                            .frame(height: 34)
                                            .background(selectedMethod == option.id ? palette.primary : palette.muted.opacity(0.6))
                                            .clipShape(Capsule())
                                        }
                                        .pressableStyle(scale: 0.96)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }

                    AppButton(
                        title: paying ? "正在创建订单…" : "去支付 \(Format.money(Int((amountYuan * 100).rounded()), symbol: payload?.currencySymbol ?? "¥"))",
                        icon: "creditcard.fill",
                        style: AppButton.Style.primary,
                        loading: paying,
                        disabled: paying || amountYuan < 1 || payTarget.isEmpty
                    ) {
                        Task { await recharge() }
                    }

                    Text("充值成功后余额将实时到账，可在购买套餐时选择「余额抵扣」全额支付")
                        .font(DS.Font.caption)
                        .foregroundStyle(palette.mutedForeground)
                }
            }
            .padding(.horizontal, DS.Size.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .pageBackground()
        .navigationTitle("余额充值")
        .navigationBarTitleDisplayMode(.large)
        .withBackLabel()
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: Binding(
            get: { payURL != nil },
            set: { if !$0 { payURL = nil } }
        ), onDismiss: {
            // 支付页关闭后刷新余额（异步回调到账后即可见）
            Task {
                await app.refreshUser()
                await load()
            }
        }) {
            if let payURL, let url = URL(string: payURL) {
                SafariSheet(url: url) { self.payURL = nil }
            }
        }
        .onAppear {
            let available = payTargetOptions(amountCents: 0, balanceCents: 0,
                                             channels: payload?.paymentChannels ?? [])
            if !available.contains(where: { $0.id == payTarget }) {
                payTarget = available.first?.id ?? ""
            }
            let methods = methodsForTarget(payTarget, channels: payload?.paymentChannels ?? [])
            if !methods.contains(where: { $0.id == selectedMethod }) {
                selectedMethod = methods.first?.id ?? "alipay"
            }
        }
    }

    private func rechargeTargetRow(_ palette: Palette, option: PayTargetOption, selected: Bool) -> some View {
        HStack(spacing: 10) {
            IconTile(icon: option.icon, color: option.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(option.name).font(DS.Font.body).foregroundStyle(palette.foreground)
                Text(option.detail).font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
            }
            Spacer(minLength: 8)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selected ? palette.primary : palette.mutedForeground.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(selected ? palette.primary.opacity(0.10) : palette.card)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(selected ? palette.primary : palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let value = try await APIClient.shared.fetchPlans()
            payload = value
            // 首次加载后补默认选中（进入页面时还没拿到接口列表）
            let available = payTargetOptions(amountCents: 0, balanceCents: 0,
                                             channels: value.paymentChannels ?? [])
            if !available.contains(where: { $0.id == payTarget }) {
                payTarget = available.first?.id ?? ""
            }
            let methods = methodsForTarget(payTarget, channels: value.paymentChannels ?? [])
            if !methods.contains(where: { $0.id == selectedMethod }) {
                selectedMethod = methods.first?.id ?? "alipay"
            }
        } catch {
            if APIError.from(error).isCancelled { return }
            app.report(error)
        }
    }

    private func recharge() async {
        guard amountYuan >= 1 else {
            app.showToast("单次充值金额不得少于 1 元", kind: BannerKind.warning)
            return
        }
        guard !payTarget.isEmpty else {
            app.showToast("请选择支付接口", kind: BannerKind.warning)
            return
        }
        paying = true
        defer { paying = false }
        let channelId = Int(payTarget.dropFirst("channel:".count))
        do {
            let result = try await APIClient.shared.rechargeBalance(
                amountYuan: amountYuan, method: selectedMethod, channelId: channelId
            )
            if result.payUrl.isEmpty {
                app.showToast(result.message.isEmpty ? "订单已创建，请联系管理员完成支付" : result.message, kind: BannerKind.warning)
            } else {
                payURL = result.payUrl
                app.showToast("订单已创建，请在 10 分钟内完成支付", kind: BannerKind.info)
            }
        } catch {
            app.report(error)
        }
    }
}