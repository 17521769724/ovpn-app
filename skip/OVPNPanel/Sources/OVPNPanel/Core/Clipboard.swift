import Foundation
#if SKIP
// Skip：Android 侧使用 Kotlin ClipboardHelper（见 Android 模块 ClipboardHelper.kt）
import com.ovpn.panel.ClipboardHelper
#endif
#if !SKIP
import UIKit
#endif

/// 系统剪贴板。
///
/// - iOS：`UIPasteboard.general`
/// - Android：Kotlin `ClipboardHelper`（`android.content.ClipboardManager`）
enum Clipboard {
    static func copy(_ text: String) {
        #if SKIP
        ClipboardHelper.shared.copy(text: text)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
