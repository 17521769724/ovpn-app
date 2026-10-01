import SwiftUI

/// 主页：选择服务器 → 选择线路 → 连接
struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: LinesPayload?
    @State private var loading = true
    @State private var error = ""
    @State private var selectedNodeId: Int?
    @State private var selectedLineId: Int?
    @State private var category = "全部"
    @State private var preparing = false
    @State private var profile: LineConfig?
    @State private var showProfile = false
    @State private var showServerPicker = false
    @State private var lastRefresh = Date()

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

                    if !error.isEmpty { BannerBar(message: error) }

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
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showProfile) {
            if let profile {
                ProfilePreviewSheet(profile: profile) { showProfile = false }
            }
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
                StatusBadge(text: "Lv.\(level)", background: palette.muted, foreground: palette.foreground)
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
                    Text("实时 ↑ \(Format.bytes(node.rxRate))/s · ↓ \(Format.bytes(node.txRate))/s")
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
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(palette.muted)
                        .frame(width: 38, height: 38)
                        .overlay(Image(systemName: "server.rack").font(.system(size: 16))
                            .foregroundStyle(palette.foreground))
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
        return AppCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(line.name).font(DS.Font.section).foregroundStyle(palette.foreground)
                    Spacer()
                    StatusBadge(
                        text: line.protocolUpper,
                        background: line.protocol == "udp" ? palette.muted : palette.background,
                        foreground: palette.foreground
                    )
                }
                if let remark = line.remark, !remark.isEmpty {
                    Text(remark).font(DS.Font.caption).foregroundStyle(palette.mutedForeground).lineLimit(2)
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
                    .foregroundStyle(palette.mutedForeground)
                    .lineLimit(1)
                Spacer()
                Text("\(line.protocolUpper) \(line.port)")
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.mutedForeground)
            }
            AppButton(title: preparing ? "正在准备线路…" : "连接", icon: "bolt.fill", loading: preparing) {
                Task { await prepareConnection() }
            }
        }
        .padding(.horizontal, DS.Size.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(palette.background)
        .overlay(Rectangle().fill(palette.border).frame(height: 1), alignment: .top)
    }

    // MARK: - 数据与动作

    private func load() async {
        error = ""
        loading = true
        defer { loading = false }
        do {
            let payload = try await APIClient.shared.fetchLines()
            self.payload = payload
            self.lastRefresh = Date()
            if let selected = selectedNodeId, !payload.nodes.contains(where: { $0.id == selected }) {
                selectedNodeId = nil
                selectedLineId = nil
            }
            if let line = selectedLineId, !payload.lines.contains(where: { $0.id == line }) {
                selectedLineId = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 拉取所选服务器的线路配置（.ovpn），为连接做准备
    private func prepareConnection() async {
        guard let node = selectedNode, let line = selectedLine else { return }
        guard payload?.quota.valid == true else {
            error = payload?.quota.reason ?? "当前订阅状态不可用"
            return
        }
        preparing = true
        defer { preparing = false }
        do {
            let config = try await APIClient.shared.fetchLineConfig(lineId: line.id, nodeId: node.id)
            profile = config
            showProfile = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 线路配置预览

struct ProfilePreviewSheet: View {
    let profile: LineConfig
    let onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Size.gapLarge) {
                    BannerBar(
                        message: "线路配置已从主控获取成功。隧道连接（自动建立 VPN）将在下一个测试包中启用。",
                        kind: .warning
                    )
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "连接信息")
                            InfoRow(label: "线路", value: profile.lineName)
                            InfoRow(label: "服务器", value: profile.nodeName)
                            InfoRow(label: "配置文件", value: profile.filename)
                            InfoRow(label: "大小", value: Format.bytes(Int64(profile.content.utf8.count)))
                        }
                    }
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "配置预览", subtitle: "内容由主控生成（含证书与密钥）")
                            Text(profile.content.prefix(1200))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.mutedForeground)
                                .lineLimit(30)
                        }
                    }
                }
                .padding(DS.Size.pagePadding)
            }
            .pageBackground()
            .navigationTitle("准备连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { onClose() }
                }
            }
        }
    }
}