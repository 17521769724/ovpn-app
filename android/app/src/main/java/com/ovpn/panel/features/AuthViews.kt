package com.ovpn.panel.features

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ovpn.panel.core.ApiService
import com.ovpn.panel.core.AppState
import com.ovpn.panel.core.BannerKind
import com.ovpn.panel.core.DS
import com.ovpn.panel.core.LocalPalette
import com.ovpn.panel.core.LocalStore
import com.ovpn.panel.ui.AppButton
import com.ovpn.panel.ui.AppCard
import com.ovpn.panel.ui.AppTextField
import com.ovpn.panel.ui.ScreenScaffold
import com.ovpn.panel.ui.pressableScale
import kotlinx.coroutines.launch

/**
 * 认证相关页面（Android），移植自 iOS `Features/AuthViews.swift`。
 * 覆盖：主控地址配置 [SetupView]、登录 [LoginView]、注册 [RegisterView]、找回密码 [ForgotPasswordView]。
 * 视图规格（圆角 / 尺寸 / 字号 / 颜色）全部取自 [DS] 与 [LocalPalette]，改动需三端同步。
 */

// MARK: - 主控地址配置

/**
 * 主控地址配置页（对应 iOS `SetupView`）。
 * iOS 无 navigationTitle，故顶部不展示标题文字；内容中已内嵌「OVPN 客户端」品牌标题。
 */
@Composable
fun SetupView() {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()
    var address by remember { mutableStateOf(LocalStore.masterURL ?: "") }
    var loading by remember { mutableStateOf(false) }

    ScreenScaffold(title = "") {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Size.pagePadding)
                .padding(top = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            // 品牌图标 + 标题（对应 iOS SetupView 顶部 VStack(spacing: 10)）
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(64.dp)
                        .shadow(
                            elevation = 12.dp,
                            shape = RoundedCornerShape(DS.Radius.xxl),
                            ambientColor = DS.Brand.green.copy(alpha = 0.35f),
                            spotColor = DS.Brand.green.copy(alpha = 0.35f),
                        )
                        .clip(RoundedCornerShape(DS.Radius.xxl))
                        .background(palette.accentGradient),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Shield,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(28.dp),
                    )
                }
                Text("OVPN 客户端", style = DS.Font.title, color = palette.foreground)
                Text("首次使用请填写你的主控地址", style = DS.Font.bodySmall, color = palette.mutedForeground)
            }

            AppCard {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    AppTextField(
                        title = "主控地址",
                        value = address,
                        onValueChange = { address = it },
                        placeholder = "https://你的域名",
                        keyboardType = KeyboardType.Uri,
                    )
                    AppButton(
                        title = "连接并继续",
                        icon = Icons.AutoMirrored.Filled.ArrowForward,
                        loading = loading,
                    ) {
                        scope.launch {
                            val value = address.trim()
                            if (value.isEmpty()) {
                                AppState.showToast("请输入主控地址", BannerKind.Warning)
                                return@launch
                            }
                            loading = true
                            try {
                                AppState.configureMaster(value)
                                AppState.showToast("主控地址已保存", BannerKind.Success)
                            } catch (e: Exception) {
                                AppState.report(e)
                            } finally {
                                loading = false
                            }
                        }
                    }
                }
            }

            Text(
                "请填写主控面板的访问地址，例如 https://panel.example.com\n客户端将使用该地址登录并获取线路",
                style = DS.Font.caption,
                color = palette.mutedForeground,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

// MARK: - 登录

/**
 * 登录页（对应 iOS `LoginView`）。
 * iOS 无 navigationTitle，故顶部不展示标题文字；内容中已内嵌「登录账号」标题。
 */
@Composable
fun LoginView(onRegister: () -> Unit, onForgot: () -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()
    val masterUrl by AppState.masterUrl.collectAsState()
    var account by remember { mutableStateOf(LocalStore.lastAccount ?: "") }
    var password by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var showMaster by remember { mutableStateOf(false) }

    ScreenScaffold(title = "") {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Size.pagePadding)
                .padding(top = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            // 图标 + 标题 + 主控地址（对应 iOS LoginView 顶部 VStack(spacing: 8)）
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(52.dp)
                        .shadow(
                            elevation = 10.dp,
                            shape = RoundedCornerShape(DS.Radius.lg),
                            ambientColor = DS.IconColor.green.copy(alpha = 0.32f),
                            spotColor = DS.IconColor.green.copy(alpha = 0.32f),
                        )
                        .clip(RoundedCornerShape(DS.Radius.lg))
                        .background(Brush.linearGradient(listOf(DS.IconColor.green, DS.IconColor.teal))),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.AccountCircle,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(24.dp),
                    )
                }
                Text("登录账号", style = DS.Font.title, color = palette.foreground)
                Text(
                    text = masterUrl,
                    style = DS.Font.caption,
                    color = palette.mutedForeground,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            AppCard {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    AppTextField(
                        title = "账号",
                        value = account,
                        onValueChange = { account = it },
                        placeholder = "用户名或邮箱",
                    )
                    AppTextField(
                        title = "密码",
                        value = password,
                        onValueChange = { password = it },
                        placeholder = "登录密码",
                        secure = true,
                    )
                    AppButton(
                        title = "登录",
                        icon = Icons.AutoMirrored.Filled.Login,
                        loading = loading,
                    ) {
                        scope.launch {
                            if (account.isEmpty() || password.isEmpty()) {
                                AppState.showToast("请输入账号与密码", BannerKind.Warning)
                                return@launch
                            }
                            loading = true
                            try {
                                AppState.login(account, password)
                                AppState.showToast("登录成功", BannerKind.Success)
                            } catch (e: Exception) {
                                AppState.report(e)
                            } finally {
                                loading = false
                            }
                        }
                    }
                }
            }

            // 底部操作链接（对应 iOS HStack(spacing: 14) + VLine 分隔）
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AuthLink(text = "注册新账号", onClick = onRegister)
                VLine(height = 10.dp)
                AuthLink(text = "找回密码", onClick = onForgot)
                VLine(height = 10.dp)
                AuthLink(text = "更换主控", onClick = { showMaster = true })
            }
        }
    }

    // 「更换主控地址？」确认弹窗（对应 iOS .alert）
    if (showMaster) {
        AlertDialog(
            onDismissRequest = { showMaster = false },
            title = { Text("更换主控地址？", style = DS.Font.section, color = palette.foreground) },
            text = { Text("将退出登录并返回主控地址配置页", style = DS.Font.bodySmall, color = palette.mutedForeground) },
            confirmButton = {
                TextButton(onClick = {
                    showMaster = false
                    AppState.resetMaster()
                }) {
                    Text("确定", color = palette.destructive)
                }
            },
            dismissButton = {
                TextButton(onClick = { showMaster = false }) {
                    Text("取消", color = palette.foreground)
                }
            },
            containerColor = palette.card,
        )
    }
}

// MARK: - 注册（含与 Web 端一致的验证码）

/**
 * 注册页（对应 iOS `RegisterView`）。验证码接口与 Web 端一致，码值直接下发。
 */
@Composable
fun RegisterView(onBack: () -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var captchaInput by remember { mutableStateOf("") }
    var captchaCode by remember { mutableStateOf("") }
    var captchaToken by remember { mutableStateOf("") }
    var captchaEnabled by remember { mutableStateOf(false) }
    var loadingCaptcha by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }

    // 拉取验证码（与 Web 端同一接口，码值直接下发）；失败时静默关闭验证码区（对齐 iOS 行为）
    suspend fun loadCaptcha() {
        loadingCaptcha = true
        try {
            val payload = ApiService.fetchCaptcha()
            captchaEnabled = payload.enabled
            captchaCode = payload.code
            captchaToken = payload.token
            captchaInput = ""
        } catch (e: Exception) {
            captchaEnabled = false
        } finally {
            loadingCaptcha = false
        }
    }

    suspend fun submit() {
        if (username.length < 3) {
            AppState.showToast("用户名至少 3 位", BannerKind.Warning)
            return
        }
        if (password.length < 6) {
            AppState.showToast("密码至少 6 位", BannerKind.Warning)
            return
        }
        if (password != confirm) {
            AppState.showToast("两次输入的密码不一致", BannerKind.Warning)
            return
        }
        if (captchaEnabled && captchaInput.trim().isEmpty()) {
            AppState.showToast("请输入验证码", BannerKind.Warning)
            return
        }
        loading = true
        try {
            AppState.register(username, password, email, captchaToken, captchaInput)
            AppState.showToast("注册成功，已自动登录", BannerKind.Success)
            onBack()
        } catch (e: Exception) {
            AppState.report(e)
            if (captchaEnabled) loadCaptcha()
        } finally {
            loading = false
        }
    }

    // 对应 iOS .task { await loadCaptcha() }
    LaunchedEffect(Unit) { loadCaptcha() }

    ScreenScaffold(title = "注册账号", onBack = onBack) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Size.pagePadding)
                .padding(top = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            AppCard {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    AppTextField(
                        title = "用户名",
                        value = username,
                        onValueChange = { username = it },
                        placeholder = "3-32 位字母/数字/下划线",
                    )
                    AppTextField(
                        title = "密码",
                        value = password,
                        onValueChange = { password = it },
                        placeholder = "至少 6 位",
                        secure = true,
                    )
                    AppTextField(
                        title = "确认密码",
                        value = confirm,
                        onValueChange = { confirm = it },
                        placeholder = "再次输入密码",
                        secure = true,
                    )
                    AppTextField(
                        title = "邮箱（选填）",
                        value = email,
                        onValueChange = { email = it },
                        placeholder = "用于找回密码",
                        keyboardType = KeyboardType.Email,
                    )

                    if (captchaEnabled) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.Bottom,
                        ) {
                            AppTextField(
                                title = "验证码",
                                value = captchaInput,
                                onValueChange = { captchaInput = it },
                                placeholder = "输入右侧 4 位字符",
                                modifier = Modifier.weight(1f),
                            )
                            CaptchaBox(loading = loadingCaptcha, code = captchaCode) {
                                scope.launch { loadCaptcha() }
                            }
                        }
                        Text(
                            "看不清？点击橙色方块刷新验证码",
                            style = DS.Font.caption,
                            color = palette.mutedForeground,
                        )
                    }

                    AppButton(
                        title = "注册并登录",
                        icon = Icons.Filled.PersonAdd,
                        loading = loading,
                    ) {
                        scope.launch { submit() }
                    }
                }
            }

            Text(
                "注册即表示同意站点服务条款；注册后可直接登录使用",
                style = DS.Font.caption,
                color = palette.mutedForeground,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

// MARK: - 找回密码（密保问题）

/**
 * 找回密码页（对应 iOS `ForgotPasswordView`），分「输入账号 → 密保问题重置」两步。
 */
@Composable
fun ForgotPasswordView(onBack: () -> Unit) {
    val palette = LocalPalette.current
    val scope = rememberCoroutineScope()
    var step by remember { mutableStateOf(1) }
    var account by remember { mutableStateOf("") }
    var question by remember { mutableStateOf("") }
    var answer by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }

    suspend fun fetchQuestion() {
        if (account.isEmpty()) {
            AppState.showToast("请输入账号", BannerKind.Warning)
            return
        }
        loading = true
        try {
            question = ApiService.forgotQuestion(account)
            step = 2
        } catch (e: Exception) {
            AppState.report(e)
        } finally {
            loading = false
        }
    }

    suspend fun reset() {
        if (answer.isEmpty()) {
            AppState.showToast("请输入密保答案", BannerKind.Warning)
            return
        }
        if (newPassword.length < 6) {
            AppState.showToast("新密码至少 6 位", BannerKind.Warning)
            return
        }
        loading = true
        try {
            ApiService.resetPassword(account, answer, newPassword)
            done = true
            AppState.showToast("密码已重置", BannerKind.Success)
        } catch (e: Exception) {
            AppState.report(e)
        } finally {
            loading = false
        }
    }

    ScreenScaffold(title = "找回密码", onBack = onBack) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = DS.Size.pagePadding)
                .padding(top = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(DS.Size.gapLarge),
        ) {
            if (done) {
                AppCard {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Filled.CheckCircle,
                            contentDescription = null,
                            tint = palette.onlineText,
                            modifier = Modifier.size(34.dp),
                        )
                        Text("密码已重置", style = DS.Font.section, color = palette.foreground)
                        Text("请使用新密码登录", style = DS.Font.bodySmall, color = palette.mutedForeground)
                        AppButton(title = "返回登录") { onBack() }
                    }
                }
            } else {
                AppCard {
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        if (step == 1) {
                            AppTextField(
                                title = "账号",
                                value = account,
                                onValueChange = { account = it },
                                placeholder = "用户名或邮箱",
                            )
                            AppButton(
                                title = "下一步",
                                icon = Icons.AutoMirrored.Filled.ArrowForward,
                                loading = loading,
                            ) {
                                scope.launch { fetchQuestion() }
                            }
                        } else {
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                Text("密保问题", style = DS.Font.bodySmall, color = palette.mutedForeground)
                                Text(
                                    text = question,
                                    style = DS.Font.body,
                                    color = palette.foreground,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(DS.Radius.md))
                                        .background(palette.muted)
                                        .padding(12.dp),
                                )
                            }
                            AppTextField(
                                title = "密保答案",
                                value = answer,
                                onValueChange = { answer = it },
                                placeholder = "不区分大小写",
                            )
                            AppTextField(
                                title = "新密码",
                                value = newPassword,
                                onValueChange = { newPassword = it },
                                placeholder = "至少 6 位",
                                secure = true,
                            )
                            AppButton(
                                title = "重置密码",
                                icon = Icons.Filled.Key,
                                loading = loading,
                            ) {
                                scope.launch { reset() }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 子组件

/**
 * 文本操作链接（对应 iOS AuthViews 中内联的 `Button` + HStack 字号/字色）。
 * bodySmall + 前景色，带按压缩放反馈。
 */
@Composable
private fun AuthLink(text: String, onClick: () -> Unit) {
    val palette = LocalPalette.current
    val interactionSource = remember { MutableInteractionSource() }
    Text(
        text = text,
        style = DS.Font.bodySmall,
        color = palette.foreground,
        modifier = Modifier
            .clip(RoundedCornerShape(DS.Radius.sm))
            .clickable(interactionSource = interactionSource, indication = null, onClick = onClick)
            .pressableScale(),
    )
}

/**
 * 竖线分隔符（对应 iOS `Components/VLine`；Android 组件库暂未提供同名组件，故在此本地实现）。
 * mutedForeground 38% 透明、宽 1dp。
 */
@Composable
private fun VLine(height: Dp = 10.dp, color: Color? = null) {
    val palette = LocalPalette.current
    Box(
        modifier = Modifier
            .width(1.dp)
            .height(height)
            .background(color ?: palette.mutedForeground.copy(alpha = 0.38f)),
    )
}

/**
 * 注册验证码方块（对应 iOS `RegisterView` 中的验证码 Button 内 ZStack）。
 * 108dp × inputHeight、amber 14% 底 + amber 45% 描边、lg 圆角；加载时显示进度圈。
 */
@Composable
private fun CaptchaBox(loading: Boolean, code: String, onRefresh: () -> Unit) {
    val interactionSource = remember { MutableInteractionSource() }
    val shape = RoundedCornerShape(DS.Radius.lg)
    Box(
        modifier = Modifier
            .width(108.dp)
            .height(DS.Size.inputHeight)
            .clip(shape)
            .background(DS.IconColor.amber.copy(alpha = 0.14f))
            .border(1.dp, DS.IconColor.amber.copy(alpha = 0.45f), shape)
            .clickable(interactionSource = interactionSource, indication = null, onClick = onRefresh)
            .pressableScale(),
        contentAlignment = Alignment.Center,
    ) {
        if (loading) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                color = DS.IconColor.amber,
                strokeWidth = 2.dp,
            )
        } else {
            Text(
                text = code.ifEmpty { "点击获取" },
                style = TextStyle(
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    letterSpacing = 2.sp,
                ),
                color = DS.IconColor.amber,
                maxLines = 1,
            )
        }
    }
}