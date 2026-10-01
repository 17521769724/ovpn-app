# OVPN 三端客户端

OpenVPN 流控系统的三端客户端（iOS / Android / Windows），界面与 Web 端用户中心保持一致。

## 目录

| 目录 | 说明 | 状态 |
|---|---|---|
| `ios/` | iOS 客户端（Swift + SwiftUI，未签名 IPA 通过 TrollStore 安装） | 开发中（M1：界面与账号流程） |
| `android/` | Android 客户端（Kotlin，最低 Android 9） | 计划中 |
| `windows/` | Windows 客户端（C++，Win7–Win11） | 计划中 |

## 功能

- 首次启动填写主控地址（例如 `http://your-domain:3000`）
- 登录 / 注册 / 找回密码（密保问题）
- 主页：选择服务器（实时状态、负载、在线数、倍率）→ 选择线路 → 连接
- 套餐购买、我的订单、公告、激活码、金币与邀请、问题反馈、账号设置
- 数据全部来自主控 API（`/api/v1/*`），组件化原生界面，非网页套壳

## iOS 构建

```bash
cd ios
xcodegen generate                 # 需要 XcodeGen
open OVPNPanel.xcodeproj          # 或用 xcodebuild 构建
```

CI 会自动构建并产出未签名 IPA（见 `.github/workflows/ios-ipa.yml`）。

## 三端 UI 一致性

颜色 / 圆角 / 控件高度 / 字号等设计令牌集中定义在
`ios/Sources/OVPNPanel/Core/Theme.swift`，Android 与 Windows 端使用同一套数值。

## 说明

- iOS 端的 VPN 连接将使用 NetworkExtension(Packet Tunnel) + 开源 OpenVPN 内核实现（GPL/AGPL 许可，本项目对应开源）。