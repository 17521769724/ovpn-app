import SwiftUI

// MARK: - 主控地址配置

struct SetupView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var address: String = LocalStore.masterURL ?? ""
    @State private var error: String = ""
    @State private var loading = false

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: DS.Radius.xxl)
                        .fill(palette.primary)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(palette.primaryForeground)
                        )
                    Text("OVPN 客户端").font(DS.Font.title).foregroundStyle(palette.foreground)
                    Text("首次使用请填写你的主控地址")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(palette.mutedForeground)
                }
                .padding(.bottom, 8)

                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        AppTextField(title: "主控地址", placeholder: "http://你的域名或IP:端口",
                                     text: $address, keyboard: .URL)
                        if !error.isEmpty {
                            BannerBar(message: error)
                        }
                        AppButton(title: "连接并继续", icon: "arrow.right", loading: loading) {
                            Task { await submit() }
                        }
                    }
                }

                Text("地址示例：http://211.101.236.116:3000\n客户端将使用该地址登录并获取线路")
                    .font(DS.Font.caption)
                    .foregroundStyle(palette.mutedForeground)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, DS.Size.pagePadding)
        }
        .pageBackground()
    }

    private func submit() async {
        error = ""
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            error = "请输入主控地址"
            return
        }
        loading = true
        defer { loading = false }
        do {
            try await app.configureMaster(value)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var account = LocalStore.lastAccount ?? ""
    @State private var password = ""
    @State private var error = ""
    @State private var loading = false
    @State private var showRegister = false
    @State private var showForgot = false
    @State private var showMasterSheet = false

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 36)

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .fill(palette.primary)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 24))
                                .foregroundStyle(palette.primaryForeground)
                        )
                    Text("登录账号").font(DS.Font.title).foregroundStyle(palette.foreground)
                    Text(app.masterURL)
                        .font(DS.Font.caption)
                        .foregroundStyle(palette.mutedForeground)
                        .lineLimit(1)
                }
                .padding(.bottom, 4)

                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        AppTextField(title: "账号", placeholder: "用户名或邮箱", text: $account)
                        AppTextField(title: "密码", placeholder: "登录密码", text: $password, secure: true)
                        if !error.isEmpty { BannerBar(message: error) }
                        AppButton(title: "登录", loading: loading) {
                            Task { await submit() }
                        }
                    }
                }

                HStack(spacing: 16) {
                    Button("注册新账号") { showRegister = true }
                    Text("·").foregroundStyle(palette.mutedForeground)
                    Button("找回密码") { showForgot = true }
                    Text("·").foregroundStyle(palette.mutedForeground)
                    Button("更换主控") { showMasterSheet = true }
                }
                .font(DS.Font.bodySmall)
                .foregroundStyle(palette.foreground)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, DS.Size.pagePadding)
        }
        .pageBackground()
        .sheet(isPresented: $showRegister) {
            RegisterView().environmentObject(app)
        }
        .sheet(isPresented: $showForgot) {
            ForgotPasswordView().environmentObject(app)
        }
        .alert("更换主控地址？", isPresented: $showMasterSheet) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) { app.resetMaster() }
        } message: {
            Text("将退出登录并返回主控地址配置页")
        }
    }

    private func submit() async {
        error = ""
        guard !account.isEmpty, !password.isEmpty else {
            error = "请输入账号与密码"
            return
        }
        loading = true
        defer { loading = false }
        do {
            try await app.login(account: account, password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 注册

struct RegisterView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var email = ""
    @State private var error = ""
    @State private var loading = false

    var body: some View {
        let palette = Palette(scheme: scheme)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 14) {
                            AppTextField(title: "用户名", placeholder: "3-32 位字母/数字/下划线", text: $username)
                            AppTextField(title: "密码", placeholder: "至少 6 位", text: $password, secure: true)
                            AppTextField(title: "确认密码", placeholder: "再次输入密码", text: $confirm, secure: true)
                            AppTextField(title: "邮箱（选填）", placeholder: "用于找回密码", text: $email, keyboard: .emailAddress)
                            if !error.isEmpty { BannerBar(message: error) }
                            AppButton(title: "注册并登录", loading: loading) {
                                Task { await submit() }
                            }
                        }
                    }
                    Text("注册即表示同意站点服务条款；注册后可直接登录使用")
                        .font(DS.Font.caption)
                        .foregroundStyle(palette.mutedForeground)
                        .multilineTextAlignment(.center)
                }
                .padding(DS.Size.pagePadding)
            }
            .pageBackground()
            .navigationTitle("注册账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        error = ""
        guard username.count >= 3 else { error = "用户名至少 3 位"; return }
        guard password.count >= 6 else { error = "密码至少 6 位"; return }
        guard password == confirm else { error = "两次输入的密码不一致"; return }
        loading = true
        defer { loading = false }
        do {
            try await app.register(username: username, password: password, email: email)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 找回密码（密保问题）

struct ForgotPasswordView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var account = ""
    @State private var question = ""
    @State private var answer = ""
    @State private var newPassword = ""
    @State private var error = ""
    @State private var loading = false
    @State private var done = false

    var body: some View {
        let palette = Palette(scheme: scheme)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if done {
                        AppCard {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(palette.onlineText)
                                Text("密码已重置").font(DS.Font.section)
                                    .foregroundStyle(palette.foreground)
                                Text("请使用新密码登录").font(DS.Font.bodySmall)
                                    .foregroundStyle(palette.mutedForeground)
                                AppButton(title: "返回登录") { dismiss() }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        AppCard {
                            VStack(alignment: .leading, spacing: 14) {
                                if step == 1 {
                                    AppTextField(title: "账号", placeholder: "用户名或邮箱", text: $account)
                                    AppButton(title: "下一步", loading: loading) {
                                        Task { await fetchQuestion() }
                                    }
                                } else {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("密保问题").font(DS.Font.bodySmall)
                                            .foregroundStyle(palette.mutedForeground)
                                        Text(question)
                                            .font(DS.Font.body)
                                            .foregroundStyle(palette.foreground)
                                            .padding(12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(palette.muted)
                                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                                    }
                                    AppTextField(title: "密保答案", placeholder: "不区分大小写", text: $answer)
                                    AppTextField(title: "新密码", placeholder: "至少 6 位", text: $newPassword, secure: true)
                                    AppButton(title: "重置密码", loading: loading) {
                                        Task { await reset() }
                                    }
                                }
                                if !error.isEmpty { BannerBar(message: error) }
                            }
                        }
                    }
                }
                .padding(DS.Size.pagePadding)
            }
            .pageBackground()
            .navigationTitle("找回密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func fetchQuestion() async {
        error = ""
        guard !account.isEmpty else { error = "请输入账号"; return }
        loading = true
        defer { loading = false }
        do {
            question = try await APIClient.shared.forgotQuestion(account: account)
            step = 2
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reset() async {
        error = ""
        guard !answer.isEmpty else { error = "请输入密保答案"; return }
        guard newPassword.count >= 6 else { error = "新密码至少 6 位"; return }
        loading = true
        defer { loading = false }
        do {
            try await APIClient.shared.resetPassword(account: account, answer: answer, newPassword: newPassword)
            done = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}