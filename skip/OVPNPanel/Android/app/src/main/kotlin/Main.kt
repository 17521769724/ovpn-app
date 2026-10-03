package ovpnpanel.module

// Skip 应用在 Android 侧的进程入口与宿主 Activity。
//
// 与 Skip 官方模板（skipapp-hello 的 Android/app/src/main/kotlin/Main.kt）保持一致：
// Skip 只负责把 SwiftUI 源码转译成 Kotlin/Compose 模块，**不会**自动生成这两个类，
// 必须由应用工程自己提供，并与 AndroidManifest.xml 中的
//   <application android:name="...AndroidAppMain">
//   <activity android:name="...MainActivity">
// 完全对应——否则安装后启动即 ClassNotFoundException 闪退。
//
// 包名与 Skip 转译模块的 Kotlin 包一致（ovpnpanel.module），
// Bundle.main 也按该包名查找模块资源（assets/ovpnpanel/module/...）。

import android.app.Application
import android.graphics.Color as AndroidColor
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import skip.lib.*
import skip.model.*
import skip.foundation.*
import skip.ui.*

/// 共享层导出的应用根视图（Sources/OVPNPanel/OVPNPanelApp.swift 的 OVPNPanelRootView）
private typealias AppRootView = OVPNPanelRootView

/// android.app.Application 入口：初始化 SkipFoundation（ProcessInfo）。
/// 必须与 AndroidManifest 中 `<application android:name>` 对应。
open class AndroidAppMain: Application() {
    override fun onCreate() {
        super.onCreate()
        ProcessInfo.launch(applicationContext)
    }
}

/// 承载 Compose 界面的宿主 Activity：把 SwiftUI 根视图渲染出来。
/// 必须与 AndroidManifest 中启动页 `<activity android:name>` 对应。
open class MainActivity: AppCompatActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        UIApplication.launch(this)
        enableEdgeToEdge()

        setContent {
            val saveableStateHolder = rememberSaveableStateHolder()
            saveableStateHolder.SaveableStateProvider(true) {
                PresentationRootView(ComposeContext())
                SideEffect { saveableStateHolder.removeState(true) }
            }
        }
    }
}

/// 状态栏 / 导航栏跟随主题明暗（等价 iOS 的系统栏适配）
@Composable
internal fun SyncSystemBarsWithTheme() {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f

    val transparent = AndroidColor.TRANSPARENT
    val style = if (dark) {
        SystemBarStyle.dark(transparent)
    } else {
        SystemBarStyle.light(transparent, transparent)
    }

    val activity = LocalContext.current as? ComponentActivity
    DisposableEffect(style) {
        activity?.enableEdgeToEdge(
            statusBarStyle = style,
            navigationBarStyle = style
        )
        onDispose { }
    }
}

/// 根容器：包一层 PresentationRoot（负责 sheet / alert / 系统栏等宿主能力）
@Composable
internal fun PresentationRootView(context: ComposeContext) {
    val colorScheme = if (isSystemInDarkTheme()) ColorScheme.dark else ColorScheme.light
    PresentationRoot(defaultColorScheme = colorScheme, context = context) { ctx ->
        SyncSystemBarsWithTheme()
        val contentContext = ctx.content()
        Box(modifier = ctx.modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            AppRootView().Compose(context = contentContext)
        }
    }
}