import SwiftUI

// MARK: - 主控地址配置

struct SetupView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var address: String = LocalStore.masterURL ?? ""
    @State private var loading = false

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: DS.Radius.xxl)
                        .fill(palette.accentGradient)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                        .shadow(color: DS.Brand.green.opacity(0.35), radius: 12, y: 6)
                    Text("OVPN 客户端").font(DS.Font.title).foregroundStyle(palette.foreground)
                    Text("首次使用请填写你的主控地址")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(palette.mutedForeground)
                }
                .padding(.bottom, 8)

                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        AppTextField(title: "主控地址", placeholder: "https://你的域名",
                                     text: $address, keyboard: UIKeyboardType.URL)
                        AppButton(title: "连接并继续", icon: "arrow.right", loading: loading) {
                            Task { await submit() }
                        }
                    }
                }

                Text("请填写主控面板的访问地址，例如 https://panel.example.com\n客户端将使用该地址登录并获取线路")
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
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            app.showToast("请输入主控地址", kind: BannerKind.warning)
            return
        }
        loading = true
        defer { loading = false }
        do {
            try await app.configureMaster(value)
            app.showToast("主控地址已保存", kind: BannerKind.success)
        } catch {
            app.report(error)
        }
    }
}

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var account = LocalStore.lastAccount ?? ""
    @State private var password = ""
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
                        .fill(
                            LinearGradient(colors: [DS.IconColor.green, DS.IconColor.teal],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                        )
                        .shadow(color: DS.IconColor.green.opacity(0.32), radius: 10, y: 5)
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
                        AppButton(title: "登录", icon: "arrow.right.to.line", loading: loading) {
                            Task { await submit() }
                        }
                    }
                }

                HStack(spacing: 14) {
                    Button("注册新账号") { showRegister = true }
                    VLine(height: 10)
                    Button("找回密码") { showForgot = true }
                    VLine(height: 10)
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
        guard !account.isEmpty, !password.isEmpty else {
            app.showToast("请输入账号与密码", kind: BannerKind.warning)
            return
        }
        loading = true
        defer { loading = false }
        do {
            try await app.login(account: account, password: password)
            app.showToast("登录成功", kind: BannerKind.success)
        } catch {
            app.report(error)
        }
    }
}

// MARK: - 注册（含与 Web 端一致的验证码）

struct RegisterView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var email = ""
    @State private var captchaInput = ""
    @State private var captchaCode = ""
    @State private var captchaToken = ""
    @State private var captchaEnabled = false
    @State private var loadingCaptcha = false
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
                            AppTextField(title: "邮箱（选填）", placeholder: "用于找回密码", text: $email, keyboard: UIKeyboardType.emailAddress)

                            if captchaEnabled {
                                HStack(alignment: .bottom, spacing: 10) {
                                    AppTextField(title: "验证码", placeholder: "输入右侧 4 位字符", text: $captchaInput)
                                    Button {
                                        Task { await loadCaptcha() }
                                    } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: DS.Radius.lg)
                                                .fill(DS.IconColor.amber.opacity(0.14))
                                                .frame(width: 108, height: DS.Size.inputHeight)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                                                        .stroke(DS.IconColor.amber.opacity(0.45), lineWidth: 1)
                                                )
                                            if loadingCaptcha {
                                                ProgressView().scaleEffect(0.8)
                                            } else {
                                                Text(captchaCode.isEmpty ? "点击获取" : captchaCode)
                                                    .font(.system(size: 17, weight: .bold))
                                                    .foregroundStyle(DS.IconColor.amber)
#if !SKIP
                                                    .kerning(2)
#endif
                                            }
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                Text("看不清？点击橙色方块刷新验证码")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(palette.mutedForeground)
                            }

                            AppButton(title: "注册并登录", icon: "person.badge.plus", loading: loading) {
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
            .task { await loadCaptcha() }
        }
    }

    /// 拉取验证码（与 Web 端同一接口，码值直接下发）
    private func loadCaptcha() async {
        loadingCaptcha = true
        defer { loadingCaptcha = false }
        do {
            let payload = try await APIClient.shared.fetchCaptcha()
            captchaEnabled = payload.enabled
            captchaCode = payload.code
            captchaToken = payload.token
            captchaInput = ""
        } catch {
            captchaEnabled = false
        }
    }

    private func submit() async {
        guard username.count >= 3 else {
            app.showToast("用户名至少 3 位", kind: BannerKind.warning)
            return
        }
        guard password.count >= 6 else {
            app.showToast("密码至少 6 位", kind: BannerKind.warning)
            return
        }
        guard password == confirm else {
            app.showToast("两次输入的密码不一致", kind: BannerKind.warning)
            return
        }
        if captchaEnabled {
            guard !captchaInput.trimmingCharacters(in: .whitespaces).isEmpty else {
                app.showToast("请输入验证码", kind: BannerKind.warning)
                return
            }
        }
        loading = true
        defer { loading = false }
        do {
            try await app.register(username: username, password: password, email: email,
                                   captchaToken: captchaToken, captchaInput: captchaInput)
            app.showToast("注册成功，已自动登录", kind: BannerKind.success)
            dismiss()
        } catch {
            app.report(error)
            if captchaEnabled { await loadCaptcha() }
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
                                    AppButton(title: "下一步", icon: "arrow.right", loading: loading) {
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
                                    AppButton(title: "重置密码", icon: "key.fill", loading: loading) {
                                        Task { await reset() }
                                    }
                                }
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
        guard !account.isEmpty else {
            app.showToast("请输入账号", kind: BannerKind.warning)
            return
        }
        loading = true
        defer { loading = false }
        do {
            question = try await APIClient.shared.forgotQuestion(account: account)
            step = 2
        } catch {
            app.report(error)
        }
    }

    private func reset() async {
        guard !answer.isEmpty else {
            app.showToast("请输入密保答案", kind: BannerKind.warning)
            return
        }
        guard newPassword.count >= 6 else {
            app.showToast("新密码至少 6 位", kind: BannerKind.warning)
            return
        }
        loading = true
        defer { loading = false }
        do {
            try await APIClient.shared.resetPassword(account: account, answer: answer, newPassword: newPassword)
            done = true
            app.showToast("密码已重置", kind: BannerKind.success)
        } catch {
            app.report(error)
        }
    }
}