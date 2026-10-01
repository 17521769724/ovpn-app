import SwiftUI

/// 主页：选择服务器 → 选择线路 → 连接（NetworkExtension 隧道）
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
    @State private var connectedProfile: LineConfig?

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

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DS.Size.gapLarge) {
                    header(palette)

                    if vpn.status != .disconnected || connectedProfile != nil {
                        connectionCard(palette)
                    }

                    if let payload {
                        if !payload.quota.valid {
                            BannerBar(message: payload.quota.reason.isEmpty ? "订阅状态异常，暂时无法连接" : payload.quota.reason)
                        } else {
                            BannerBar(
                                message: "订阅状态正常 · 限速 \(Format.speed(payload.speedLimitKbps)) · 设备上限 \(payload.deviceLimit > 0 ? "\(payload.deviceLimit) 台" : "不限")",
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
                .padding(.top, 12)
                .padding(.bottom, 16)
            }

            if let node = selectedNode, let line = selectedLine {
                bottomBar(palette, node: node, line: line)
            }
        }
        .pageBackground()
        .task {
            await vpn.prepare()
            await load()
        }
        .refreshable { await load() }
        .sheet(isPresented: $showPasswordSheet) {
            passwordSheet(palette)
        }
    }

    // MARK: - 顶部

    private func header(_ palette: Palette) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("线路连接").font(DS.Font.title).foregroundStyle(palette.foreground)
                Text(showingServerPicker ? "第 1 步 · 选择服务器" : "第 2 步 · 选择线路并连接")
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.mutedForeground)
            }
            Spacer()
            if let level = payload?.level {
                StatusBadge(text: "Lv.\(level)", background: DS.IconColor.violet.opacity(0.14),
                            foreground: DS.IconColor.violet)
            }
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
            .disabled(loading)
        }
    }

    // MARK: - 连接状态

    private func connectionCard(_ palette: Palette) -> some View {
        let style: (Color, String) = {
            switch vpn.status {
            case .connected: return (palette.onlineText, "checkmark.seal.fill")
            case .connecting, .reasserting: return (DS.IconColor.amber, "arrow.triangle.2.circlepath")
            case .disconnecting: return (DS.IconColor.amber, "arrow.triangle.2.circlepath")
            default: return (palette.mutedForeground, "bolt.horizontal.circle")
            }
        }()
        return AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconTile(icon: style.1, color: style.0, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vpn.statusText)
                            .font(DS.Font.section)
                            .foregroundStyle(style.0)
                        if let profile = connectedProfile {
                            Text("\(profile.nodeName) · \(profile.lineName)")
                                .font(DS.Font.caption)
                                .foregroundStyle(palette.secondaryText)
                        } else {
                            Text("选择服务器与线路后点击连接")
                                .font(DS.Font.caption)
                                .foregroundStyle(palette.mutedForeground)
                        }
                    }
                    Spacer()
                    Circle()
                        .fill(style.0)
                        .frame(width: 9, height: 9)
                        .opacity(vpn.status == .connected ? 1 : 0.5)
                }

                if vpn.status == .disconnected, connectedProfile != nil {
                    AppButton(title: "断开连接", icon: "stop.circle", style: .outline, height: 40) {
                        Task {
                            await vpn.disconnect()
                            app.showToast("已断开连接", kind: .info)
                        }
                    }
                }
            }
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
                        selectedNodeId = node.id
                        selectedLineId = nil
                        showServerPicker = false
                    } label: {
                        serverCard(palette, node: node)
                    }
                    .buttonStyle(.plain)
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
                    Button("更换") { showServerPicker = true }
                        .font(DS.Font.caption)
                        .foregroundStyle(palette.foreground)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(palette.card)
                        .overlay(Capsule().stroke(palette.border, lineWidth: 1))
                        .clipShape(Capsule())
                }
                .padding(10)
                .background(palette.muted.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
            }

            if categories.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { item in
                            ChipButton(title: item, selected: item == category) { category = item }
                        }
                    }
                }
            }

            SectionHeader(title: "选择线路", subtitle: "点击线路卡片后使用底部「连接」按钮")

            if visibleLines.isEmpty {
                EmptyHint(icon: "antenna.radiowaves.left.and.right", title: "暂无可用的线路", detail: "线路正在维护或尚未配置")
            } else {
                ForEach(visibleLines) { line in
                    Button { selectedLineId = line.id } label: {
                        lineCard(palette, line: line)
                    }
                    .buttonStyle(.plain)
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
        let connected = vpn.status == .connected || vpn.status == .connecting || vpn.status == .reasserting
        return VStack(spacing: 8) {
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
            if connected {
                AppButton(title: vpn.statusText, icon: "stop.circle", style: .outline,
                          loading: vpn.isBusy, disabled: vpn.status == .disconnecting) {
                    Task {
                        await vpn.disconnect()
                        app.showToast("已断开连接", kind: .info)
                    }
                }
            } else {
                AppButton(title: connecting ? "正在准备线路…" : "连接", icon: "bolt.fill", loading: connecting) {
                    Task { await connect() }
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

    private func connect() async {
        guard let node = selectedNode, let line = selectedLine else { return }
        guard payload?.quota.valid == true else {
            app.showToast(payload?.quota.reason ?? "当前订阅状态不可用", kind: .warning)
            return
        }
        connecting = true
        defer { connecting = false }
        do {
            let config = try await APIClient.shared.fetchLineConfig(lineId: line.id, nodeId: node.id)
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
        try await vpn.connect(profile: profile, username: username, password: password)
        connectedProfile = profile
        app.showToast("正在连接 \(profile.nodeName)…", kind: .info)
    }
}