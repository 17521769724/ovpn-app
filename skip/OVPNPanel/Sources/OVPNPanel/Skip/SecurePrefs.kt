package com.ovpn.panel

import android.content.Context

/**
 * 凭据存储（对应 iOS 的 Keychain 封装 `SecureStore`）。
 *
 * iOS 侧使用 Keychain；Android 侧使用私有模式 `SharedPreferences`
 * （文件位于应用私有目录 `/data/data/com.ovpn.panel/shared_prefs/`，
 *  其他应用无法读取，满足本应用的令牌/密码保存需求）。
 */
object SecurePrefs {

    /** Swift 侧以 `SecurePrefs.shared` 形式访问（Skip 转译约定） */
    val shared: SecurePrefs get() = this

    private const val FILE_NAME = "ovpn_secure_store"

    private val prefs by lazy {
        AppEnv.appContext.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)
    }

    fun save(account: String, value: String) {
        prefs.edit().putString(account, value).apply()
    }

    fun load(account: String): String? = prefs.getString(account, null)

    fun clear(account: String) {
        prefs.edit().remove(account).apply()
    }
}
