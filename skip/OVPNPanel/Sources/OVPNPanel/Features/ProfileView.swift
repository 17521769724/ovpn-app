import SwiftUI

/// 个人中心
struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var vpn = VPNManager.shared

    @State private var center: UserCenterPayload?
    @State private var traffic: TrafficPayload?
    @State private var loading = true
    @State private var showLogout = false
    @State private var unreadCount = 0
    @State private var trafficDays = 15
    @State private var closingSessions = false

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: DS.Size.gapLarge) {
                    userCard(palette)

                    assetsStrip(palette)
                    trafficCard(palette)
                    sessionCard(palette).id("sessions")
                    menuCard(palette)

                    AppButton(title: "退出登录", icon: "rectangle.portrait.and.arrow.right", style: AppButton.Style.destructive) {
                        showLogout = true
                    }
                    .padding(.top, 4)

                    HStack(spacing: 8) {
                        Text("客户端 v\(AppInfo.version) (Build \(AppInfo.build))")
                        VLine(height: 10)
                        Text(app.masterURL).lineLimit(1).truncationMode(.middle)
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.mutedForeground)
                    .padding(.top, 4)
                }
                .padding(.horizontal, DS.Size.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .task {
                await load()
                // 界面检查：按启动参数滚动到指定区块（如「在线会话」），便于截图核对
                if let anchor = LaunchArgs.scrollTo {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    proxy.scrollTo(anchor, anchor: .center)
                }
            }
        }
        .pageBackground()
        .navigationTitle("个人中心")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            Haptics.refresh()
            await load()
        }
        .onChange(of: trafficDays) { _ in
            Task { await loadTraffic() }
        }
        .alert("退出登录？", isPresented: $showLogout) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { app.logout() }
        }
    }

    // MARK: - 账户资产（等级 / 金币 / 余额）

    /// 三格资产条：与下方「流量使用」保持同一卡片底色，仅用彩色图标区分
    private func assetsStrip(_ palette: Palette) -> some View {
        AppCard(padding: 0) {
            HStack(spacing: 0) {
                assetCell(palette, icon: "star.circle.fill", color: DS.IconColor.teal,
                          title: "等级", value: "Lv.\(app.user?.levelValue ?? 1)")
                assetDivider(palette)
                assetCell(palette, icon: "bitcoinsign.circle.fill", color: DS.IconColor.amber,
                          title: "金币", value: "\(app.user?.coinsValue ?? 0)")
                assetDivider(palette)
                assetCell(palette, icon: "creditcard.fill", color: DS.IconColor.green,
                          title: "余额", value: String(format: "%.2f", app.user?.balanceYuanValue ?? 0))
            }
            .padding(.vertical, 14)
        }
    }

    private func assetCell(_ palette: Palette, icon: String, color: Color,
                           title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.foreground)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
        }
        .frame(maxWidth: .infinity)
    }

    private func assetDivider(_ palette: Palette) -> some View {
        Rectangle().fill(palette.border).frame(width: 1, height: 34)
    }

    // MARK: - 用户卡片（渐变底：主题色示意，作为页面视觉焦点）

    private func userCard(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(
                        LinearGradient(colors: [DS.IconColor.green, DS.IconColor.teal],
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
                // 数据未就绪时先占位，避免加载完成后整块插入导致布局跳动
                if let center {
                    StatusBadge(
                        text: center.quota.valid ? "正常" : "受限",
                        background: center.quota.valid ? palette.onlineBg : palette.offlineBg,
                        foreground: center.quota.valid ? palette.onlineText : palette.offlineText
                    )
                } else {
                    StatusBadge(text: "同步中", background: palette.muted, foreground: palette.mutedForeground)
                }
            }

            if let center, !center.quota.valid {
                BannerBar(message: center.quota.reason)
            }
            // 固定行数：数据未就绪时以占位符展示，加载完成后仅数值变化、不发生布局跳动
            VStack(spacing: 6) {
                InfoRow(label: "当前套餐", value: center?.plan?.name ?? "—")
                InfoRow(label: "到期时间", value: center == nil ? "—" : Format.dateOnly(app.user?.planExpiresAt))
                InfoRow(label: "限速", value: center == nil ? "—" : Format.speed(app.user?.speedLimitKbps ?? 0))
                InfoRow(label: "设备上限",
                        value: center == nil ? "—"
                            : ((app.user?.deviceLimit ?? 0) > 0 ? "\(app.user?.deviceLimit ?? 0) 台" : "不限"))
            }
        }
        .padding(DS.Size.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                palette.card
                LinearGradient(
                    colors: [palette.primary.opacity(palette.scheme == .dark ? 0.24 : 0.14),
                             DS.Brand.teal.opacity(palette.scheme == .dark ? 0.10 : 0.06),
                             Color.clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .stroke(palette.primary.opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
    }

    // MARK: - 流量（纯绿色统计，与 Web 端一致）

    private func trafficCard(_ palette: Palette) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconTile(icon: "chart.bar.fill", color: DS.Traffic.barStrong)
                    SectionHeader(title: "流量使用")
                    Spacer()
                    SegmentedTabs(
                        items: ["近7天", "近15天"],
                        selection: Binding(
                            get: { trafficDays == 7 ? 0 : 1 },
                            set: { trafficDays = $0 == 0 ? 7 : 15 }
                        )
                    )
                }

                // 用量区：未就绪时以占位展示，保证首屏与加载完成后布局一致（无跳动）
                let used = center?.traffic.usedBytes ?? 0
                let limit = center?.traffic.limitBytes ?? 0
                let percent = center?.traffic.percent ?? 0
                HStack(alignment: .firstTextBaseline) {
                    Text(center == nil ? "—" : Format.bytes(used))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DS.Traffic.barStrong)
                    Text(limit > 0 ? "/ \(Format.bytes(limit))" : "/ 不限量")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    if limit > 0 {
                        Text(String(format: "%.1f%%", percent))
                            .font(DS.Font.number)
                            .foregroundStyle(DS.Traffic.barStrong)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.trafficTracker)
                        Capsule()
                            .fill(
                                LinearGradient(colors: [DS.Traffic.bar, DS.Traffic.barStrong],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: max(0, min(1, percent / 100)) * geo.size.width)
                    }
                }
                .frame(height: 8)

                // 图表：固定高度占位，数据到达后仅柱形变化
                Group {
                    if let traffic, !traffic.days.isEmpty {
                        TrafficBars(days: traffic.days, palette: palette)
                    } else {
                        TrafficBarsPlaceholder(palette: palette)
                    }
                }
                .frame(height: 90)

                HStack {
                    Text(traffic.map { "合计 \(Format.bytes($0.totalBytes))" } ?? "合计 —")
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
                    IconTile(icon: "antenna.radiowaves.left.and.right", color: DS.IconColor.cyan)
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

                    // 本机未连接时，这些会话多半是系统「设置」中断开留下的残留记录，
                    // 提供手动兜底清理（主控会同时通知节点释放服务端连接）
                    if !vpn.isConnected {
                        Divider().overlay(palette.border)
                        HStack {
                            Text("断开其它设备 / 清理残留会话")
                                .font(DS.Font.caption)
                                .foregroundStyle(palette.mutedForeground)
                            Spacer()
                            AppButton(
                                title: "全部断开",
                                icon: "xmark.circle",
                                style: AppButton.Style.secondary,
                                height: DS.Size.buttonHeightSmall,
                                loading: closingSessions,
                                disabled: closingSessions
                            ) {
                                Task { await closeAllSessions() }
                            }
                            .frame(width: 108)
                        }
                        .padding(.top, 8)
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
                        badge: unreadCount > 0 ? "\(unreadCount)" : nil,
                        destination: AnyView(AnnouncementsView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "ticket.fill", color: DS.IconColor.amber, title: "激活码",
                        destination: AnyView(ActivationView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "wallet.pass.fill", color: DS.IconColor.green, title: "余额充值",
                        subtitle: "充值后可在购买套餐时全额抵扣",
                        destination: AnyView(RechargeView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "bitcoinsign.circle.fill", color: DS.IconColor.orange, title: "金币记录",
                        destination: AnyView(CoinsView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "exclamationmark.bubble.fill", color: DS.IconColor.cyan, title: "问题反馈",
                        destination: AnyView(FeedbackView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "doc.text.fill", color: DS.IconColor.cyan, title: "我的订单",
                        destination: AnyView(OrdersView().environmentObject(app)))
                divider(palette)
                menuRow(palette, icon: "gearshape.fill", color: DS.IconColor.slate, title: "账号设置",
                        destination: AnyView(AccountSettingsView().environmentObject(app)))
            }
        }
    }

    private func menuRow(_ palette: Palette, icon: String, color: Color, title: String,
                         subtitle: String? = nil, badge: String? = nil, destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            MenuRow(icon: icon, iconColor: color, title: title, subtitle: subtitle, badge: badge)
        }
        .pressableStyle(scale: 0.98)
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
    /// 失败或被取消时保留上一次数据，避免下拉刷新后图表短暂消失
    private func loadTraffic() async {
        let days = trafficDays
        guard let value = try? await APIClient.shared.fetchTraffic(days: days) else { return }
        guard days == trafficDays else { return }
        traffic = value
    }

    /// 手动关闭该账号在主控侧的全部在线会话（含系统「设置」断开后残留的记录）
    private func closeAllSessions() async {
        guard !closingSessions else { return }
        closingSessions = true
        defer { closingSessions = false }
        do {
            try await APIClient.shared.closeSessions()
            app.showToast("已断开全部在线会话")
        } catch {
            app.report(error)
        }
        await load()
    }
}

/// 流量柱状图占位：保持与真实图表相同的高度与排布，避免加载完成后页面跳动
struct TrafficBarsPlaceholder: View {
    let palette: Palette

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<15, id: \.self) { _ in
                VStack(spacing: 3) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.trafficTracker.opacity(0.7))
                        .frame(height: 4)
                    Text("--")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.mutedForeground.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
            }
        }
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