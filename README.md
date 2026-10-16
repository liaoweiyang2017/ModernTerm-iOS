# ModernTerm for iOS / iPadOS

独立的原生 SwiftUI + UIKit SSH 客户端，沿用 Modernterm 的应用图标。AppKit 只适用于 macOS，因此移动端采用 UIKit 的 SwiftTerm 终端视图。首版 0.1.0，iOS / iPadOS 17+。

## 功能

- SSH 交互终端、最多 8 个会话、服务器收藏/编辑/分组信息。
- 密码和 OpenSSH Ed25519 / RSA 私钥登录（支持私钥口令）；凭据使用 iOS Keychain `WhenUnlockedThisDeviceOnly`，正常读取不弹授权，不同步 iCloud。
- 首次连接显示 SHA-256 主机指纹，确认后固定保存；指纹改变时拒绝连接。
- SFTP 目录导航、文件上传、下载到系统分享/文件面板、多选删除（非空目录受保护）、UTF-8 文本编辑与冲突检查。
- 原生终端键盘补充栏：Tab、Esc、Ctrl-C/D、方向键；18 个终端配色、字体大小、明暗主题。
- Linux 主机/负载/内存/根分区信息、保存的宏命令、可选 OSC 7 目录跟随。
- iPhone 自适应导航、iPad 会话侧栏；英文界面，后续可通过 String Catalog 本地化。

## 平台差异和明确边界

这是独立的移动实现，不是 macOS Qt 二进制移植或 WindTerm/MobaXterm 原代码移植。

- iOS 没有桌面本地 Shell；不会伪装提供系统终端。
- 切到后台主动断开 SSH，前台手动重连；不宣称 iOS 可永久后台保活。
- 首版不含 SSH 隧道、自动重连、桌面分屏、工作区恢复、传输断点续传、目录递归上传下载、自动读取 Mac 服务器凭据。
- 目录同步需远端 Shell 发送匹配主机的 OSC 7 报告；不会偷偷改 shell 启动脚本。
- 编辑仅限 UTF-8、2 MiB，保存前后核对原内容，临时文件写完后通过服务端 `mv -f --` 替换，要求远端提供该命令。比较与替换之间仍存在短暂竞态，SFTP 不提供事务锁；不适用于多人并发编辑。上传不覆盖同名目标。
- 下载流式写本机临时目录，分享后可保存到“文件”；用户自己选择保存位置。不会自动使用或删除 iCloud 文件。
- 服务器监控针对 Linux；其他系统可能显示部分指标或不支持。

## 使用本机 Xcode

已使用 Xcode 27.1。打开 `ModerntermIOS.xcodeproj`，选择 `ModerntermIOS` scheme 和 iPhone / iPad 模拟器。

工程配置源是 `project.yml`，修改后运行 `xcodegen generate`。依赖锁定于 `ModerntermIOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`。

```sh
xcodegen generate
xcodebuild -project ModerntermIOS.xcodeproj -scheme ModerntermIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

SwiftTerm 固定为 1.18.0；1.20.0 的构建信息插件在本机 Xcode 的 iOS SDK 构建中错误定位宿主工具，因此选择不含该插件的稳定版本，不需要跳过插件验证。

真机安装需要在 Xcode → Signing & Capabilities 选择自己的 Apple Development Team 和连接的 iPhone/iPad。未提供团队时只验证模拟器和未签名真机构建，不声称可直接分发 IPA 或已通过 App Store 审核。

## 测试与安全

`ModerntermTests` 验证会话校验、密码与配置分离、Keychain 读写、路径引用和配色。`Scripts/integration.py` 创建临时本机 OpenSSH 服务和一次性密钥，在模拟器验证 SSH/SFTP；不读取用户服务器、SSH 配置或密钥。

代码只备份到私有 GitHub 项目；没有 GitHub Actions。生成目录、测试临时密钥和用户凭据不进入 Git。

第三方依赖：SwiftTerm（MIT）、Citadel（MIT）、SwiftNIO/NIOSSH/Crypto（Apache 2.0）、终端配色及对应来源。详见 `Resources/ThirdParty.txt` 和 `Resources/PaletteProvenance.json`。应用自有代码暂保留所有权利，不提供公共开源许可。
