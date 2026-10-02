package com.ovpn.panel

import android.content.Intent
import android.net.Uri

/**
 * 打开外部链接（对应 iOS 的 `SFSafariViewController` 支付页）。
 *
 * Android 没有 SFSafariViewController 的等价控件，
 * 采用与既有 Kotlin 版一致的做法：交给系统浏览器 / Chrome Custom Tabs 处理。
 */
object IntentLauncher {

    fun openURL(url: String) {
        runCatching {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            AppEnv.appContext.startActivity(intent)
        }
    }
}
