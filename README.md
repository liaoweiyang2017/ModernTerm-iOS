# ModernTerm — iOS / iPadOS / Android

独立的原生 SwiftUI + UIKit SSH 客户端，沿用 Modernterm 的应用图标。AppKit 只适用于 macOS，因此移动端采用 UIKit 的 SwiftTerm 终端视图。当前版本 0.2.3，iOS / iPadOS 17+。

[下载 0.2.3 (6) 安装包与校验文件](https://github.com/liaoweiyang2017/ModernTerm-iOS/releases/tag/v0.2.3-build6-open-attachments) · [本次验收记录](specs/007-open-term-attachment/validation.md)

2026-10-18：两端统一桌面最新版图标，版本仍为 0.2.3 (6)，并已更新到 iPhone。[图标与部署验收](specs/005-mobile-icon-alignment/validation.md)。

## 平台入口

- iOS / iPadOS：仓库根目录 `ModerntermIOS.xcodeproj`，下文保留原iOS说明。
- Android：独立 Kotlin / Compose Material 3 工程 [android/](android/README.md)，Android 10+，版本 0.2.3 (6)。
- Android规范与逐项验收：[specs/003-android-material/](specs/003-android-material/spec.md)。

## iOS 功能

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

代码保存在私有 GitHub 项目；Android 与 iOS 均配置 GitHub Actions，保留本机验证流程。生成目录、测试临时密钥和用户凭据不进入 Git。

第三方依赖：SwiftTerm（MIT）、Citadel（MIT）、SwiftNIO/NIOSSH/Crypto（Apache 2.0）、终端配色及对应来源。详见 `Resources/ThirdParty.txt` 和 `Resources/PaletteProvenance.json`。应用自有代码暂保留所有权利，不提供公共开源许可。

## 0.2.0 手机监控工作区

连接后默认进入 Monitor，SSH 终端和 SFTP 通道仅在切换到对应页时建立。底部 Overview 汇总最多 8 个已打开连接；点击某台服务器查看详细数据。

- CPU 总使用率、逻辑核心、型号、系统/内核/架构、负载与运行时间。
- 内存（以 MemAvailable 计算）、交换区、可用时的温度传感器。
- 本地文件系统容量、各磁盘/分区读写速度与 IOPS。
- 各网络接口收发速度/累计流量、TCP in-use 和 TIME_WAIT；排除 lo、veth、docker 和 br-*，其他叠加接口可能重复，不能据此计费。
- 可用时的 NVIDIA 利用率、显存、温度；只读取已有 nvidia-smi。
- Docker 只读统计；需要用户现有权限，不执行 sudo、不更改组或启动/停止容器。
- CPU 平均占用最高的 12 个进程，仅采集命令名，不采集命令参数；ps 显示的是进程生命周期平均值，不是采样间隔瞬时值。
- 原生趋势图保留最近 60 个样本，仅存内存；5/10/30 秒间隔可选，后台断开，重新连接重新采样。

通过 SSH 读取 Linux /proc 和 /sys，未在服务器安装程序。参考 [ServerCat 官方说明](https://servercat.app/en/faq) 的无代理采集方式，自行实现采集、计算与 SwiftUI 界面。非 Linux 仅显示平台信息，SSH/SFTP 仍可用。CPU/网络/I/O 首次采样、重启或计数回退不显示伪造速率。命令响应限制 256 KiB；有 timeout 时整次采集限制 9 秒，GPU/Docker 子命令各 3 秒。无 timeout 时不运行可选 GPU/Docker 命令；基础采集依赖服务器普通系统命令正常返回。

监控数据不会上传到开发者、GitHub 或 iCloud。最多展示 512 个核心计数、32 个文件系统/容器和 256 条磁盘计数。

Debug 专用参数 `--monitor-preview` 可展示明确标注的模拟数据，方便检查小屏布局；不读取凭据、不连接服务器、不保存会话，Release 构建不包含此预览。正式启动不传此参数。

## 0.2.1 LiveContainer 与 Mac 会话迁移

已提供一次性 USB 迁移入口：将受保护的 `ModernTerm-Mac-Import.json` 放入 ModernTerm 自己的数据容器 Documents，启动或回到前台时导入；也可在 Settings → Mac migration 中触发。文件结构为版本 1 的 `MacMigration`，只合并新 UUID，保留现有条目，密码/私钥写入 iOS Keychain。成功后删除输入文件并留下不含凭据的统计回执；失败保留输入文件，不宣称成功。不要把该迁移文件放入仓库、IPA 或云端。

LiveContainer 部署使用正常 Release arm64 `.app` 的 `Payload` IPA；LiveContainer 自己完成签名及沙箱处理。已验证 iPhone 17 / iOS 27.2 / LiveContainer 3.8.10 可启动并完成 Keychain 凭据迁移。该部署不等同于 App Store 安装，不替代 LiveContainer/SideStore 的签名有效期维护。


## 0.2.2 系统键盘修复

终端加入 UIKit 窗口后再申请键盘焦点，切到 Terminal 自动唤起系统输入；右上角提供 Show keyboard，下方辅助按键栏提供收起按钮。监控刷新不会抢回已经收起的键盘，离开终端页时释放焦点。

LiveContainer 更新时可能给替换应用创建新的空数据容器。更新前记录现有容器，更新后核对并重新选择原容器，不要删除原数据或重复导入。应用配置和 Keychain 的隔离标识都与容器有关。

## 0.2.3 RSA-SHA2 网关兼容

支持仅提供 RSA 主机密钥的网关，使用 rsa-sha2-256/512 校验主机签名，保持指纹固定验证；不启用 ssh-rsa/SHA-1 主机签名回退。用户名中的 @ 原样传递。连接失败显示协商、认证、网络或未知阶段，不再只显示 NIOSSH error 1。

SFTP 子系统被拒绝时结束初始化并关闭该子通道，已有终端连接保持可用。依赖固定源码及局部补丁说明见 Vendor/README.md。

额外测试命令：在隔离 Python venv 安装 `paramiko==4.0.0` 后执行 `python Scripts/password_integration.py`，同时运行原 OpenSSH 回归。可通过 `MODERNTERM_DERIVED_DATA` 指定复用构建目录。`python3 Scripts/gateway_probe.py HOST` 只做显式指定服务器的握手检查，主动拒绝主机验证且不发送凭据，不代表登录验收。

### 自动主题与手机键盘

`Ubuntu Neo (Auto)` 跟随应用有效浅色/深色外观；`Ubuntu Neo Dark` 和 `Ubuntu Neo Light` 为固定配色。若应用界面已变浅但终端仍深色，先核对 Terminal colors 是否选中 Auto。

电脑 Device Hub 手机预览可能使系统进入外接键盘状态，即使 Capture Keyboard 已关闭，也可能仅显示辅助栏。若手机系统文字键盘不弹出，退出电脑端 Device Hub，再在手机终端点击右上角键盘按钮。本次真机对照由用户确认恢复；不需要改密码、重建会话或重装输入法。

## 0.2.3 (6) 跨平台加密 SSH 连接包

iOS 和 Android 顶部的 **SSH transfer** 支持多选导出、全选、多个 `.term` 文件批量导入。默认仅配置，可选包含保存的密码、私钥和口令；整个文件由独立密码加密，不能直接用文本查看连接信息。导入先预览，已有 UUID 默认跳过，可作为新副本导入；主机信任不转移，也不会自动连接。文件密码至少 12 个字符，遗忘无法恢复。

[格式与互通测试](shared/term-transfer/README.md) · [需求与验收](specs/004-term-transfer/spec.md) · [实际验证记录](specs/004-term-transfer/validation.md)。本次 iOS 只完成模拟器与构建验证，真机部署由用户后续执行。

导出时可选 **Export N connections** 保存文件，或 **Share N connections** 打开系统分享面板，选择微信等已安装应用。微信未出现在第一屏时可点“更多”。分享的是加密 `.term` 附件，文件密码需另行告知接收方。短密码等错误会弹窗提示并保留输入。

收到 `.term` 后：Android 在微信/文件管理器选择“用其他应用打开 → ModernTerm”；iOS 原生安装可选择 ModernTerm，自动进入文件密码和导入预览。当前 iPhone 的 LiveContainer 安装方式需“分享 → LiveContainer → ModernTerm”。解密后仍需确认导入，已有连接不会覆盖。请先完成或取消当前导入，再打开另一个附件。
