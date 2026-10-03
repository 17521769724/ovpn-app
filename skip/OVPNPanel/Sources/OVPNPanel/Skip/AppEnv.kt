package com.ovpn.panel

import android.app.Activity
import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri

/**
 * 应用级 Context 持有者。
 *
 * Skip 转译出的 Compose 代码运行在宿主 Activity 内，
 * 但剪贴板、SharedPreferences、启动浏览器、启动 VpnService 都需要一个 Context。
 * 这里通过 [AppEnvInitializer]（ContentProvider）在进程启动时自动注入，
 * 避免依赖任何 Skip 内部实现细节。
 *
 * 同时通过 [Application.registerActivityLifecycleCallbacks] 跟踪当前前台 Activity：
 * 系统 VPN 授权窗口必须从一个 Activity 启动（Android 10+ 对后台启动 Activity 有严格限制），
 * 这是「点了连接却不弹出授权弹窗」问题的根因修复。
 */
object AppEnv {

    @Volatile
    private var ref: Context? = null

    @Volatile
    private var activity: Activity? = null

    /** 应用级 Context（applicationContext），进程启动后一定可用 */
    val appContext: Context
        get() = ref ?: error("AppEnv 尚未初始化：请确认 AndroidManifest 中已声明 AppEnvInitializer")

    /** 当前前台 Activity（可能为空：应用在后台时） */
    val currentActivity: Activity?
        get() = activity

    internal fun install(context: Context) {
        val app = context.applicationContext
        ref = app
        if (app is Application) {
            app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
                override fun onActivityResumed(activity: Activity) {
                    AppEnv.activity = activity
                    VpnBridge.onHostResumed()
                }

                override fun onActivityPaused(activity: Activity) {
                    if (AppEnv.activity === activity) AppEnv.activity = null
                }

                override fun onActivityCreated(activity: Activity, savedInstanceState: android.os.Bundle?) {}
                override fun onActivityStarted(activity: Activity) {}
                override fun onActivityStopped(activity: Activity) {}
                override fun onActivitySaveInstanceState(activity: Activity, outState: android.os.Bundle) {}
                override fun onActivityDestroyed(activity: Activity) {}
            })
        }
    }
}

/**
 * 借 ContentProvider 的创建时机完成 Context 注入。
 *
 * ContentProvider 会在 Application.onCreate 之前被系统实例化，
 * 因此早于任何 UI / 服务代码，是最可靠的自动初始化入口。
 * 需要在 AndroidManifest.xml 中声明（见 app 模块清单）。
 */
class AppEnvInitializer : ContentProvider() {

    override fun onCreate(): Boolean {
        context?.let { AppEnv.install(it) }
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0
}