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
    /// 每秒心跳：驱动连接时长计时的刷新
    @State private var nowTick = Date()

    /// 服务器列表「实时」数据自动刷新（带宽 / 负载 / 在线数）
    private let liveTicker = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    /// 计时心跳（1 秒）
    private let clockTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
        // 分类顺序以主控下发为准（与管理后台的排序一致）；老版本主控未下发时按线路出现顺序兜底
        if let preset = payload.categories, !preset.isEmpty {
            var list = ["全部"]
            for name in preset where !list.contains(name) {
                list.append(name)
            }
            return list
        }
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
            // 冷启动时隧道可能已由「系统设置」建立：直接进入已连接状态（含计时与实时统计）
            if vpn.status == .connected {
                if sessionStart == nil { connectedSince = Date() }
                startStats()
            }
        }
        .refreshable {
            Haptics.refresh()
            // 下拉刷新后需重新选择线路，底部连接栏随之收起
            await load(clearSelection: true)
        }
        .sheet(isPresented: $showPasswordSheet) { passwordSheet(palette) }
        .onChange(of: vpn.status) { status in handleStatusChange(status) }
        // 服务器列表自动刷新：让「实时带宽 / 负载」真的保持实时（不打断已选线路）
        .onReceive(liveTicker) { _ in
            guard !connectionActive, !loading, payload != nil else { return }
            Task { await load() }
        }
        // 每秒心跳：仅连接状态页需要驱动计时
        .onReceive(clockTicker) { value in
            if sessionStart != nil { nowTick = value }
        }
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
                                message: "订阅正常｜限速 \(Format.speed(payload.speedLimitKbps))｜设备上限 \(payload.deviceLimit > 0 ? "\(payload.deviceLimit) 台" : "不限")",
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
            Text(showingServerPicker ? "第 1 步" : "第 2 步")
                .font(DS.Font.caption)
                .foregroundStyle(palette.mutedForeground)
            VLine(height: 10)
            Text(showingServerPicker ? "选择服务器" : "选择线路并连接")
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
                ConnectRing(status: vpn.status, palette: palette, duration: durationText, size: 224)
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
                HStack(spacing: 6) {
                    Text("↑ \(Format.bytes(sessionRx))")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(DS.IconColor.green)
                    VLine(height: 9)
                    Text("↓ \(Format.bytes(sessionTx))")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(DS.IconColor.teal)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
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
        guard let start = sessionStart else { return "--:--" }
        let seconds = max(0, Int(nowTick.timeIntervalSince(start)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    /// 当前会话的起始时间：优先使用系统隧道记录的时间（跨页面 / 冷启动 / 系统设置连接均不重置），
    /// 仅在系统未提供时回退到主控会话时间或本地记录。
    private var sessionStart: Date? { vpn.connectedAt ?? connectedSince }

    // MARK: - 服务器列表

    private func serverSection(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: DS.Size.gap) {
            HStack {
                SectionHeader(title: "选择服务器", subtitle: "显示实时状态与负载，共 \(payload?.nodes.count ?? 0) 台")
                Spacer()
                if selectedNode != nil {
                    // 非白底按钮：主题色浅底胶囊，明确可点
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showServerPicker = false
                            // 返回线路列表后不再保留已选线路，连接栏收起
                            selectedLineId = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("返回线路")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(palette.primary)
                        .padding(.horizontal, 12)
                        .frame(height: DS.Size.buttonHeightSmall)
                        .background(palette.primary.opacity(0.14))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
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
        // 不可用（离线 / 等级不足）：整卡使用不可点击的灰底，弱化展示
        return AppCard(background: node.usable ? nil : palette.muted) {
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
                            }
                            if let region = node.region, !region.isEmpty {
                                Text(region)
                                    .font(DS.Font.caption)
                                    .foregroundStyle(palette.mutedForeground)
                            }
                        }
                    }
                    Spacer()
                    NodeStatusBadge(status: node.status)
                }

                // 已配置的 IPv4 / IPv6 地址（两者都配置时同时展示）
                // 服务器离线时隐藏地址（IPv4 / IPv6 均不显示，避免暴露不可达的地址）
                let showAddress = node.status == "online"
                if showAddress, node.displayIPv4 != nil || node.displayIPv6 != nil {
                    VStack(spacing: 5) {
                        if let v4 = node.displayIPv4 {
                            addressRow(palette, label: "IPv4", value: v4, color: DS.IconColor.green)
                        }
                        if let v6 = node.displayIPv6 {
                            addressRow(palette, label: "IPv6", value: v6, color: DS.IconColor.teal)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(palette.muted.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
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

                HStack(spacing: 7) {
                    Text("实时")
                        .font(DS.Font.caption)
                        .foregroundStyle(palette.mutedForeground)
                    Text("↑ \(Format.bytes(node.rxRateValue))/s")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.IconColor.green)
                    VLine(height: 10)
                    Text("↓ \(Format.bytes(node.txRateValue))/s")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.IconColor.teal)
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
        .opacity(node.usable ? 1 : 0.8)
    }

    /// 单行地址展示（IPv4 / IPv6）
    private func addressRow(_ palette: Palette, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.name).font(DS.Font.section).foregroundStyle(palette.foreground)
                        // 离线服务器不展示地址（IPv4 / IPv6 都隐藏）
                        if node.status == "online" {
                            HStack(spacing: 6) {
                                if let v4 = node.displayIPv4 {
                                    Text(v4)
                                        .font(DS.Font.caption)
                                        .foregroundStyle(palette.mutedForeground)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                if node.displayIPv4 != nil && node.displayIPv6 != nil {
                                    VLine(height: 9)
                                }
                                if let v6 = node.displayIPv6 {
                                    Text(v6)
                                        .font(DS.Font.caption)
                                        .foregroundStyle(palette.mutedForeground)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 6)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showServerPicker = true
                            selectedLineId = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                            Text("更换")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: DS.Size.buttonHeightSmall)
                        .background(palette.accentGradient)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(10)
                .background(palette.muted.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
            }

            if categories.count > 1 {
                // 「全部」与竖线固定在左侧不参与滑动，其余分类单独横向滚动
                HStack(spacing: 8) {
                    ChipButton(title: "全部", selected: category == "全部") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { category = "全部" }
                    }
                    VLine(height: 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(categories.dropFirst()), id: \.self) { item in
                                ChipButton(title: item, selected: item == category) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { category = item }
                                }
                            }
                        }
                        // 左右留出少量内边距，滚动时首尾分类不贴边
                        .padding(.horizontal, 1)
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
            HStack(spacing: 8) {
                Text(node.name)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                VLine(height: 10)
                Text(line.name)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
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
        // 主控侧会话由 VPNManager 在状态落为「已断开」时统一关闭（含系统设置里断开的情况）
    }

    /// 监听隧道状态：只有真正连接成功才进入「已连接」；失败则回到选择页并提示
    private func handleStatusChange(_ status: NEVPNStatus) {
        switch status {
        case .connected:
            connectingFamily = nil
            if attemptActive {
                attemptActive = false
                Haptics.connected()
                let name = vpn.activeServerName
                app.showToast(name.isEmpty ? "已连接" : "已连接到 \(name)", kind: .success)
                resetSessionStats()
            }
            // 系统隧道已提供连接时间（含在系统设置里建立的连接）；缺失时才用本地兜底
            if sessionStart == nil { connectedSince = Date() }
            startStats()
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
            connectedSince = nil
            // 主控侧会话由 VPNManager 在状态变化时统一关闭（含系统设置里断开的情况）
        default:
            break
        }
    }

    // MARK: - 当前会话的实时网速与流量

    /// 重新连接时清空计数（流量按当前会话统计；计时由 VPNManager 持久化的连接时间驱动）
    private func resetSessionStats() {
        sessionRx = 0
        sessionTx = 0
        downSpeed = 0
        upSpeed = 0
        lastSample = nil
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

        // 从主控会话时间恢复计时（例如在系统设置里连接后回到 App）
        if connectedSince == nil, let started = Format.parse(session.connectedAt) {
            connectedSince = started
        }

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

// MARK: - 连接状态圆环（极光光环：渐变描边 + 光晕呼吸 + 中心计时）

private struct ConnectRing: View {
    let status: NEVPNStatus
    let palette: Palette
    /// 已连接时长（如 12:34），连接成功后显示在圆环中央
    let duration: String
    /// 圆环直径（固定尺寸，避免父视图布局差异导致错位）
    var size: CGFloat = 224

    @State private var sweep = false
    @State private var breathe = false

    private var isConnected: Bool { status == .connected }
    private var isBusy: Bool { status == .connecting || status == .reasserting || status == .disconnecting }

    private var tint: Color {
        if isConnected { return DS.IconColor.green }
        if isBusy { return DS.IconColor.teal }
        return palette.mutedForeground
    }

    private var ringWidth: CGFloat { 9 }

    private var label: String {
        switch status {
        case .connected: return "已连接"
        case .connecting: return "连接中…"
        case .reasserting: return "重连中…"
        case .disconnecting: return "断开中…"
        default: return "未连接"
        }
    }

    var body: some View {
        ZStack {
            // 外层光晕：用两层低透明度粗描边模拟柔光（不使用 blur —— 模糊图层在真机上
            // 会出现离屏渲染杂色 / 残影，表现为圆环旁出现莫名色块）
            Circle()
                .stroke(palette.connectionGradient, lineWidth: 30)
                .frame(width: size - 44, height: size - 44)
                .opacity(glowOpacity * 0.45)
                .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: breathe)
            Circle()
                .stroke(palette.connectionGradient, lineWidth: 18)
                .frame(width: size - 40, height: size - 40)
                .opacity(glowOpacity * 0.6)
                .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: breathe)

            // 底环
            Circle()
                .stroke(palette.muted, lineWidth: ringWidth)
                .frame(width: size - ringWidth, height: size - ringWidth)

            // 内部柔和径向底色
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(isConnected ? 0.16 : 0.07), tint.opacity(0.015)],
                        center: .center, startRadius: 6, endRadius: 100
                    )
                )
                .frame(width: size - (ringWidth + 2) * 2, height: size - (ringWidth + 2) * 2)

            // 渐变主环（缓慢流转；未连接时淡显）
            Circle()
                .stroke(
                    palette.connectionGradient,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .frame(width: size - ringWidth, height: size - ringWidth)
                .opacity(isConnected ? 1 : (isBusy ? 0.9 : 0.32))
                .rotationEffect(.degrees(sweep ? 360 : 0))
                .animation(
                    .linear(duration: isBusy ? 1.6 : 16).repeatForever(autoreverses: false),
                    value: sweep
                )

            // 高光彗尾：连接中快速巡游，已连接缓慢扫过
            if isConnected || isBusy {
                Circle()
                    .trim(from: 0, to: 0.14)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0), .white.opacity(0.85)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .frame(width: size - ringWidth, height: size - ringWidth)
                    .rotationEffect(.degrees(sweep ? 360 : 0))
                    .animation(
                        .linear(duration: isBusy ? 1.3 : 6).repeatForever(autoreverses: false),
                        value: sweep
                    )
                    .opacity(isBusy ? 0.9 : 0.45)
            }

            // 中心：已连接显示计时；连接中显示状态
            if isConnected {
                VStack(spacing: 4) {
                    Text(duration)
                        .font(.system(size: 34, weight: .semibold).monospacedDigit())
                        .foregroundStyle(palette.foreground)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(DS.IconColor.green)
                            .frame(width: 7, height: 7)
                            .shadow(color: DS.IconColor.green.opacity(0.6), radius: 3)
                        Text(label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.IconColor.green)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: isBusy ? "arrow.triangle.2.circlepath" : "power")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(tint)
                        .rotationEffect(.degrees(isBusy && sweep ? 360 : 0))
                        .animation(
                            .linear(duration: 1.2).repeatForever(autoreverses: false),
                            value: sweep
                        )
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        // 固定尺寸 + 裁剪：所有子图层（光晕 / 旋转渐变环 / 彗尾）都收在本帧内，
        // 任何越界绘制都会被裁掉，避免真机上出现「圆环旁边莫名色块 / 杂色」
        .frame(width: size, height: size)
        .clipped()
        .frame(maxWidth: .infinity)
        .onAppear {
            sweep = true
            breathe = true
        }
        .onChange(of: status) { _ in
            // 状态切换：重置旋转动画（瞬时复位，不产生反向旋转位移）
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { sweep = false }
            DispatchQueue.main.async { sweep = true }
            breathe = true
        }
    }

    /// 外层光晕透明度（呼吸动画的取值区间）
    private var glowOpacity: Double {
        if isConnected { return breathe ? 0.9 : 0.5 }
        if isBusy { return breathe ? 0.6 : 0.35 }
        return 0.16
    }
}