package com.ovpn.panel

import android.content.ClipData
import android.content.ClipboardManager
import android.os.Handler
import android.os.Looper

/**
 * 系统剪贴板（对应 Swift 侧 `Clipboard.copy(_:)`）。
 * 剪贴板操作必须在主线程执行，这里统一切回主线程。
 */
object ClipboardHelper {

    /** Swift 侧以 `ClipboardHelper.shared` 形式访问（Skip 转译约定） */
    val shared: ClipboardHelper get() = this

    private val mainHandler = Handler(Looper.getMainLooper())

    fun copy(text: String) {
        mainHandler.post {
            val manager = AppEnv.appContext
                .getSystemService(ClipboardManager::class.java) ?: return@post
            manager.setPrimaryClip(ClipData.newPlainText("OVPN", text))
        }
    }
}
