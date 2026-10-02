import Foundation
import NetworkExtension
import TunnelKit
import TunnelKitOpenVPNAppExtension

/// 数据包隧道扩展：基于 TunnelKit 的 OpenVPN 实现
class PacketTunnelProvider: OpenVPNTunnelProvider {

    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        dataCountInterval = 3

        // 主 App 若无法写钥匙串（entitlements 受限场景），会在 providerConfiguration
        // 中传入明文密码，这里在扩展进程内补写钥匙串引用，保证账号密码认证可用。
        if let proto = protocolConfiguration as? NETunnelProviderProtocol,
           proto.passwordReference == nil,
           let password = proto.providerConfiguration?["__plain_password"] as? String,
           let username = proto.username {
            let group = (proto.providerConfiguration?["appGroup"] as? String) ?? "group.com.ovpn.panel"
            let context = proto.providerBundleIdentifier ?? "com.ovpn.panel.tunnel"
            if let reference = try? Keychain(group: group).set(password: password, for: username, context: context) {
                proto.passwordReference = reference
            }
        }

        try await super.startTunnel(options: options)
    }
}