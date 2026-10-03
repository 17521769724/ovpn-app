package com.ovpn.panel

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.ovpn.panel.core.AppState
import com.ovpn.panel.core.DS
import com.ovpn.panel.core.LocalPalette
import com.ovpn.panel.core.PanelTheme
import com.ovpn.panel.core.VpnManager
import com.ovpn.panel.features.AccountSettingsView
import com.ovpn.panel.features.ActivationView
import com.ovpn.panel.features.AnnouncementsView
import com.ovpn.panel.features.CoinsView
import com.ovpn.panel.features.FeedbackView
import com.ovpn.panel.features.ForgotPasswordView
import com.ovpn.panel.features.HomeView
import com.ovpn.panel.features.InviteView
import com.ovpn.panel.features.LoginView
import com.ovpn.panel.features.OrdersView
import com.ovpn.panel.features.PlansView
import com.ovpn.panel.features.ProfileView
import com.ovpn.panel.features.RechargeView
import com.ovpn.panel.features.RegisterView
import com.ovpn.panel.features.SetupView
import com.ovpn.panel.ui.ToastCard
import com.ovpn.panel.ui.pressableScale
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppState.init(applicationContext)
        VpnManager.init(applicationContext)
        setContent {
            PanelTheme { RootView() }
        }
    }
}

/** 根视图：按阶段切换（配置 → 登录 → 主界面），并承载全局横幅提示。对应 iOS `RootView`。 */
@Composable
private fun RootView() {
    val phase by AppState.phase.collectAsState()
    val palette = LocalPalette.current
    var authRoute by remember { mutableStateOf("login") }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background),
    ) {
        when (phase) {
            AppState.Phase.Setup -> SetupView()
            AppState.Phase.Auth -> when (authRoute) {
                "register" -> RegisterView(onBack = { authRoute = "login" })
                "forgot" -> ForgotPasswordView(onBack = { authRoute = "login" })
                else -> LoginView(
                    onRegister = { authRoute = "register" },
                    onForgot = { authRoute = "forgot" },
                )
            }
            AppState.Phase.Main -> MainNavHost()
        }
        ToastHost()
    }

    // 冷启动同步系统 VPN 状态；回到前台再次同步（在系统「设置」里连接/断开也能正确反映）
    val vpnScope = rememberCoroutineScope()
    LaunchedEffect(Unit) { VpnManager.refreshStatus() }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                vpnScope.launch { VpnManager.refreshStatus() }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
}

/** 主界面导航：Tab 根页面 + 各子页面（对应 iOS 各 Tab 的 NavigationStack push）。 */
@Composable
private fun MainNavHost() {
    val nav = rememberNavController()

    LaunchedEffect(Unit) {
        AppState.startStatusPolling()
    }
    DisposableEffect(Unit) {
        onDispose { AppState.stopStatusPolling() }
    }

    NavHost(navController = nav, startDestination = "main") {
        composable("main") {
            MainTabView(onOpen = { route -> nav.navigate(route) })
        }
        composable("announcements") { AnnouncementsView(onBack = { nav.popBackStack() }) }
        composable("activation") { ActivationView(onBack = { nav.popBackStack() }) }
        composable("recharge") { RechargeView(onBack = { nav.popBackStack() }) }
        composable("coins") { CoinsView(onBack = { nav.popBackStack() }) }
        composable("feedback") { FeedbackView(onBack = { nav.popBackStack() }) }
        composable("orders") { OrdersView(onBack = { nav.popBackStack() }) }
        composable("account") { AccountSettingsView(onBack = { nav.popBackStack() }) }
    }
}

/** 主界面：自定义底部导航（三端样式统一）。对应 iOS `MainTabView`。 */
@Composable
private fun MainTabView(onOpen: (String) -> Unit) {
    var tab by remember { mutableIntStateOf(0) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(LocalPalette.current.background),
    ) {
        Box(modifier = Modifier.weight(1f)) {
            when (tab) {
                0 -> HomeView(onOpen)
                1 -> PlansView(onOpen)
                2 -> InviteView(onOpen)
                else -> ProfileView(onOpen)
            }
        }
        TabBar(selection = tab, onSelect = { tab = it })
    }
}

private data class TabItem(
    val icon: ImageVector,
    val activeIcon: ImageVector,
    val title: String,
    val color: Color,
)

@Composable
private fun TabBar(selection: Int, onSelect: (Int) -> Unit) {
    val palette = LocalPalette.current
    val items = listOf(
        TabItem(Icons.Outlined.Bolt, Icons.Filled.Bolt, "线路", DS.IconColor.green),
        TabItem(Icons.Outlined.Inventory2, Icons.Filled.Inventory2, "套餐", DS.IconColor.teal),
        TabItem(Icons.Outlined.PersonAdd, Icons.Filled.PersonAdd, "邀请", DS.IconColor.lime),
        TabItem(Icons.Outlined.AccountCircle, Icons.Filled.AccountCircle, "我的", DS.IconColor.cyan),
    )
    Column {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(palette.border),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(palette.background)
                .height(DS.Size.tabBarHeight),
        ) {
            items.forEachIndexed { index, item ->
                val selected = index == selection
                val scale by animateFloatAsState(
                    targetValue = if (selected) 1.06f else 1f,
                    animationSpec = spring(
                        dampingRatio = 0.82f,
                        stiffness = Spring.StiffnessLow,
                    ),
                    label = "tabScale",
                )
                val interactionSource = remember { MutableInteractionSource() }
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxSize()
                        .pressableScale(scale = 0.88f)
                        .clickable(interactionSource = interactionSource, indication = null) {
                            onSelect(index)
                        },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        imageVector = if (selected) item.activeIcon else item.icon,
                        contentDescription = item.title,
                        tint = if (selected) item.color else palette.mutedForeground,
                        modifier = Modifier
                            .size(22.dp)
                            .scale(scale),
                    )
                    Spacer(Modifier.height(3.dp))
                    Text(
                        text = item.title,
                        style = TextStyle(
                            fontSize = 11.sp,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                        ),
                        color = if (selected) palette.foreground else palette.mutedForeground,
                    )
                }
            }
        }
    }
}

/** 全局横幅提示（对应 iOS `ToastHost`）：顶部浮层，点按可关闭。 */
@Composable
private fun ToastHost() {
    val toast by AppState.toast.collectAsState()
    Box(modifier = Modifier.fillMaxSize()) {
        androidx.compose.animation.AnimatedVisibility(
            visible = toast != null,
            enter = fadeIn() + scaleIn(initialScale = 0.97f, transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 0f)),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopCenter),
        ) {
            toast?.let { value ->
                ToastCard(
                    message = value.text,
                    kind = value.kind,
                    modifier = Modifier
                        .padding(horizontal = DS.Size.pagePadding)
                        .padding(top = 6.dp)
                        .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {
                            AppState.dismissToast()
                        },
                )
            }
        }
    }
}