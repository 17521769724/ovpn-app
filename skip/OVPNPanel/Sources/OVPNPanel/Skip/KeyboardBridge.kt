package com.ovpn.panel

import android.content.Context
import android.view.inputmethod.InputMethodManager

/**
 * 软键盘控制（对应 Swift 侧 `Keyboard.dismiss()`）。
 *
 * 点击页面空白处时收起键盘：从当前前台 Activity 的窗口取输入法管理器并隐藏。
 */
object KeyboardBridge {

    /** Swift 侧以 `KeyboardBridge.shared` 形式访问（Skip 转译约定） */
    val shared: KeyboardBridge get() = this

    fun dismiss() {
        val activity = AppEnv.currentActivity ?: return
        val manager = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager ?: return
        runCatching {
            manager.hideSoftInputFromWindow(activity.window.decorView.windowToken, 0)
        }
    }
}