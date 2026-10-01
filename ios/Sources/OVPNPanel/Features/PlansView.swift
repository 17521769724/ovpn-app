import SwiftUI

/// 套餐购买
struct PlansView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: PlansPayload?
    @State private var loading = true
    @State private var error = ""
    @State private var paying = false
    @State private var payURL: String?
    @State private var payMessage = ""

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("套餐中心").font(DS.Font.title).foregroundStyle(palette.foreground)
                        Text("节点在线 \(payload?.nodeOnline ?? 0)/\(payload?.nodeTotal ?? 0)")
                            .font(DS.Font.caption)
                            .foregroundStyle(palette.mutedForeground)
                    }
                    Spacer()
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.foreground)
                            .frame(width: 34, height: 34)
                            .background(palette.card)
                            .overlay(Circle().stroke(palette.border, lineWidth: 1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if !error.isEmpty { BannerBar(message: error) }
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

                NavigationLink {
                    OrdersView().environmentObject(app)
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("我的订单")
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12))
                    }
                    .font(DS.Font.body)
                    .foregroundStyle(palette.foreground)
                    .padding(DS.Size.cardPadding)
                    .background(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl).stroke(palette.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Size.pagePadding)
            .padding(.top, 12)
        }
        .pageBackground()
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: Binding(
            get: { payURL != nil },
            set: { if !$0 { payURL = nil } }
        )) {
            if let payURL, let url = URL(string: payURL) {
                SafariSheet(url: url) { self.payURL = nil }
            }
        }
        .alert("提示", isPresented: Binding(
            get: { !payMessage.isEmpty },
            set: { if !$0 { payMessage = "" } }
        )) {
            Button("知道了", role: .cancel) { payMessage = "" }
        } message: {
            Text(payMessage)
        }
    }

    private func planCard(_ palette: Palette, plan: PlanItem) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(plan.name).font(DS.Font.section).foregroundStyle(palette.foreground)
                            if plan.isCurrent {
                                StatusBadge(text: "当前套餐", background: palette.onlineBg, foreground: palette.onlineText)
                            }
                        }
                        if let description = plan.description, !description.isEmpty {
                            Text(description).font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
                        }
                    }
                    Spacer()
                    Text(Format.money(plan.priceCents, symbol: payload?.currencySymbol ?? "¥"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                }

                VStack(spacing: 6) {
                    InfoRow(label: "时长", value: "\(plan.durationDays) 天")
                    InfoRow(label: "流量", value: Format.traffic(plan.trafficBytes))
                    InfoRow(label: "限速", value: Format.speed(plan.speedLimitKbps))
                    InfoRow(label: "设备数", value: plan.deviceLimit > 0 ? "\(plan.deviceLimit) 台" : "不限")
                }

                AppButton(
                    title: "立即购买",
                    icon: "cart",
                    style: .primary,
                    loading: paying,
                    disabled: !(payload?.purchaseEnabled ?? false)
                ) {
                    Task { await buy(plan: plan) }
                }
            }
        }
    }

    private func load() async {
        error = ""
        loading = true
        defer { loading = false }
        do {
            payload = try await APIClient.shared.fetchPlans()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func buy(plan: PlanItem) async {
        error = ""
        paying = true
        defer { paying = false }
        do {
            let result = try await APIClient.shared.createOrder(planId: plan.id, method: "alipay")
            if result.payUrl.isEmpty {
                payMessage = result.message.isEmpty ? "订单已创建，请联系管理员完成支付" : result.message
            } else {
                payURL = result.payUrl
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 我的订单
struct OrdersView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: OrdersPayload?
    @State private var loading = true
    @State private var error = ""

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gap) {
                if !error.isEmpty { BannerBar(message: error) }
                if loading && payload == nil {
                    LoadingBlock(text: "正在获取订单…")
                } else if (payload?.orders ?? []).isEmpty {
                    EmptyHint(icon: "doc.text", title: "暂无订单")
                } else {
                    ForEach(payload?.orders ?? []) { order in
                        AppCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(order.planName ?? "套餐").font(DS.Font.section)
                                        .foregroundStyle(palette.foreground)
                                    Spacer()
                                    StatusBadge(
                                        text: order.statusText,
                                        background: order.status == "paid" ? palette.onlineBg : palette.muted,
                                        foreground: order.status == "paid" ? palette.onlineText : palette.mutedForeground
                                    )
                                }
                                InfoRow(label: "订单号", value: order.orderNo)
                                InfoRow(label: "金额", value: Format.money(order.amountCents))
                                InfoRow(label: "创建时间", value: Format.dateTime(order.createdAt))
                                if let paidAt = order.paidAt {
                                    InfoRow(label: "支付时间", value: Format.dateTime(paidAt))
                                }
                            }
                        }
                    }
                }
            }
            .padding(DS.Size.pagePadding)
        }
        .pageBackground()
        .navigationTitle("我的订单")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        error = ""
        loading = true
        defer { loading = false }
        do {
            payload = try await APIClient.shared.fetchOrders()
        } catch {
            self.error = error.localizedDescription
        }
    }
}