import SwiftUI
import UIKit

// MARK: - 公告

struct AnnouncementsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: AnnouncementsPayload?
    @State private var loading = true
    @State private var error = ""
    @State private var expanded: Set<Int> = []

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gap) {
                if !error.isEmpty { BannerBar(message: error) }
                if loading && payload == nil {
                    LoadingBlock(text: "正在获取公告…")
                } else if (payload?.announcements ?? []).isEmpty {
                    EmptyHint(icon: "megaphone", title: "暂无公告")
                } else {
                    if let unread = payload?.unreadCount, unread > 0 {
                        BannerBar(message: "有 \(unread) 条未读公告", kind: .warning)
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
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        error = ""
        loading = true
        defer { loading = false }
        do {
            payload = try await APIClient.shared.fetchAnnouncements()
        } catch {
            self.error = error.localizedDescription
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
    @State private var error = ""
    @State private var result: ActivationRedeemResult?
    @State private var notice = ""

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "兑换激活码", subtitle: "输入管理员发放的激活码")
                        AppTextField(title: "激活码", placeholder: "OVPN-XXXX-XXXX-XXXX", text: $code)
                        if !error.isEmpty { BannerBar(message: error) }
                        if !notice.isEmpty { BannerBar(message: notice, kind: .success) }
                        AppButton(title: "立即兑换", icon: "ticket", loading: submitting) {
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
                                        Text(record.code).font(.system(size: 12, design: .monospaced))
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
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        records = (try? await APIClient.shared.fetchActivationRecords()) ?? []
    }

    private func redeem() async {
        error = ""
        notice = ""
        result = nil
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { error = "请输入激活码"; return }
        submitting = true
        defer { submitting = false }
        do {
            let preview = try await APIClient.shared.previewActivation(code: value)
            guard preview.valid else {
                error = preview.message
                return
            }
            let redeemResult = try await APIClient.shared.redeemActivation(code: value)
            result = redeemResult
            notice = "兑换成功：\(redeemResult.planName)"
            code = ""
            await load()
            await app.refreshUser()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 金币与邀请

struct CoinsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var payload: CoinsPayload?
    @State private var loading = true
    @State private var error = ""
    @State private var copied = false

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("我的金币").font(DS.Font.caption).foregroundStyle(palette.mutedForeground)
                                Text("\(payload?.coins ?? 0)").font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(palette.foreground)
                            }
                            Spacer()
                            Image(systemName: "bitcoinsign.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(palette.warningText)
                        }
                        if let payload, payload.coinExchangeEnabled {
                            Text("金币可在购买套餐时抵扣（以套餐设置的金币价为准）")
                                .font(DS.Font.caption)
                                .foregroundStyle(palette.mutedForeground)
                        }
                    }
                }

                if let payload, payload.inviteEnabled {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "邀请好友", subtitle: "邀请注册双方均可获得金币奖励")
                            HStack {
                                Image(systemName: "link").foregroundStyle(palette.mutedForeground)
                                Text(payload.inviteCode)
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.foreground)
                                Spacer()
                                Button(copied ? "已复制" : "复制邀请码") {
                                    UIPasteboard.general.string = payload.inviteCode
                                    copied = true
                                }
                                .font(DS.Font.caption)
                                .foregroundStyle(palette.foreground)
                            }
                            InfoRow(label: "邀请人奖励", value: "\(payload.inviteRewardCoins) 金币")
                            InfoRow(label: "被邀请人奖励", value: "\(payload.inviteeRewardCoins) 金币")
                            InfoRow(label: "注册赠送", value: "\(payload.registerCoins) 金币")
                        }
                    }
                }

                if !error.isEmpty { BannerBar(message: error) }

                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "金币流水")
                        if loading && payload == nil {
                            LoadingBlock()
                        } else if (payload?.logs ?? []).isEmpty {
                            Text("暂无流水记录").font(DS.Font.bodySmall)
                                .foregroundStyle(palette.mutedForeground)
                        } else {
                            ForEach(payload?.logs ?? []) { log in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(log.reason.isEmpty ? "金币变动" : log.reason)
                                            .font(DS.Font.bodySmall)
                                            .foregroundStyle(palette.foreground)
                                        Text(Format.dateTime(log.createdAt))
                                            .font(DS.Font.caption)
                                            .foregroundStyle(palette.mutedForeground)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(log.amount >= 0 ? "+\(log.amount)" : "\(log.amount)")
                                            .font(DS.Font.number)
                                            .foregroundStyle(log.amount >= 0 ? palette.onlineText : palette.offlineText)
                                        Text("余额 \(log.balance)")
                                            .font(DS.Font.caption)
                                            .foregroundStyle(palette.mutedForeground)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .padding(DS.Size.pagePadding)
        }
        .pageBackground()
        .navigationTitle("金币与邀请")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            payload = try await APIClient.shared.fetchCoins()
        } catch {
            self.error = error.localizedDescription
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
    @State private var error = ""
    @State private var notice = ""

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "提交反馈", subtitle: "线路问题、建议都可以告诉我们")
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
                        if !error.isEmpty { BannerBar(message: error) }
                        if !notice.isEmpty { BannerBar(message: notice, kind: .success) }
                        AppButton(title: "提交反馈", icon: "paperplane", loading: submitting) {
                            Task { await submit() }
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "我的反馈")
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
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        items = (try? await APIClient.shared.fetchFeedback()) ?? []
    }

    private func submit() async {
        error = ""
        notice = ""
        guard content.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 else {
            error = "请填写反馈内容（至少 5 个字）"
            return
        }
        submitting = true
        defer { submitting = false }
        do {
            try await APIClient.shared.submitFeedback(lineId: nil, title: title, content: content, contact: contact)
            notice = "提交成功，管理员会尽快处理"
            title = ""
            content = ""
            contact = ""
            await load()
        } catch {
            self.error = error.localizedDescription
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
    @State private var loaded = false

    @State private var error = ""
    @State private var notice = ""

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Size.gapLarge) {
                if !error.isEmpty { BannerBar(message: error) }
                if !notice.isEmpty { BannerBar(message: notice, kind: .success) }

                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "修改密码")
                        AppTextField(title: "原密码", placeholder: "当前登录密码", text: $oldPassword, secure: true)
                        AppTextField(title: "新密码", placeholder: "至少 6 位", text: $newPassword, secure: true)
                        AppTextField(title: "确认新密码", placeholder: "再次输入新密码", text: $confirmPassword, secure: true)
                        AppButton(title: "保存新密码", loading: savingPassword) {
                            Task { await changePassword() }
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "密保问题",
                            subtitle: currentQuestion?.isEmpty == false ? "当前：\(currentQuestion ?? "")" : "用于找回密码，建议设置"
                        )
                        AppTextField(title: "密保问题", placeholder: "例如：我的第一台服务器名字", text: $question)
                        AppTextField(title: "密保答案", placeholder: "找回密码时使用（不区分大小写）", text: $answer)
                        AppButton(title: "保存密保", style: .secondary, loading: savingSecurity) {
                            Task { await saveSecurity() }
                        }
                    }
                }

                AppButton(title: "退出登录", icon: "rectangle.portrait.and.arrow.right", style: .outline) {
                    app.logout()
                }
            }
            .padding(DS.Size.pagePadding)
        }
        .pageBackground()
        .navigationTitle("账号设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            loaded = true
            currentQuestion = try? await APIClient.shared.fetchSecurityQuestion()
        }
    }

    private func changePassword() async {
        error = ""
        notice = ""
        guard newPassword.count >= 6 else { error = "新密码至少 6 位"; return }
        guard newPassword == confirmPassword else { error = "两次输入的新密码不一致"; return }
        savingPassword = true
        defer { savingPassword = false }
        do {
            try await APIClient.shared.changePassword(old: oldPassword, new: newPassword)
            notice = "密码已更新"
            oldPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveSecurity() async {
        error = ""
        notice = ""
        guard !question.isEmpty, answer.count >= 2 else {
            error = "请填写密保问题与答案（答案至少 2 个字符）"
            return
        }
        savingSecurity = true
        defer { savingSecurity = false }
        do {
            try await APIClient.shared.updateSecurity(question: question, answer: answer)
            currentQuestion = question
            notice = "密保已保存"
            answer = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}