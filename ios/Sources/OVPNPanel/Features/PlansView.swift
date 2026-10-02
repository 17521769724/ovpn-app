import SwiftUI
import Combine

/// 套餐购买
struct PlansView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: PlansPayload?
    @State private var loading = true
    @State private var paying = false
    @State private var payURL: String?

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                if let payload, !payload.purchaseEnabled {
                    BannerBar(message: "站点当前已关闭购买功能", kind: .warning)
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
        .sheet(isPresented: Binding(
            get: { payURL != nil },
            set: { if !$0 { payURL = nil } }
        )) {
            if let payURL, let url = URL(string: payURL) {
                SafariSheet(url: url) { self.payURL = nil }
            }
        }
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
                            style: .secondary,
                            loading: paying
                        ) {
                            Task { await redeemWithCoins(plan: plan) }
                        }
                        AppButton(
                            title: "立即购买",
                            icon: "cart.fill",
                            style: .primary,
                            loading: paying,
                            disabled: !(payload?.purchaseEnabled ?? false)
                        ) {
                            Task { await buy(plan: plan) }
                        }
                    }
                } else {
                    AppButton(
                        title: "立即购买",
                        icon: "cart.fill",
                        style: .primary,
                        loading: paying,
                        disabled: !(payload?.purchaseEnabled ?? false)
                    ) {
                        Task { await buy(plan: plan) }
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

    private func buy(plan: PlanItem) async {
        paying = true
        defer { paying = false }
        do {
            let result = try await APIClient.shared.createOrder(planId: plan.id, method: "alipay")
            if result.paidValue {
                app.showToast(result.message.isEmpty ? "支付成功" : result.message, kind: .success)
                await app.refreshUser()
                await load()
            } else if result.payUrl.isEmpty {
                app.showToast(result.message.isEmpty ? "订单已创建，请联系管理员完成支付" : result.message, kind: .warning)
            } else {
                payURL = result.payUrl
                app.showToast("订单已创建，请在 10 分钟内完成支付", kind: .info)
            }
        } catch {
            app.report(error)
        }
    }

    /// 金币全额兑换（主控直接发货）
    private func redeemWithCoins(plan: PlanItem) async {
        guard plan.coinPriceValue > 0 else { return }
        guard (payload?.user?.coins ?? 0) >= plan.coinPriceValue else {
            app.showToast("金币不足，需要 \(plan.coinPriceValue) 金币", kind: .warning)
            return
        }
        paying = true
        defer { paying = false }
        do {
            let result = try await APIClient.shared.createOrder(planId: plan.id, method: "coins", useCoins: true)
            app.showToast(result.message.isEmpty ? "兑换成功" : result.message, kind: .success)
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
                            .buttonStyle(PressableStyle(scale: 0.97))
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
                        .buttonStyle(PressableStyle(scale: 0.97))
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
                app.showToast(result.message.isEmpty ? "订单已创建，请联系管理员完成支付" : result.message, kind: .warning)
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
            app.showToast("订单已取消", kind: .success)
            await load()
        } catch {
            app.report(error)
        }
    }
}