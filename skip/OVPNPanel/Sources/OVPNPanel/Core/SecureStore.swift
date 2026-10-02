import Foundation

#if SKIP
// Skip：Android 侧使用 Kotlin SecurePrefs（见 Android 模块 SecurePrefs.kt）
import com.ovpn.panel.SecurePrefs
#endif

/// 令牌与凭据安全存储。
///
/// - iOS：Keychain（`kSecClassGenericPassword`）
/// - Android：Kotlin `SecurePrefs`（`SharedPreferences` 私有模式，等价封装）
///
/// 两端对外暴露同一套 `save / load / clear` 接口，调用方无感知。
/// 命名避免与 TunnelKit 的 `Keychain` 冲突。
enum SecureStore {
    static let tokenAccount = "app.token"
    /// 连接 VPN 用的账号密码（登录成功后保存，连接时自动使用）
    static let passwordAccount = "vpn.password"

    #if SKIP
    // Android：委托给 Kotlin 侧实现（见 Android 模块 SecurePrefs.kt）
    static func save(_ value: String, account: String = tokenAccount) {
        SecurePrefs.shared.save(account: account, value: value)
    }

    static func load(account: String = tokenAccount) -> String? {
        SecurePrefs.shared.load(account: account)
    }

    static func clear(account: String = tokenAccount) {
        SecurePrefs.shared.clear(account: account)
    }
    #else
    private static let service = "com.ovpn.panel"

    static func save(_ value: String, account: String = tokenAccount) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(account: String = tokenAccount) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    static func clear(account: String = tokenAccount) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
    #endif
}
