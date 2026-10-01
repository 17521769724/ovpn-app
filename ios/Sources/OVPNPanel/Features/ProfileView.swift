import SwiftUI

/// 个人中心
struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var center: UserCenterPayload?
    @State private var traffic: TrafficPayload?
    @State private var loading = true
    @State private var error = ""
    @State private var showLogout = false

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                userCard(palette)

                if !error.isEmpty { BannerBar(message: error) }

                trafficCard(palette)
                sessionCard(palette)
                menuCard(palette)

                AppButton(title: "退出登录", icon: "rectangle.portrait.and.arrow.right", style: .outline) {
                    showLogout = true
                }
                .padding(.top, 4)

                Text("客户端 v1.0.0 · \(app.masterURL)")
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, DS.Size.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .pageBackground()
        .task { await load() }
        .refreshable { await load() }
        .alert("退出登录？", isPresented: $showLogout) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { app.logout() }
        }
    }

    // MARK: - 用户卡片

    private func userCard(_ palette: Palette) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(palette.muted)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(String(app.user?.username.prefix(1) ?? "U").uppercased())
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(palette.foreground)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.user?.username ?? "-")
                            .font(DS.Font.section)
                            .foregroundStyle(palette.foreground)
                        Text(app.user?.email ?? "未绑定邮箱")
                            .font(DS.Font.caption)
                            .foregroundStyle(palette.mutedForeground)
                    }
                    Spacer()
                    if let center {
                        StatusBadge(
                            text: center.quota.valid ? "正常" : "受限",
                            background: center.quota.valid ? palette.onlineBg : palette.offlineBg,
                            foreground: center.quota.valid ? palette.onlineText : palette.offlineText
                        )
                    }
                }

                if let center {
                    if !center.quota.valid {
                        BannerBar(message: center.quota.reason)
                    }
                    VStack(spacing: 6) {
                        InfoRow(label: "当前套餐", value: center.plan?.name ?? "未订阅")
                        InfoRow(label: "到期时间", value: Format.dateOnly(app.user?.planExpiresAt))
                        InfoRow(label: "限速", value: Format.speed(app.user?.speedLimitKbps ?? 0))
                        InfoRow(label: "设备上限", value: (app.user?.deviceLimit ?? 0) > 0 ? "\(app.user?.deviceLimit ?? 0) 台" : "不限")
                    }
                }
            }
        }
    }

    // MARK: - 流量

    private func trafficCard(_ palette: Palette) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "流量使用", subtitle: "近 15 天")

                if let center {
                    let used = center.traffic.usedBytes
                    let limit = center.traffic.limitBytes
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.bytes(used)).font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(palette.foreground)
                        Text(limit > 0 ? "/ \(Format.bytes(limit))" : "/ 不限量")
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(palette.mutedForeground)
                        Spacer()
                        if limit > 0 {
                            Text(String(format: "%.1f%%", center.traffic.percent))
                                .font(DS.Font.number)
                                .foregroundStyle(palette.mutedForeground)
                        }
                    }
                    if limit > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.muted)
                                Capsule()
                                    .fill(palette.primary.opacity(0.8))
                                    .frame(width: max(0, min(1, center.traffic.percent / 100)) * geo.size.width)
                            }
                        }
                        .frame(height: 8)
                    }
                }

                if let traffic, !traffic.days.isEmpty {
                    TrafficBars(days: traffic.days, palette: palette)
                        .frame(height: 90)
                    HStack {
                        Text("合计 \(Format.bytes(traffic.totalBytes))")
                            .font(DS.Font.caption)
                            .foregroundStyle(palette.mutedForeground)
                        Spacer()
                        Text("上行 / 下行")
                            .font(DS.Font.caption)
                            .foregroundStyle(palette.mutedForeground)
                    }
                }
            }
        }
    }

    // MARK: - 在线会话

    private func sessionCard(_ palette: Palette) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "在线会话", subtitle: "当前账号的连接")
                let sessions = center?.onlineSessions ?? []
                if sessions.isEmpty {
                    Text("当前没有在线连接")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(palette.mutedForeground)
                        .padding(.vertical, 6)
                } else {
                    ForEach(sessions) { session in
                        VStack(spacing: 6) {
                            HStack {
                                Text(session.nodeName ?? "节点")
                                    .font(DS.Font.bodySmall)
                                    .foregroundStyle(palette.foreground)
                                Spacer()
                                Text(Format.dateTime(session.connectedAt))
                                    .font(DS.Font.caption)
                                    .foregroundStyle(palette.mutedForeground)
                            }
                            InfoRow(label: "虚拟 IP", value: session.virtualIp.isEmpty ? "-" : session.virtualIp)
                            InfoRow(
                                label: "流量",
                                value: "↑ \(Format.bytes(session.rxBytes)) / ↓ \(Format.bytes(session.txBytes))"
                            )
                        }
                        .padding(.vertical, 6)
                        if session.id != sessions.last?.id {
                            Divider().overlay(palette.border)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 功能入口

    private func menuCard(_ palette: Palette) -> some View {
        AppCard(padding: 0) {
            VStack(spacing: 0) {
                menuRow(palette, icon: "megaphone", title: "公告", destination: AnyView(AnnouncementsView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "ticket", title: "激活码", destination: AnyView(ActivationView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "bitcoinsign.circle", title: "金币与邀请", destination: AnyView(CoinsView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "bubble.left.and.text.bubble.right", title: "问题反馈", destination: AnyView(FeedbackView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "doc.text", title: "我的订单", destination: AnyView(OrdersView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "gearshape", title: "账号设置", destination: AnyView(AccountSettingsView().environmentObject(app)))
            }
        }
    }

    private func menuRow(_ palette: Palette, icon: String, title: String, destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.foreground)
                    .frame(width: 22)
                Text(title).font(DS.Font.body).foregroundStyle(palette.foreground)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.mutedForeground)
            }
            .padding(.horizontal, DS.Size.cardPadding)
            .frame(height: 50)
        }
        .buttonStyle(.plain)
    }

    private func divider(_ palette: Palette) -> some View {
        Rectangle().fill(palette.border).frame(height: 1).padding(.leading, 50)
    }

    private func load() async {
        error = ""
        loading = true
        defer { loading = false }
        async let centerTask = APIClient.shared.fetchUserCenter()
        async let trafficTask = APIClient.shared.fetchTraffic(days: 15)
        do {
            center = try await centerTask
            app.user = center?.user
        } catch {
            self.error = error.localizedDescription
        }
        traffic = try? await trafficTask
    }
}

/// 15 天流量柱状图（纯 SwiftUI 绘制，与 Web 端堆叠柱状图对应）
struct TrafficBars: View {
    let days: [TrafficDay]
    let palette: Palette

    var body: some View {
        let maxValue = max(days.map { $0.totalBytes }.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(days) { day in
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        let total = CGFloat(day.totalBytes) / CGFloat(maxValue)
                        let rxRatio = day.totalBytes > 0 ? CGFloat(day.rxBytes) / CGFloat(max(day.totalBytes, 1)) : 0.5
                        let height = max(2, geo.size.height * total)
                        VStack(spacing: 1) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(palette.primary.opacity(0.85))
                                .frame(height: max(1, height * (1 - rxRatio)))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(palette.primary.opacity(0.35))
                                .frame(height: max(1, height * rxRatio))
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    Text(day.day.suffix(2))
                        .font(.system(size: 9))
                        .foregroundStyle(palette.mutedForeground)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}