import SwiftUI

/// 个人中心
struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var center: UserCenterPayload?
    @State private var traffic: TrafficPayload?
    @State private var loading = true
    @State private var showLogout = false
    @State private var unreadCount = 0
    @State private var trafficDays = 15

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                userCard(palette)

                trafficCard(palette)
                sessionCard(palette)
                menuCard(palette)

                AppButton(title: "退出登录", icon: "rectangle.portrait.and.arrow.right", style: .destructive) {
                    showLogout = true
                }
                .padding(.top, 4)

                Text("客户端 v\(AppInfo.version) (Build \(AppInfo.build)) · \(app.masterURL)")
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, DS.Size.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .pageBackground()
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: trafficDays) { _ in
            Task { await loadTraffic() }
        }
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
                        .fill(
                            LinearGradient(colors: [DS.IconColor.emerald, DS.IconColor.teal],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(String(app.user?.username.prefix(1) ?? "U").uppercased())
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.user?.username ?? "-")
                            .font(DS.Font.section)
                            .foregroundStyle(palette.foreground)
                        Text(app.user?.email ?? "未绑定邮箱")
                            .font(DS.Font.caption)
                            .foregroundStyle(palette.secondaryText)
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

    // MARK: - 流量（纯绿色统计，与 Web 端一致）

    private func trafficCard(_ palette: Palette) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconTile(icon: "chart.bar.fill", color: DS.Traffic.barStrong)
                    SectionHeader(title: "流量使用", subtitle: "近 \(trafficDays) 天")
                    Spacer()
                    SegmentedTabs(
                        items: ["近 7 天", "近 15 天"],
                        selection: Binding(
                            get: { trafficDays == 7 ? 0 : 1 },
                            set: { trafficDays = $0 == 0 ? 7 : 15 }
                        )
                    )
                    .frame(width: 150)
                }

                if let center {
                    let used = center.traffic.usedBytes
                    let limit = center.traffic.limitBytes
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.bytes(used)).font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(DS.Traffic.barStrong)
                        Text(limit > 0 ? "/ \(Format.bytes(limit))" : "/ 不限量")
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        if limit > 0 {
                            Text(String(format: "%.1f%%", center.traffic.percent))
                                .font(DS.Font.number)
                                .foregroundStyle(DS.Traffic.barStrong)
                        }
                    }
                    if limit > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.trafficTracker)
                                Capsule()
                                    .fill(
                                        LinearGradient(colors: [DS.Traffic.bar, DS.Traffic.barStrong],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
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
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        HStack(spacing: 10) {
                            legend(color: DS.Traffic.bar, title: "上传")
                            legend(color: DS.Traffic.barSoft, title: "下载")
                        }
                    }
                }
            }
        }
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).font(DS.Font.caption).foregroundStyle(DS.IconColor.slate)
        }
    }

    // MARK: - 在线会话

    private func sessionCard(_ palette: Palette) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconTile(icon: "antenna.radiowaves.left.and.right", color: DS.IconColor.sky)
                    SectionHeader(title: "在线会话", subtitle: "当前账号的连接")
                }
                let sessions = center?.onlineSessions ?? []
                if sessions.isEmpty {
                    Text("当前没有在线连接")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(palette.secondaryText)
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

    // MARK: - 功能入口（彩色图标 + 整行可点）

    private func menuCard(_ palette: Palette) -> some View {
        AppCard(padding: 0) {
            VStack(spacing: 0) {
                menuRow(palette, icon: "megaphone.fill", color: DS.IconColor.rose, title: "公告",
                        subtitle: unreadCount > 0 ? "有 \(unreadCount) 条未读" : nil,
                        destination: AnyView(AnnouncementsView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "ticket.fill", color: DS.IconColor.amber, title: "激活码",
                        destination: AnyView(ActivationView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "bitcoinsign.circle.fill", color: DS.IconColor.orange, title: "金币与邀请",
                        destination: AnyView(CoinsView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "exclamationmark.bubble.fill", color: DS.IconColor.blue, title: "问题反馈",
                        destination: AnyView(FeedbackView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "doc.text.fill", color: DS.IconColor.sky, title: "我的订单",
                        destination: AnyView(OrdersView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "gearshape.fill", color: DS.IconColor.slate, title: "账号设置",
                        destination: AnyView(AccountSettingsView().environmentObject(app)))
            }
        }
    }

    private func menuRow(_ palette: Palette, icon: String, color: Color, title: String,
                         subtitle: String? = nil, destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            MenuRow(icon: icon, iconColor: color, title: title, subtitle: subtitle)
        }
        .buttonStyle(PressableStyle(scale: 0.98, haptic: true))
    }

    private func divider(_ palette: Palette) -> some View {
        Rectangle().fill(palette.border).frame(height: 1).padding(.leading, 58)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let value = try await APIClient.shared.fetchUserCenter()
            center = value
            app.user = value.user
        } catch {
            if APIError.from(error).isCancelled { return }
            app.report(error)
        }
        await loadTraffic()
        if let announcements = try? await APIClient.shared.fetchAnnouncements() {
            unreadCount = announcements.unreadCount
        }
    }

    /// 按当前选择（近 7 / 15 天）拉取流量统计
    private func loadTraffic() async {
        traffic = try? await APIClient.shared.fetchTraffic(days: trafficDays)
    }
}

/// 15 天流量柱状图（纯绿色，与 Web 端配色对齐）
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
                                .fill(DS.Traffic.bar)
                                .frame(height: max(1, height * (1 - rxRatio)))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(DS.Traffic.barSoft)
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

/// 版本信息（跟随构建号）
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}