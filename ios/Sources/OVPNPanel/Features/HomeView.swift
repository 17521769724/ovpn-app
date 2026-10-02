import SwiftUI
import Combine
import NetworkExtension

/// 主页：选择服务器 → 选择线路 → 连接（NetworkExtension 隧道）
/// 连接中/已连接时整页切换为彩色泡泡圆环状态页。
struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var vpn = VPNManager.shared

    @State private var payload: LinesPayload?
    @State private var loading = true
    @State private var selectedNodeId: Int?
    @State private var selectedLineId: Int?
    @State private var category = "全部"
    /// 正在准备的地址族（v4 / v6）：两个连接按钮各自独立显示加载状态
    @State private var connectingFamily: String?
    @State private var showServerPicker = false
    /// 是否处于一次「用户主动发起」的连接尝试中，用于识别失败
    @State private var attemptActive = false

    // 当前会话的实时网速与流量（每次重新连接都会重新计数）
    @State private var sessionRx: Int64 = 0
    @State private var sessionTx: Int64 = 0
    @State private var downSpeed: Double = 0
    @State private var upSpeed: Double = 0
    @State private var connectedSince: Date?
    @State private var lastSample: (rx: Int64, tx: Int64, at: Date)?
    @State private var statsTask: Task<Void, Never>?

    // 输入一次密码后保存到钥匙串，后续连接自动使用
    @State private var passwordInput = ""
    @State private var pendingProfile: LineConfig?
    @State private var showPasswordSheet = false
    @State private var savingPassword = false

    private var selectedNode: ServerNode? {
        payload?.nodes.first { $0.id == selectedNodeId }
    }

    private var selectedLine: VPNLine? {
        payload?.lines.first { $0.id == selectedLineId }
    }

    private var categories: [String] {
        guard let payload else { return ["全部"] }
        var list = ["全部"]
        for line in payload.lines where !list.contains(line.category) {
            list.append(line.category)
        }
        return list
    }

    private var visibleLines: [VPNLine] {
        guard let payload else { return [] }
        if category == "全部" { return payload.lines }
        return payload.lines.filter { $0.category == category }
    }

    /// 未选服务器，或用户主动点「更换服务器」时展示服务器列表
    private var showingServerPicker: Bool { selectedNode == nil || showServerPicker }

    /// 连接中 / 已连接 / 正在断开：整页切换为连接状态页
    private var connectionActive: Bool {
        switch vpn.status {
        case .connecting, .connected, .reasserting, .disconnecting: return true
        default: return false
        }
    }

    var body: some View {
        let palette = Palette(scheme: scheme)
        Group {
            if connectionActive {
                connectionPage(palette)
            } else {
                selectionPage(palette)
            }
        }
        .pageBackground()
        .navigationTitle("线路连接")
        .navigationBarTitleDisplayMode(connectionActive ? .inline : .large)
        .task {
            await vpn.prepare()
            await load()
        }
        .refreshable {
            Haptics.refresh()
            // 下拉刷新后需重新选择线路，底部连接栏随之收起
            await load(clearSelection: true)
        }
        .sheet(isPresented: $showPasswordSheet) { passwordSheet(palette) }
        .onChange(of: vpn.status) { status in handleStatusChange(status) }
        .onDisappear { stopStats() }
    }

    // MARK: - 选择流程（服务器 → 线路）

    private func selectionPage(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DS.Size.gapLarge) {
                    stepHint(palette)

                    if let payload {
                        if !payload.quota.valid {
                            BannerBar(message: payload.quota.reason.isEmpty ? "订阅状态异常，暂时无法连接" : payload.quota.reason)
                        } else {
                            BannerBar(
                                message: "订阅正常 · 限速 \(Format.speed(payload.speedLimitKbps)) · 设备上限 \(payload.deviceLimit > 0 ? "\(payload.deviceLimit) 台" : "不限")",
                                kind: .success
                            )
                        }
                    }

                    if loading && payload == nil {
                        LoadingBlock(text: "正在获取服务器与线路…")
                    } else if showingServerPicker {
                        serverSection(palette)
                    } else {
                        lineSection(palette)
                    }

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, DS.Size.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            if let node = selectedNode, let line = selectedLine {
                bottomBar(palette, node: node, line: line)
            }
        }
    }

    private func stepHint(_ palette: Palette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: showingServerPicker ? "1.circle.fill" : "2.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.primary)
            Text(showingServerPicker ? "第 1 步 · 选择服务器" : "第 2 步 · 选择线路并连接")
                .font(DS.Font.caption)
                .foregroundStyle(palette.mutedForeground)
            Spacer()
            if let level = payload?.level {
                StatusBadge(text: "Lv.\(level)", background: DS.IconColor.teal.opacity(0.14),
                            foreground: DS.IconColor.teal)
            }
        }
    }

    // MARK: - 连接状态页

    private func connectionPage(_ palette: Palette) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                ConnectRing(status: vpn.status, palette: palette)
                    .frame(width: 216, height: 216)
                    .padding(.top, 12)

                // 实时网速 + 本次会话流量
                HStack(spacing: DS.Size.gap) {
                    speedTile(palette, title: "实时网速",
                              primary: Format.speedValue(downSpeed),
                              primaryIcon: "arrow.down",
                              secondary: Format.speedValue(upSpeed),
                              secondaryIcon: "arrow.up")
                    trafficTile(palette)
                }

                infoPanel(palette)

                if vpn.status == .connected {
                    AppButton(title: "断开连接", icon: "stop.circle.fill", style: .destructive) {
                        Task { await disconnect() }
                    }
                } else if vpn.status == .connecting || vpn.status == .reasserting {
                    AppButton(title: "取消连接", icon: "xmark.circle", style: .outline) {
                        Task { await disconnect() }
                    }
                } else if vpn.status == .disconnecting {
                    AppButton(title: "正在断开…", icon: "stop.circle", style: .outline, loading: true) {}
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, DS.Size.pagePadding)
            .padding(.bottom, 24)
        }
    }

    private func speedTile(_ palette: Palette, title: String,
                           primary: String, primaryIcon: String,
                           secondary: String, secondaryIcon: String) -> some View {
        AppCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.IconColor.green)
                    Text(title).font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
                }
                HStack(spacing: 4) {
                    Image(systemName: primaryIcon).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.IconColor.green)
                    Text(primary)
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                HStack(spacing: 4) {
                    Image(systemName: secondaryIcon).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.IconColor.teal)
                    Text(secondary)
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func trafficTile(_ palette: Palette) -> some View {
        AppCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.IconColor.cyan)
                    Text("本次流量").font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
                }
                Text(Format.bytes(sessionTx + sessionRx))
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.IconColor.cyan)
                    Text(durationText)
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 当前服务器 / 当前路线 / 连接状态（轻量信息面板，避免整块卡片堆叠）
    private func infoPanel(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            infoLine(palette, icon: "server.rack", label: "当前服务器",
                     value: vpn.activeServerName.isEmpty ? "-" : vpn.activeServerName)
            divider(palette)
            infoLine(palette, icon: "point.topleft.down.curvedto.point.bottomright.up",
                     label: "当前路线", value: vpn.activeLineName.isEmpty ? "-" : vpn.activeLineName)
            divider(palette)
            infoLine(palette, icon: "dot.radiowaves.left.and.right", label: "连接状态",
                     value: vpn.statusText,
                     valueColor: vpn.status == .connected ? palette.onlineText : palette.warningText)
        }
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl).stroke(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
    }

    private func infoLine(_ palette: Palette, icon: String, label: String,
                          value: String, valueColor: Color? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primary)
                .frame(width: 26, height: 26)
                .background(palette.primary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            Text(label).font(DS.Font.bodySmall).foregroundStyle(palette.mutedForeground)
            Spacer(minLength: 12)
            Text(value)
                .font(DS.Font.value)
                .foregroundStyle(valueColor ?? palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func divider(_ palette: Palette) -> some View {
        Rectangle().fill(palette.border).frame(height: 1).padding(.leading, 50)
    }

    private var durationText: String {
        guard let connectedSince else { return "--:--" }
        let seconds = max(0, Int(Date().timeIntervalSince(connectedSince)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    // MARK: - 服务器列表

    private func serverSection(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: DS.Size.gap) {
            HStack {
                SectionHeader(title: "选择服务器", subtitle: "显示实时状态与负载，共 \(payload?.nodes.count ?? 0) 台")
                Spacer()
                if selectedNode != nil {
                    Button("返回线路") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showServerPicker = false
                            // 返回线路列表后不再保留已选线路，连接栏收起
                            selectedLineId = nil
                        }
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.primary)
                }
            }

            if let nodes = payload?.nodes, nodes.isEmpty {
                EmptyHint(icon: "server.rack", title: "暂无可用服务器", detail: "请联系管理员添加节点")
            } else {
                ForEach(payload?.nodes ?? []) { node in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            selectedNodeId = node.id
                            selectedLineId = nil
                            showServerPicker = false
                        }
                    } label: {
                        serverCard(palette, node: node)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .disabled(!node.usable)
                }
            }
        }
    }

    private func serverCard(_ palette: Palette, node: ServerNode) -> some View {
        let isSelected = node.id == selectedNodeId
        return AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    HStack(spacing: 10) {
                        IconTile(icon: node.status == "online" ? "server.rack" : "exclamationmark.icloud",
                                 color: node.status == "online" ? DS.IconColor.green : DS.IconColor.slate)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(node.name).font(DS.Font.section).foregroundStyle(palette.foreground)
                                if node.dcoEnabled {
                                    StatusBadge(text: "DCO", background: palette.onlineBg, foreground: palette.onlineText)
                                }
                                if node.supportsIPv6 {
                                    StatusBadge(text: "IPv6", background: DS.IconColor.teal.opacity(0.14),
                                                foreground: DS.IconColor.teal)
                                }
                            }
                            Text(node.region?.isEmpty == false ? (node.region ?? "") : node.address)
                                .font(DS.Font.caption)
                                .foregroundStyle(palette.mutedForeground)
                        }
                    }
                    Spacer()
                    NodeStatusBadge(status: node.status)
                }

                HStack(spacing: 0) {
                    metricCell(palette, title: "在线人数", value: "\(node.onlineCount)")
                    metricCell(palette, title: "流量倍率", value: String(format: "×%.2f", node.ratio))
                    metricCell(palette, title: "等级要求", value: "Lv.\(node.levelRequired)")
                }

                VStack(spacing: 6) {
                    StatBar(label: "CPU", value: node.cpuUsage, icon: "cpu")
                    StatBar(label: "内存", value: node.memUsage, icon: "memorychip")
                    StatBar(label: "磁盘", value: node.diskUsage, icon: "internaldrive")
                }

                HStack {
                    Text("实时 ↑ \(Format.bytes(node.rxRateValue))/s · ↓ \(Format.bytes(node.txRateValue))/s")
                        .font(DS.Font.caption)
                        .foregroundStyle(palette.mutedForeground)
                    Spacer()
                    if !node.usable {
                        Text(node.unusableReason)
                            .font(DS.Font.caption)
                            .foregroundStyle(palette.offlineText)
                    } else if isSelected {
                        Text("已选择").font(DS.Font.caption).foregroundStyle(palette.onlineText)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .stroke(isSelected ? palette.primary : Color.clear, lineWidth: 1.5)
        )
        .opacity(node.usable ? 1 : 0.6)
    }

    private func metricCell(_ palette: Palette, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
            Text(value).font(DS.Font.number).foregroundStyle(palette.foreground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 线路列表

    private func lineSection(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: DS.Size.gap) {
            if let node = selectedNode {
                HStack(spacing: 10) {
                    IconTile(icon: "server.rack", color: DS.IconColor.green, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name).font(DS.Font.section).foregroundStyle(palette.foreground)
                        Text(node.address).font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showServerPicker = true
                            selectedLineId = nil
                        }
                    } label: {
                        Text("更换")
                            .font(DS.Font.caption)
                            .foregroundStyle(palette.primary)
                            .padding(.horizontal, 10)
                            .frame(height: DS.Size.buttonHeightSmall)
                            .background(palette.card)
                            .overlay(Capsule().stroke(palette.border, lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(10)
                .background(palette.muted.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
            }

            if categories.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { item in
                            ChipButton(title: item, selected: item == category) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { category = item }
                            }
                        }
                    }
                }
            }

            SectionHeader(title: "选择线路", subtitle: selectedNode?.supportsIPv6 == true
                          ? "该服务器支持 IPv6，选好路线后可分别用 IPv4 / IPv6 连接"
                          : "点击线路卡片后使用底部「连接」按钮")

            if visibleLines.isEmpty {
                EmptyHint(icon: "antenna.radiowaves.left.and.right", title: "暂无可用的线路", detail: "线路正在维护或尚未配置")
            } else {
                ForEach(visibleLines) { line in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selectedLineId = line.id }
                    } label: {
                        lineCard(palette, line: line)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
        }
    }

    private func lineCard(_ palette: Palette, line: VPNLine) -> some View {
        let isSelected = line.id == selectedLineId
        let isUDP = line.protocol.lowercased() == "udp"
        return AppCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    IconTile(icon: isUDP ? "bolt.fill" : "shield.lefthalf.filled",
                             color: isUDP ? DS.IconColor.amber : DS.IconColor.tealDeep)
                    Text(line.name).font(DS.Font.section).foregroundStyle(palette.foreground)
                    Spacer()
                    StatusBadge(
                        text: line.protocolUpper,
                        background: (isUDP ? DS.IconColor.amber : DS.IconColor.tealDeep).opacity(0.14),
                        foreground: isUDP ? DS.IconColor.amber : DS.IconColor.tealDeep
                    )
                }
                if let remark = line.remark, !remark.isEmpty {
                    Text(remark).font(DS.Font.caption).foregroundStyle(palette.secondaryText).lineLimit(2)
                }
                HStack {
                    Text("协议 / 端口").font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
                    Spacer()
                    Text("\(line.protocolUpper) \(line.port)")
                        .font(DS.Font.number)
                        .foregroundStyle(palette.foreground)
                }
                HStack {
                    Text("服务器").font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
                    Spacer()
                    Text(selectedNode?.name ?? "-")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(palette.foreground)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .stroke(isSelected ? palette.primary : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - 底部连接栏

    private func bottomBar(_ palette: Palette, node: ServerNode, line: VPNLine) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(node.name) · \(line.name)")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                Spacer()
                Text("\(line.protocolUpper) \(line.port)")
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.mutedForeground)
            }

            if node.supportsIPv6 {
                // 服务器支持 IPv6：IPv4 / IPv6 两个按钮并排，加载状态相互独立
                HStack(spacing: 10) {
                    AppButton(title: "IPv4 连接", icon: "4.circle.fill",
                              loading: connectingFamily == "v4",
                              disabled: !node.supportsIPv4 || connectingFamily == "v6") {
                        Task { await connect(family: "v4") }
                    }
                    AppButton(title: "IPv6 连接", icon: "6.circle.fill", style: .accent,
                              loading: connectingFamily == "v6",
                              disabled: !node.supportsIPv6 || connectingFamily == "v4") {
                        Task { await connect(family: "v6") }
                    }
                }
            } else {
                AppButton(title: connectingFamily == "v4" ? "正在准备线路…" : "连接",
                          icon: "bolt.fill", loading: connectingFamily == "v4") {
                    Task { await connect(family: "v4") }
                }
            }
        }
        .padding(.horizontal, DS.Size.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(palette.background)
        .overlay(Rectangle().fill(palette.border).frame(height: 1), alignment: .top)
    }

    // MARK: - 密码输入（首次连接时保存登录密码）

    private func passwordSheet(_ palette: Palette) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                BannerBar(message: "连接需要账号密码认证，密码仅保存在本机钥匙串，不会上传。", kind: .info)
                AppTextField(title: "账号", placeholder: "", text: .constant(app.user?.username ?? ""))
                AppTextField(title: "登录密码", placeholder: "请输入登录密码", text: $passwordInput, secure: true)
                AppButton(title: "保存并连接", icon: "bolt.fill", loading: savingPassword) {
                    Task { await confirmPasswordAndConnect() }
                }
            }
            .padding(DS.Size.pagePadding)
            .pageBackground()
            .navigationTitle("输入连接密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showPasswordSheet = false
                        pendingProfile = nil
                        passwordInput = ""
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
    }

    private func confirmPasswordAndConnect() async {
        guard let profile = pendingProfile else { return }
        guard !passwordInput.isEmpty else {
            app.showToast("请输入登录密码", kind: .warning)
            return
        }
        savingPassword = true
        defer { savingPassword = false }
        SecureStore.save(passwordInput, account: SecureStore.passwordAccount)
        let password = passwordInput
        passwordInput = ""
        showPasswordSheet = false
        pendingProfile = nil
        do {
            try await startTunnel(profile: profile, password: password)
        } catch {
            app.report(error)
        }
    }

    // MARK: - 数据与动作

    /// 加载服务器与线路；clearSelection=true 时清空已选线路（底部连接栏随之收起）
    private func load(clearSelection: Bool = false) async {
        loading = true
        defer { loading = false }
        do {
            let payload = try await APIClient.shared.fetchLines()
            self.payload = payload
            if clearSelection { selectedLineId = nil }
            if let selected = selectedNodeId, !payload.nodes.contains(where: { $0.id == selected }) {
                selectedNodeId = nil
                selectedLineId = nil
            }
            if let line = selectedLineId, !payload.lines.contains(where: { $0.id == line }) {
                selectedLineId = nil
            }
        } catch {
            // 下拉刷新取消请求时静默处理，避免弹出「已取消」错误
            if APIError.from(error).isCancelled { return }
            app.report(error)
        }
    }

    private func connect(family: String) async {
        guard let node = selectedNode, let line = selectedLine else { return }
        guard connectingFamily == nil else { return }
        guard payload?.quota.valid == true else {
            app.showToast(payload?.quota.reason.isEmpty == false ? (payload?.quota.reason ?? "") : "当前订阅状态不可用", kind: .warning)
            return
        }

        // 连接前先检查账号状态：被拉黑 / 封禁 / 到期 / 超流量直接拦截，
        // 避免无法连接却仍然显示「断开连接」按钮。
        if let status = try? await APIClient.shared.fetchUserStatus(), let notice = status.notice {
            let isBlock: Bool = (notice.code == "blocked" || notice.code == "banned")
            app.showToast(notice.message, kind: isBlock ? .error : .warning)
            return
        }

        connectingFamily = family
        defer { connectingFamily = nil }
        do {
            let config = try await APIClient.shared.fetchLineConfig(lineId: line.id, nodeId: node.id, family: family)
            let saved = SecureStore.load(account: SecureStore.passwordAccount) ?? ""
            if saved.isEmpty {
                pendingProfile = config
                passwordInput = ""
                showPasswordSheet = true
                return
            }
            try await startTunnel(profile: config, password: saved)
        } catch {
            if APIError.from(error).isCancelled { return }
            app.report(error)
        }
    }

    private func startTunnel(profile: LineConfig, password: String) async throws {
        guard let username = app.user?.username, !username.isEmpty else {
            throw APIError.server("登录状态异常，请重新登录")
        }
        attemptActive = true
        do {
            try await vpn.connect(profile: profile, username: username, password: password)
        } catch {
            attemptActive = false
            throw error
        }
    }

    private func disconnect() async {
        attemptActive = false
        await vpn.disconnect()
        Haptics.disconnected()
        stopStats()
        app.showToast("已断开连接", kind: .info)
        // 同步关闭主控侧会话并通知节点释放 peer，避免「在线会话」残留
        try? await APIClient.shared.closeSessions()
    }

    /// 监听隧道状态：只有真正连接成功才进入「已连接」；失败则回到选择页并提示
    private func handleStatusChange(_ status: NEVPNStatus) {
        switch status {
        case .connected:
            if attemptActive {
                attemptActive = false
                connectingFamily = nil
                Haptics.connected()
                let name = vpn.activeServerName
                app.showToast(name.isEmpty ? "已连接" : "已连接到 \(name)", kind: .success)
                resetSessionStats()
                startStats()
            }
        case .disconnected:
            if attemptActive {
                attemptActive = false
                connectingFamily = nil
                Haptics.connectFailed()
                app.showToast("连接失败，请检查账号状态或稍后重试", kind: .error)
                // 立即拉取账号状态，若存在具体异常（被踢 / 到期 / 超流量）则用更精确的提示覆盖
                Task { await app.checkStatusNow() }
            }
            stopStats()
            // 隧道已断开（含用户在系统设置里关闭）：同步关闭主控侧会话，避免「在线会话」残留
            Task { try? await APIClient.shared.closeSessions() }
        default:
            break
        }
    }

    // MARK: - 当前会话的实时网速与流量

    /// 重新连接时清空计数（流量按当前会话统计）
    private func resetSessionStats() {
        sessionRx = 0
        sessionTx = 0
        downSpeed = 0
        upSpeed = 0
        lastSample = nil
        connectedSince = Date()
    }

    /// 轮询主控获取当前会话的流量，换算为实时网速
    private func startStats() {
        statsTask?.cancel()
        statsTask = Task {
            while !Task.isCancelled {
                await sampleStats()
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            }
        }
    }

    private func stopStats() {
        statsTask?.cancel()
        statsTask = nil
    }

    private func sampleStats() async {
        guard vpn.status == .connected else { return }
        guard let center = try? await APIClient.shared.fetchUserCenter() else { return }
        // 绑定到当前连接的服务器，避免连到别的节点时统计串台
        let session = center.onlineSessions.first { $0.nodeId == vpn.activeNodeId }
            ?? center.onlineSessions.first
        guard let session else { return }

        let rx = session.rxBytes
        let tx = session.txBytes
        sessionRx = rx
        sessionTx = tx

        let now = Date()
        if let last = lastSample {
            let elapsed = now.timeIntervalSince(last.at)
            if elapsed > 0.5 {
                let downDelta = Double(max(0, tx - last.tx))
                let upDelta = Double(max(0, rx - last.rx))
                let down = downDelta / elapsed
                let up = upDelta / elapsed
                // 指数平滑，避免读数跳动
                downSpeed = downSpeed * 0.4 + down * 0.6
                upSpeed = upSpeed * 0.4 + up * 0.6
            }
        }
        lastSample = (rx: rx, tx: tx, at: now)
    }
}

// MARK: - 连接状态圆环（内部彩色泡泡 + 渐变描边）

private struct ConnectRing: View {
    let status: NEVPNStatus
    let palette: Palette

    @State private var spin = false
    @State private var bubbles: [Bubble] = []
    @State private var animate = false

    private let colorTimer = Timer.publish(every: 1.6, on: .main, in: .common).autoconnect()

    private var isConnected: Bool { status == .connected }
    private var isBusy: Bool { status == .connecting || status == .reasserting || status == .disconnecting }

    private var tint: Color {
        if isConnected { return DS.IconColor.green }
        if isBusy { return DS.IconColor.teal }
        return palette.mutedForeground
    }

    private var label: String {
        switch status {
        case .connected: return "已连接"
        case .connecting: return "连接中…"
        case .reasserting: return "重连中…"
        case .disconnecting: return "断开中…"
        default: return "未连接"
        }
    }

    /// 单个泡泡：位置 / 大小 / 上浮节奏 / 当前颜色均随机
    private struct Bubble: Identifiable {
        let id = UUID()
        var x: CGFloat          // -1 ... 1
        var y: CGFloat          // -1 ... 1
        var size: CGFloat
        var delay: Double
        var duration: Double
        var colorIndex: Int
    }

    var body: some View {
        ZStack {
            // 底环
            Circle()
                .stroke(palette.muted, lineWidth: 10)

            // 渐变描边（连接中旋转；已连接缓慢流转）
            Circle()
                .trim(from: 0, to: isBusy ? 0.3 : 1)
                .stroke(palette.connectionGradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(
                    .linear(duration: isBusy ? 1.1 : 9).repeatForever(autoreverses: false),
                    value: spin
                )

            // 内部：柔和底色 + 彩色泡泡
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(isConnected ? 0.16 : 0.08),
                                 tint.opacity(0.02)],
                        center: .center, startRadius: 4, endRadius: 104
                    )
                )

            if isConnected {
                bubbleField
            }

            VStack(spacing: 6) {
                if !isConnected {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.system(size: isConnected ? 17 : 16, weight: .semibold))
                    .foregroundStyle(isConnected ? palette.foreground : tint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(palette.card.opacity(isConnected ? 0.82 : 0.0))
            )
        }
        .onAppear {
            spin = true
            if bubbles.isEmpty { bubbles = makeBubbles() }
            animate = true
        }
        .onChange(of: status) { _ in spin = true }
        .onReceive(colorTimer) { _ in
            guard isConnected else { return }
            // 每个泡泡随机渐变到新的颜色
            withAnimation(.easeInOut(duration: 1.5)) {
                for index in bubbles.indices {
                    bubbles[index].colorIndex = Int.random(in: 0..<Palette.bubbleColors.count)
                }
            }
        }
    }

    /// 圆内彩色泡泡
    private var bubbleField: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(bubbles) { bubble in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Palette.bubbleColors[bubble.colorIndex % Palette.bubbleColors.count].opacity(0.95),
                                    Palette.bubbleColors[bubble.colorIndex % Palette.bubbleColors.count].opacity(0.45),
                                ],
                                center: .init(x: 0.35, y: 0.3),
                                startRadius: 0.5,
                                endRadius: bubble.size * 0.75
                            )
                        )
                        .frame(width: bubble.size, height: bubble.size)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                        )
                        .offset(x: bubble.x * side * 0.34,
                                y: animate ? -(side * 0.5) : (side * 0.5))
                        .opacity(bubble.size / 22 * 0.55 + 0.35)
                        .animation(
                            .linear(duration: bubble.duration)
                            .repeatForever(autoreverses: false)
                            .delay(bubble.delay),
                            value: animate
                        )
                }
            }
            .frame(width: side, height: side)
            .mask(
                Circle().padding(14)
            )
        }
        .allowsHitTesting(false)
    }

    private func makeBubbles() -> [Bubble] {
        var list: [Bubble] = []
        for index in 0..<16 {
            list.append(
                Bubble(
                    x: CGFloat.random(in: -1...1),
                    y: CGFloat.random(in: -1...1),
                    size: CGFloat.random(in: 7...21),
                    delay: Double(index) * 0.28 + Double.random(in: 0...0.6),
                    duration: Double.random(in: 3.2...5.4),
                    colorIndex: Int.random(in: 0..<Palette.bubbleColors.count)
                )
            )
        }
        return list
    }
}