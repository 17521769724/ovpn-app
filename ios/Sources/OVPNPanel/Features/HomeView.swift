import SwiftUI
import NetworkExtension

/// 主页：选择服务器 → 选择线路 → 连接（NetworkExtension 隧道）
/// 连接中/已连接时整页切换为渐变色圆环状态页。
struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var vpn = VPNManager.shared

    @State private var payload: LinesPayload?
    @State private var loading = true
    @State private var selectedNodeId: Int?
    @State private var selectedLineId: Int?
    @State private var category = "全部"
    @State private var connecting = false
    @State private var showServerPicker = false
    /// 是否处于一次「用户主动发起」的连接尝试中，用于识别失败
    @State private var attemptActive = false

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
        .toolbar {
            if !connectionActive {
                ToolbarItem(placement: .navigationBarTrailing) {
                    IconActionButton(icon: "arrow.clockwise", loading: loading) {
                        Task { await load() }
                    }
                }
            }
        }
        .task {
            await vpn.prepare()
            await load()
        }
        .refreshable { await load() }
        .sheet(isPresented: $showPasswordSheet) { passwordSheet(palette) }
        .onChange(of: vpn.status) { status in handleStatusChange(status) }
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
                .foregroundStyle(DS.IconColor.sky)
            Text(showingServerPicker ? "第 1 步 · 选择服务器" : "第 2 步 · 选择线路并连接")
                .font(DS.Font.caption)
                .foregroundStyle(palette.mutedForeground)
            Spacer()
            if let level = payload?.level {
                StatusBadge(text: "Lv.\(level)", background: DS.IconColor.violet.opacity(0.14),
                            foreground: DS.IconColor.violet)
            }
        }
    }

    // MARK: - 连接状态页（圆环 + 服务器 / 线路 + 断开）

    private func connectionPage(_ palette: Palette) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 16)

                ConnectRing(status: vpn.status, palette: palette)
                    .frame(width: 208, height: 208)
                    .padding(.top, 8)

                // 当前使用的服务器 / 当前连接的线路
                AppCard {
                    VStack(spacing: 10) {
                        InfoRow(label: "当前服务器", value: vpn.activeServerName.isEmpty ? "-" : vpn.activeServerName)
                        Divider().overlay(palette.border)
                        InfoRow(label: "当前路线", value: vpn.activeLineName.isEmpty ? "-" : vpn.activeLineName)
                        Divider().overlay(palette.border)
                        InfoRow(label: "连接状态", value: vpn.statusText)
                    }
                }

                // 只有真正连接成功才显示「断开」；连接中显示「取消连接」
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

    // MARK: - 服务器列表

    private func serverSection(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: DS.Size.gap) {
            HStack {
                SectionHeader(title: "选择服务器", subtitle: "显示实时状态与负载，共 \(payload?.nodes.count ?? 0) 台")
                Spacer()
                if selectedNode != nil {
                    Button("返回线路") { showServerPicker = false }
                        .font(DS.Font.caption)
                        .foregroundStyle(palette.foreground)
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
                                 color: node.status == "online" ? DS.IconColor.sky : DS.IconColor.slate)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(node.name).font(DS.Font.section).foregroundStyle(palette.foreground)
                                if node.dcoEnabled {
                                    StatusBadge(text: "DCO", background: palette.onlineBg, foreground: palette.onlineText)
                                }
                                if node.supportsIPv6 {
                                    StatusBadge(text: "IPv6", background: DS.IconColor.indigo.opacity(0.14),
                                                foreground: DS.IconColor.indigo)
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
                .stroke(isSelected ? DS.IconColor.sky : Color.clear, lineWidth: 1.5)
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
                    IconTile(icon: "server.rack", color: DS.IconColor.sky, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name).font(DS.Font.section).foregroundStyle(palette.foreground)
                        Text(node.address).font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
                    }
                    Spacer()
                    Button {
                        Haptics.tap()
                        showServerPicker = true
                    } label: {
                        Text("更换")
                            .font(DS.Font.caption)
                            .foregroundStyle(palette.foreground)
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
                          ? "该服务器支持 IPv6，选择线路后可分别用 IPv4 / IPv6 连接"
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
                             color: isUDP ? DS.IconColor.amber : DS.IconColor.indigo)
                    Text(line.name).font(DS.Font.section).foregroundStyle(palette.foreground)
                    Spacer()
                    StatusBadge(
                        text: line.protocolUpper,
                        background: (isUDP ? DS.IconColor.amber : DS.IconColor.indigo).opacity(0.14),
                        foreground: isUDP ? DS.IconColor.amber : DS.IconColor.indigo
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
                .stroke(isSelected ? DS.IconColor.sky : Color.clear, lineWidth: 1.5)
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
                // 服务器支持 IPv6：IPv4 连接 / IPv6 连接 两个按钮并排
                HStack(spacing: 10) {
                    AppButton(title: "IPv4 连接", icon: "4.circle.fill", loading: connecting,
                              disabled: !node.supportsIPv4) {
                        Task { await connect(family: "v4") }
                    }
                    AppButton(title: "IPv6 连接", icon: "6.circle.fill", style: .accent, loading: connecting,
                              disabled: !node.supportsIPv6) {
                        Task { await connect(family: "v6") }
                    }
                }
            } else {
                AppButton(title: connecting ? "正在准备线路…" : "连接", icon: "bolt.fill", loading: connecting) {
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

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let payload = try await APIClient.shared.fetchLines()
            self.payload = payload
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
        guard payload?.quota.valid == true else {
            app.showToast(payload?.quota.reason.isEmpty == false ? (payload?.quota.reason ?? "") : "当前订阅状态不可用", kind: .warning)
            return
        }

        // 连接前先检查账号状态：被拉黑 / 封禁 / 到期 / 超流量直接拦截，
        // 避免无法连接却仍然显示「断开连接」按钮。
        if let status = try? await APIClient.shared.fetchUserStatus(), let notice = status.notice {
            let isBlock: Bool = (notice.code == "blocked" || notice.code == "banned")
            app.showToast(notice.message, kind: isBlock ? .error : .warning)
            Haptics.warning()
            return
        }

        connecting = true
        defer { connecting = false }
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
        app.showToast("已断开连接", kind: .info)
    }

    /// 监听隧道状态：只有真正连接成功才进入「已连接」；失败则回到选择页并提示
    private func handleStatusChange(_ status: NEVPNStatus) {
        switch status {
        case .connected:
            if attemptActive {
                attemptActive = false
                connecting = false
                Haptics.success()
                let name = vpn.activeServerName
                app.showToast(name.isEmpty ? "已连接" : "已连接到 \(name)", kind: .success)
            }
        case .disconnected:
            if attemptActive {
                attemptActive = false
                connecting = false
                Haptics.error()
                app.showToast("连接失败，请检查账号状态或稍后重试", kind: .error)
                // 立即拉取账号状态，若存在具体异常（被踢 / 到期 / 超流量）则用更精确的提示覆盖
                Task { await app.checkStatusNow() }
            }
        default:
            break
        }
    }
}

// MARK: - 连接状态圆环（渐变动画）

/// 已连接 / 连接中状态圆环：内部渐变光晕 + 旋转渐变描边
private struct ConnectRing: View {
    let status: NEVPNStatus
    let palette: Palette

    @State private var spin = false
    @State private var pulse = false

    private var isConnected: Bool { status == .connected }
    private var isBusy: Bool { status == .connecting || status == .reasserting || status == .disconnecting }

    private var tint: Color {
        if isConnected { return DS.Traffic.bar }
        if isBusy { return DS.IconColor.sky }
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

    private var icon: String { isConnected ? "checkmark" : "bolt.horizontal.fill" }

    var body: some View {
        ZStack {
            // 外圈光晕
            Circle()
                .stroke(tint.opacity(isConnected ? 0.28 : 0.16), lineWidth: 20)
                .blur(radius: 14)
                .scaleEffect(pulse ? 1.04 : 0.96)

            // 底环
            Circle()
                .stroke(palette.muted, lineWidth: 10)

            // 渐变描边（旋转动画）
            Circle()
                .trim(from: 0, to: isBusy ? 0.3 : 1)
                .stroke(palette.connectionGradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(
                    .linear(duration: isBusy ? 1.1 : 7).repeatForever(autoreverses: false),
                    value: spin
                )

            // 内部渐变
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(isConnected ? 0.30 : 0.18), tint.opacity(0.04)],
                        center: .center, startRadius: 6, endRadius: 92
                    )
                )
                .padding(26)

            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(tint)
                    .scaleEffect(pulse ? 1.06 : 1)
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.foreground)
            }
        }
        .onAppear {
            spin = true
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onChange(of: status) { _ in spin = true }
    }
}
