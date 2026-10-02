import SwiftUI

// MARK: - 公告

struct AnnouncementsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: AnnouncementsPayload?
    @State private var loading = true
    @State private var expanded: Set<Int> = []

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gap) {
                if loading && payload == nil {
                    LoadingBlock(text: "正在获取公告…")
                } else if (payload?.announcements ?? []).isEmpty {
                    EmptyHint(icon: "megaphone", title: "暂无公告")
                } else {
                    if let unread = payload?.unreadCount, unread > 0 {
                        BannerBar(message: "有 \(unread) 条未读公告", kind: BannerKind.warning)
                    }
                    ForEach(payload?.announcements ?? []) { item in
                        AppCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    if item.isTop {
                                        StatusBadge(text: "置顶", background: palette.muted, foreground: palette.foreground)
                                    }
                                    Text(item.title).font(DS.Font.section).foregroundStyle(palette.foreground)
                                    Spacer()
                                    if !item.read {
                                        Circle().fill(palette.destructive).frame(width: 7, height: 7)
                                    }
                                }
                                Text(item.content)
                                    .font(DS.Font.bodySmall)
                                    .foregroundStyle(palette.mutedForeground)
                                    .lineLimit(expanded.contains(item.id) ? nil : 3)
                                HStack {
                                    Text(Format.dateTime(item.createdAt))
                                        .font(DS.Font.caption)
                                        .foregroundStyle(palette.mutedForeground)
                                    Spacer()
                                    Button(expanded.contains(item.id) ? "收起" : "展开") {
                                        if expanded.contains(item.id) { expanded.remove(item.id) }
                                        else { expanded.insert(item.id) }
                                    }
                                    .font(DS.Font.caption)
                                    .foregroundStyle(palette.foreground)
                                }
                            }
                        }
                        .onTapGesture {
                            Task { await markRead(item.id) }
                        }
                    }
                }
            }
            .padding(DS.Size.pagePadding)
        }
        .pageBackground()
        .navigationTitle("公告")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable {
            Haptics.refresh()
            await load()
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            payload = try await APIClient.shared.fetchAnnouncements()
        } catch {
            if APIError.from(error).isCancelled { return }
            app.report(error)
        }
    }

    private func markRead(_ id: Int) async {
        guard let items = payload?.unreadIds, items.contains(id) else { return }
        try? await APIClient.shared.markAnnouncementsRead(ids: [id])
        await load()
    }
}

// MARK: - 激活码

struct ActivationView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var code = ""
    @State private var records: [ActivationRecord] = []
    @State private var loading = true
    @State private var submitting = false
    @State private var result: ActivationRedeemResult?

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            IconTile(icon: "ticket.fill", color: DS.IconColor.amber)
                            SectionHeader(title: "兑换激活码", subtitle: "输入管理员发放的激活码")
                        }
                        AppTextField(title: "激活码", placeholder: "OVPN-XXXX-XXXX-XXXX", text: $code)
                        AppButton(title: "立即兑换", icon: "ticket.fill", loading: submitting) {
                            Task { await redeem() }
                        }
                    }
                }

                if let result {
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: result.extend ? "已叠加到当前套餐" : "兑换成功")
                            InfoRow(label: "套餐", value: result.planName)
                            InfoRow(label: "时长", value: "\(result.durationDays) 天")
                            InfoRow(label: "流量", value: Format.traffic(result.trafficBytes))
                            InfoRow(label: "到期时间", value: Format.dateOnly(result.expiresAt))
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "兑换记录")
                        if records.isEmpty {
                            Text("暂无兑换记录")
                                .font(DS.Font.bodySmall)
                                .foregroundStyle(palette.mutedForeground)
                        } else {
                            ForEach(records) { record in
                                VStack(spacing: 5) {
                                    HStack {
                                        Text(record.code).font(.system(size: 12))
                                            .foregroundStyle(palette.foreground)
                                        Spacer()
                                        Text(Format.dateTime(record.usedAt))
                                            .font(DS.Font.caption)
                                            .foregroundStyle(palette.mutedForeground)
                                    }
                                    InfoRow(label: "套餐", value: record.planName)
                                    InfoRow(label: "时长", value: "\(record.durationDays) 天")
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                }
            }
            .padding(DS.Size.pagePadding)
        }
        .pageBackground()
        .navigationTitle("激活码")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        records = (try? await APIClient.shared.fetchActivationRecords()) ?? []
    }

    private func redeem() async {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            app.showToast("请输入激活码", kind: BannerKind.warning)
            return
        }
        submitting = true
        defer { submitting = false }
        result = nil
        do {
            let preview = try await APIClient.shared.previewActivation(code: value)
            guard preview.valid else {
                app.showToast(preview.message, kind: BannerKind.error)
                return
            }
            let redeemResult = try await APIClient.shared.redeemActivation(code: value)
            result = redeemResult
            app.showToast("兑换成功：\(redeemResult.planName)", kind: BannerKind.success)
            code = ""
            await load()
            await app.refreshUser()
        } catch {
            app.report(error)
        }
    }
}

// MARK: - 金币记录

/// 金币记录：只展示金币余额与流水（邀请相关已独立为「邀请」Tab）
struct CoinsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: CoinsPayload?
    @State private var loading = true

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                balanceCard(palette)
                logsCard(palette)
            }
            .padding(.horizontal, DS.Size.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .pageBackground()
        .navigationTitle("金币记录")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable {
            Haptics.refresh()
            await load()
        }
    }

    private func balanceCard(_ palette: Palette) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("我的金币").font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
                        Text("\(payload?.coins ?? 0)")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(DS.IconColor.orange)
                    }
                    Spacer()
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(DS.IconColor.orange)
                }
                if let payload, payload.coinExchangeEnabled {
                    BannerBar(message: "金币可在「套餐中心」兑换支持的套餐", kind: BannerKind.info)
                }
            }
        }
    }

    private func logsCard(_ palette: Palette) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconTile(icon: "list.bullet.rectangle.fill", color: DS.IconColor.teal)
                    SectionHeader(title: "金币流水")
                }
                if loading && payload == nil {
                    LoadingBlock()
                } else if (payload?.logs ?? []).isEmpty {
                    Text("暂无流水记录")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(palette.mutedForeground)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array((payload?.logs ?? []).enumerated()), id: \.offset) { index, log in
                        if index > 0 {
                            Rectangle().fill(palette.border).frame(height: 1)
                        }
                        logRow(palette, log: log)
                    }
                }
            }
        }
    }

    private func logRow(_ palette: Palette, log: CoinLog) -> some View {
        HStack(spacing: 10) {
            Image(systemName: log.amount >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(log.amount >= 0 ? palette.onlineText : DS.IconColor.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.reason.isEmpty ? "金币变动" : log.reason)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(palette.foreground)
                    .lineLimit(2)
                Text(Format.dateTime(log.createdAt))
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.mutedForeground)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(log.amount >= 0 ? "+\(log.amount)" : "\(log.amount)")
                    .font(DS.Font.number)
                    .foregroundStyle(log.amount >= 0 ? palette.onlineText : palette.offlineText)
                Text("余额 \(log.balance)")
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.mutedForeground)
            }
        }
        .padding(.vertical, 8)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            payload = try await APIClient.shared.fetchCoins()
        } catch {
            if APIError.from(error).isCancelled { return }
            app.report(error)
        }
    }
}

// MARK: - 反馈

struct FeedbackView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var title = ""
    @State private var content = ""
    @State private var contact = ""
    @State private var items: [FeedbackItem] = []
    @State private var submitting = false

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            IconTile(icon: "paperplane.fill", color: DS.IconColor.cyan)
                            SectionHeader(title: "提交反馈", subtitle: "线路问题、建议都可以告诉我们")
                        }
                        AppTextField(title: "标题", placeholder: "简要描述（选填）", text: $title)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("内容").font(DS.Font.bodySmall).foregroundStyle(palette.mutedForeground)
                            TextEditor(text: $content)
                                .font(DS.Font.body)
                                .frame(height: 110)
                                .padding(8)
                                .background(palette.background)
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg).stroke(palette.border, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                                .foregroundStyle(palette.foreground)
                        }
                        AppTextField(title: "联系方式", placeholder: "邮箱 / Telegram（选填）", text: $contact)
                        AppButton(title: "提交反馈", icon: "paperplane.fill", loading: submitting) {
                            Task { await submit() }
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            IconTile(icon: "text.bubble.fill", color: DS.IconColor.teal)
                            SectionHeader(title: "我的反馈")
                        }
                        if items.isEmpty {
                            Text("暂无反馈记录").font(DS.Font.bodySmall)
                                .foregroundStyle(palette.mutedForeground)
                        } else {
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(item.title.isEmpty ? "反馈 #\(item.id)" : item.title)
                                            .font(DS.Font.bodySmall)
                                            .foregroundStyle(palette.foreground)
                                        Spacer()
                                        StatusBadge(
                                            text: item.statusText,
                                            background: item.status == "handled" ? palette.onlineBg : palette.muted,
                                            foreground: item.status == "handled" ? palette.onlineText : palette.mutedForeground
                                        )
                                    }
                                    Text(item.content).font(DS.Font.caption)
                                        .foregroundStyle(palette.mutedForeground).lineLimit(3)
                                    if !item.reply.isEmpty {
                                        Text("回复：\(item.reply)")
                                            .font(DS.Font.caption)
                                            .foregroundStyle(palette.foreground)
                                    }
                                    Text(Format.dateTime(item.createdAt))
                                        .font(DS.Font.caption)
                                        .foregroundStyle(palette.mutedForeground)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
            }
            .padding(DS.Size.pagePadding)
        }
        .pageBackground()
        .navigationTitle("问题反馈")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private func load() async {
        items = (try? await APIClient.shared.fetchFeedback()) ?? []
    }

    private func submit() async {
        guard content.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 else {
            app.showToast("请填写反馈内容（至少 5 个字）", kind: BannerKind.warning)
            return
        }
        submitting = true
        defer { submitting = false }
        do {
            try await APIClient.shared.submitFeedback(lineId: nil, title: title, content: content, contact: contact)
            app.showToast("提交成功，管理员会尽快处理", kind: BannerKind.success)
            title = ""
            content = ""
            contact = ""
            await load()
        } catch {
            app.report(error)
        }
    }
}

// MARK: - 邀请（独立 Tab）

/// 邀请好友：展示邀请码 / 邀请链接 / 奖励规则，支持一键复制与系统分享
struct InviteView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: CoinsPayload?
    @State private var copiedCode = false
    @State private var copiedLink = false

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                hero(palette)

                if payload?.inviteEnabled == false {
                    BannerBar(message: "站点当前已关闭邀请奖励", kind: BannerKind.warning)
                } else {
                    // 固定结构：数据未就绪时先以占位展示，加载完成后仅数值变化，页面不跳动
                    codeCard(palette, payload: payload)
                    rewardCard(palette, payload: payload)
                    tipCard(palette)
                }
            }
            .padding(.horizontal, DS.Size.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .pageBackground()
        .navigationTitle("邀请好友")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable {
            Haptics.refresh()
            await load()
        }
    }

    private func hero(_ palette: Palette) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: DS.Radius.xxl)
                .fill(
                    LinearGradient(colors: [DS.Brand.green, DS.Brand.tealDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                Text("邀请好友得金币")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("好友通过你的邀请码注册，双方均可获得金币奖励，金币可用于兑换套餐。")
                    .font(DS.Font.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: "bitcoinsign.circle.fill")
                    Text("我的金币 \(payload?.coins ?? 0)")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.18))
                .clipShape(Capsule())
            }
            .padding(18)
        }
    }

    private func codeCard(_ palette: Palette, payload: CoinsPayload?) -> some View {
        let code = payload?.inviteCode ?? ""
        let urlString = payload?.inviteUrl ?? ""
        return AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconTile(icon: "number.square.fill", color: DS.IconColor.teal)
                    SectionHeader(title: "我的邀请码", subtitle: "分享给好友即可参与")
                }
                HStack {
                    Text(code.isEmpty ? "------" : code)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(palette.foreground)
#if !SKIP
                        .textSelection(.enabled)
#endif
                    Spacer()
                    AppButton(title: copiedCode ? "已复制" : "复制", icon: copiedCode ? "checkmark" : "doc.on.doc",
                              style: AppButton.Style.secondary, height: DS.Size.buttonHeightSmall,
                              disabled: code.isEmpty) {
                        Clipboard.copy(code)
                        copiedCode = true
                        app.showToast("邀请码已复制", kind: BannerKind.success)
                    }
                    .frame(width: 104)
                }

                Divider().overlay(palette.border)
                Text("邀请链接")
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.mutedForeground)
                Text(urlString.isEmpty ? "正在获取邀请链接…" : urlString)
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    AppButton(title: copiedLink ? "已复制" : "复制链接",
                              icon: "link", style: AppButton.Style.secondary,
                              height: DS.Size.buttonHeightSmall,
                              disabled: urlString.isEmpty) {
                        Clipboard.copy(urlString)
                        copiedLink = true
                        app.showToast("邀请链接已复制", kind: BannerKind.success)
                    }
                    if !urlString.isEmpty, let url = URL(string: urlString) {
                        ShareLink(item: url) { shareLabel(palette) }
                            .buttonStyle(PressableStyle())
                    } else {
                        // 未就绪时占位（保持布局稳定，不可点击）
                        shareLabel(palette).opacity(0.45)
                    }
                }
            }
        }
    }

    /// 分享按钮外观（供 ShareLink 与占位共用）
    private func shareLabel(_ palette: Palette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13, weight: .semibold))
            Text("分享").font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: DS.Size.buttonHeightSmall)
        .foregroundStyle(.white)
        .background(palette.accentGradient)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func rewardCard(_ palette: Palette, payload: CoinsPayload?) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconTile(icon: "gift.fill", color: DS.IconColor.orange)
                    SectionHeader(title: "奖励规则")
                }
                rewardRow(palette, icon: "person.fill.checkmark", title: "邀请人奖励",
                          value: "\(payload?.inviteRewardCoins ?? 0) 金币", color: DS.IconColor.green)
                rewardRow(palette, icon: "person.fill.badge.plus", title: "被邀请人奖励",
                          value: "\(payload?.inviteeRewardCoins ?? 0) 金币", color: DS.IconColor.cyan)
                rewardRow(palette, icon: "sparkles", title: "新用户注册赠送",
                          value: "\(payload?.registerCoins ?? 0) 金币", color: DS.IconColor.teal)
            }
        }
    }

    private func rewardRow(_ palette: Palette, icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            Text(title).font(DS.Font.bodySmall).foregroundStyle(palette.secondaryText)
            Spacer()
            Text(value).font(DS.Font.value).foregroundStyle(DS.IconColor.orange)
        }
    }

    private func tipCard(_ palette: Palette) -> some View {
        BannerBar(message: "好友注册成功后，奖励金币会自动到账，可在「套餐」页使用金币兑换套餐。", kind: BannerKind.info)
    }

    private func load() async {
        do {
            payload = try await APIClient.shared.fetchCoins()
        } catch {
            if APIError.from(error).isCancelled { return }
            app.report(error)
        }
    }
}

// MARK: - 账号设置（改密 / 密保）

struct AccountSettingsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var savingPassword = false

    @State private var question = ""
    @State private var answer = ""
    @State private var savingSecurity = false
    @State private var currentQuestion: String?
    @State private var securityLoaded = false
    @State private var loaded = false

    /// 是否已设置密保（已设置后界面只读展示，不再提供修改入口）
    private var hasSecurityQuestion: Bool {
        !(currentQuestion ?? "").isEmpty
    }

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            IconTile(icon: "lock.fill", color: DS.IconColor.amber)
                            SectionHeader(title: "修改密码")
                        }
                        AppTextField(title: "原密码", placeholder: "当前登录密码", text: $oldPassword, secure: true)
                        AppTextField(title: "新密码", placeholder: "至少 6 位", text: $newPassword, secure: true)
                        AppTextField(title: "确认新密码", placeholder: "再次输入新密码", text: $confirmPassword, secure: true)
                        AppButton(title: "保存新密码", icon: "checkmark.shield.fill", loading: savingPassword) {
                            Task { await changePassword() }
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            IconTile(icon: "questionmark.key.filled", color: DS.IconColor.tealDeep)
                            SectionHeader(title: "密保问题", subtitle: "用于找回密码")
                        }
                        if hasSecurityQuestion {
                            // 已设置密保：仅只读展示问题，答案不明文展示，输入框不可点击，不再显示保存/更新按钮
                            ReadOnlyField(title: "密保问题", value: currentQuestion ?? "")
                            ReadOnlyField(title: "密保答案", masked: true)
                            Text("密保答案已加密保存，不会明文展示；如需修改，请联系管理员在「用户管理」中重置密保后重新设置。")
                                .font(DS.Font.caption)
                                .foregroundStyle(palette.mutedForeground)
                        } else if securityLoaded {
                            AppTextField(title: "密保问题", placeholder: "例如：我的第一台服务器名字", text: $question)
                            AppTextField(title: "密保答案", placeholder: "找回密码时使用（不区分大小写）", text: $answer)
                            AppButton(title: "保存密保", icon: "checkmark.shield.fill", style: AppButton.Style.primary,
                                      loading: savingSecurity) {
                                Task { await saveSecurity() }
                            }
                        } else {
                            LoadingBlock(text: "正在获取密保信息…")
                        }
                    }
                }
            }
            .padding(DS.Size.pagePadding)
            .padding(.bottom, 24)
        }
        .pageBackground()
        .navigationTitle("账号设置")
        .navigationBarTitleDisplayMode(.large)
        .task {
            guard !loaded else { return }
            loaded = true
            currentQuestion = try? await APIClient.shared.fetchSecurityQuestion()
            securityLoaded = true
        }
    }

    private func changePassword() async {
        guard newPassword.count >= 6 else {
            app.showToast("新密码至少 6 位", kind: BannerKind.warning)
            return
        }
        guard newPassword == confirmPassword else {
            app.showToast("两次输入的新密码不一致", kind: BannerKind.warning)
            return
        }
        savingPassword = true
        defer { savingPassword = false }
        do {
            try await APIClient.shared.changePassword(old: oldPassword, new: newPassword)
            app.showToast("密码已更新", kind: BannerKind.success)
            oldPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch {
            app.report(error)
        }
    }

    private func saveSecurity() async {
        guard !question.isEmpty, answer.count >= 2 else {
            app.showToast("请填写密保问题与答案（答案至少 2 个字符）", kind: BannerKind.warning)
            return
        }
        savingSecurity = true
        defer { savingSecurity = false }
        do {
            try await APIClient.shared.updateSecurity(question: question, answer: answer)
            currentQuestion = question
            app.showToast("密保已保存", kind: BannerKind.success)
            answer = ""
        } catch {
            app.report(error)
        }
    }
}