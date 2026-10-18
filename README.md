<p align="center">
  <img src="shared/branding/Modernterm.png" width="112" alt="ModernTerm icon">
</p>

<h1 align="center">ModernTerm</h1>
<p align="center">手机上的 SSH 终端、Linux 监控与 SFTP 文件工作区</p>
<p align="center">SwiftUI · Kotlin / Material 3 · iOS / iPadOS 17+ · Android 10+ · MIT</p>

ModernTerm 把远程终端、服务器状态和文件操作放在同一个移动工作区。它面向需要随时查看服务器、执行命令、修改配置或传输文件的开发者与运维人员。iOS 和 Android 分别采用原生界面，并通过加密 `.term` 文件交换连接配置。

**当前版本：0.2.4（构建号 7）**。项目仍在持续完善，具体测试范围和限制见下文。

[下载安装包](https://github.com/liaoweiyang2017/ModernTerm-iOS/releases/tag/v0.2.4) · [使用指南](#快速开始) · [源码构建](#从源码构建) · [反馈问题](https://github.com/liaoweiyang2017/ModernTerm-iOS/issues) · [桌面版 Modernterm](https://github.com/liaoweiyang2017/Modernterm)

## 为什么使用 ModernTerm

- **一个连接，三种工作方式。** 查看 Monitor、打开 Terminal、使用 SFTP，按任务切换；监控时无需先打开交互终端。
- **保留平台习惯。** iPhone/iPad 使用 SwiftUI 与 UIKit；Android 使用 Kotlin、Jetpack Compose 和 Material 3，支持大屏布局及 Android 12+ 动态配色。
- **连接配置随设备迁移。** 多选 SSH 连接，导出为完整加密的 `.term` 文件，可通过微信、邮件或系统分享发送，再在另一平台输入文件密码导入。
- **服务器无需安装监控代理。** 通过已有 SSH 连接读取 Linux 系统信息；GPU、Docker 等指标在现有工具及权限允许时显示。
- **凭据留在本地。** iOS 使用 Keychain，Android 使用 Keystore 保护凭据；无需注册项目账号，不依赖开发者的云同步服务，Android 不要求 Google Play Services。
- **清晰且可维护。** 两个平台工程独立，复用协议、测试向量、配色和监控脚本；需求与验收文档随源码保存。自有代码采用 MIT 许可。

## 功能一览

| 能力 | iOS / iPadOS | Android |
| --- | --- | --- |
| SSH 交互终端、最多 8 个会话 | SwiftTerm / UIKit | 本地打包 xterm.js / WebView |
| 密码、RSA / Ed25519 私钥及私钥口令 | 支持 | 支持 |
| RSA-SHA2 主机签名、SHA-256 指纹确认 | 支持 | 支持 |
| 连接搜索、收藏、编辑、分组信息 | 支持 | 支持 |
| SFTP 浏览、上传、下载、删除、UTF-8 编辑 | 支持 | 支持 |
| Linux 监控、趋势图、多连接概览 | 支持 | 支持 |
| 宏命令、可选 OSC 7 目录跟随 | 支持 | 支持 |
| 18 套终端配色、Ubuntu Neo 自动明暗主题 | 支持 | 支持 |
| `.term` 多选导出、批量导入、系统分享 | 支持 | 支持 |
| 从其他应用打开 `.term` | 系统文档关联；LiveContainer 见下文 | 系统打开方式和分享接收 |
| 本地凭据保护 | Keychain | Android Keystore |

当前应用界面主要为英文。桌面项目与移动项目独立发布，本仓库不包含 Windows/macOS 安装包。

## 界面预览

以下为合成测试数据的导入预览，展示手机和平板布局，不包含真实服务器凭据。

| iOS | Android 手机 |
| --- | --- |
| <img src="specs/004-term-transfer/screenshots/ios-import.png" width="300" alt="iOS 导入预览"> | <img src="specs/004-term-transfer/screenshots/android-phone-import.png" width="300" alt="Android 导入预览"> |

<details>
<summary>Android 平板预览</summary>

![Android 平板导入预览](specs/004-term-transfer/screenshots/android-tablet-import.png)

</details>

## 下载与安装

请从 [v0.2.4 Release](https://github.com/liaoweiyang2017/ModernTerm-iOS/releases/tag/v0.2.4) 下载：

| 文件 | 用途 |
| --- | --- |
| `ModernTerm-Android-0.2.4.apk` | Android 10+ 安装包 |
| `ModernTerm-iOS-0.2.4.ipa` | iOS / iPadOS 安装包，需相应签名或 LiveContainer 环境 |
| `SHA256SUMS.txt` | 安装包 SHA-256 校验值 |
| `build-info.txt` | 源码提交、版本和构建信息 |

### Android

下载 APK 后，由系统安装器完成安装；首次安装可能需要允许所用下载应用安装软件。后续同签名 Release 可覆盖升级。Debug 包使用独立包名，数据不会与 Release 混用。终端需要可用的 Android System WebView，终端资源随应用打包，不从 CDN 加载。

**华为 / 鸿蒙：** 仅适用于仍支持安装和运行 Android APK 的系统。Android 10 最低版本不代表兼容所有鸿蒙设备；原生 HarmonyOS/HAP 不在本项目范围，Mate 70 尚未进行实体机验收。

### iOS / iPadOS

- **Xcode 安装：** 从源码构建，选择自己的 Apple Development Team，按设备要求完成签名。
- **LiveContainer：** 将 IPA 导入 LiveContainer，更新时选择替换原 ModernTerm，并核对使用原数据容器。不要删除原容器来处理更新问题。
- Release IPA 不是 App Store 安装包，不能作为无需签名的独立应用直接安装。签名有效期和 LiveContainer 的维护由所用安装方式决定。

## 快速开始

1. 点击 **Add server**，填写 Host、Port 和 Username。Host 填域名或 IP，用户名单独填写；用户名中的 `@` 原样保留。
2. 选择密码或私钥认证，保存连接。
3. 首次连接核对服务器 **SHA-256 主机指纹**，确认可信后继续。已保存指纹发生变化时应用会拒绝连接，请先查明原因。
4. 在 **Monitor / Terminal / SFTP** 间切换。终端提供 Tab、Esc、Ctrl 和方向键辅助栏。
5. 使用 **Overview** 查看已打开连接的概览，使用设置调整主题、字体与监控间隔。

应用进入后台时会断开连接，回到前台后手动重连。系统文件操作可有有限宽限期，但不提供永久后台保活。

## 加密连接包：备份、分享与接收

### 导出或分享

1. 打开顶部 **SSH transfer**，选中一条或多条已保存连接，也可全选。
2. 默认只导出配置。需要时勾选包含已保存的密码、私钥和私钥口令。
3. 两次输入独立的文件密码，至少 12 个字符。
4. 选择 **Export N connections** 保存到文件，或 **Share N connections** 打开系统分享面板，选择微信或其他已安装应用。

整个 `.term` 文件都经过加密，包含的主机、用户名和凭据不会以明文保存。文件密码不会随附件发送，请通过另一种方式告知接收方；遗忘文件密码无法恢复。分享面板关闭不等于对方已收到文件。

### 接收别人发来的 `.term`

- **Android：** 在微信或文件管理器中选择“其他应用打开 → ModernTerm”，也可从系统分享面板选择 ModernTerm。
- **iOS 原生安装：** 在文件的系统打开/分享选项中选择 ModernTerm。
- **iOS LiveContainer：** 选择“分享 → 更多 → LiveContainer → ModernTerm”。系统识别的是宿主应用，需要多这一步。

进入文件密码页后解密，检查 **Import preview**，再点击导入。也可以在应用内选择多个 `.term` 文件批量处理。

每批最多 20 个文件，合计 16 MiB，最多 200 条连接。已有 UUID 默认跳过，可选择导入为新副本；冲突版本需明确选择，不自动覆盖现有连接。取消不修改连接，导入也不会自动连接服务器。主机信任记录不转移，首次连接仍需确认指纹。

格式使用 AES-256-GCM 和 PBKDF2-HMAC-SHA256（600,000 次），文件密码采用 NFC 规范化。协议与跨平台合成测试向量见 [shared/term-transfer](shared/term-transfer/README.md)。

## 监控与文件操作

**Linux 监控**包含 CPU/逻辑核心、负载、内存/交换区、文件系统容量、磁盘读写/IOPS、网络收发/TCP、可用温度传感器，以及权限允许时的 NVIDIA、Docker 和进程统计。趋势图保留最近 60 个样本，仅存内存，采样间隔可选 5/10/30 秒。非 Linux 主机可能仅显示平台信息。

**SFTP**支持目录浏览、文件上传下载、多选删除和最大 2 MiB 的 UTF-8 文本编辑。上传不覆盖同名目标；编辑会检查基线内容并通过临时文件替换，仍存在比较与替换之间的竞态，不是多人协作事务。非空目录受保护，不提供递归传输或断点续传。

## 安全与隐私

- iOS 凭据使用 `WhenUnlockedThisDeviceOnly` Keychain；Android 凭据使用 Keystore 保护，不将密码与普通连接配置混存。
- SSH 首次指纹确认，指纹变化拒绝连接；支持 RSA-SHA2 主机签名，不启用 `ssh-rsa` / SHA-1 主机签名回退。
- 应用不提供遥测、开发者云端凭据同步或监控数据上传。用户主动通过第三方应用分享的文件由所选应用处理。
- 监控只使用现有权限，不执行 sudo、不安装代理、不自动调整 Docker 用户组。
- 日志或 Issue 中不要提交密码、私钥、文件密码、真实连接导出包或未脱敏截图。
- 测试目录中的密钥和 `.term` 均为合成数据，不应用于真实服务器。

## 已知限制与常见问题

- 没有本地 Shell、SSH 隧道、自动重连、永久后台运行、递归 SFTP 或工作区恢复。
- GPU/Docker 指标依赖远端已有工具及权限；进程 CPU 指标是进程生命周期平均值。叠加网络接口可能重复计数，不适合作为计费依据。
- OSC 7 目录跟随需要远端 Shell 主动报告路径，应用不会自动修改启动脚本。
- **Android 终端键盘：** 点击固定的 **Keyboard** 按钮或轻点终端区域；辅助栏横向滚动不会隐藏键盘入口。0.2.4 修复了早于 SSH 通道创建的尺寸更新丢失，减少 `top` 等全屏程序的列折行问题。ColorOS 17 仍需实际机型复测。
- **手机键盘不弹出：** 电脑端 Device Hub 预览可能使 iOS 进入外接键盘状态。退出电脑预览后，再点 Terminal 的键盘按钮。
- **浅色界面但终端仍深色：** 确认终端配色选的是 `Ubuntu Neo (Auto)`；Dark/Light 为固定主题。
- **文件打不开：** 先完成或取消当前传输，再重新打开；确认附件完整且文件密码正确。LiveContainer 按上文宿主转交路径操作。
- 第三方聊天应用、OEM 文件管理器和不同鸿蒙系统不保证行为一致。实机系统附件交接已验证，但微信会话端到端收件未覆盖所有平台。

## 从源码构建

```sh
git clone https://github.com/liaoweiyang2017/ModernTerm-iOS.git
cd ModernTerm-iOS
```

### iOS / iPadOS

需要 macOS、支持项目 Swift 依赖的 Xcode 和 XcodeGen。工程配置源为 `project.yml`，依赖版本锁定在工程的 `Package.resolved` 中。

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project ModerntermIOS.xcodeproj -scheme ModerntermIOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$HOME/Library/Caches/ModernTerm-build" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

真机构建在 Xcode 中配置自己的签名团队。SwiftTerm 固定为 1.18.0，Citadel/NIOSSH 的局部兼容补丁与原因见 [Vendor/README.md](Vendor/README.md)。

### Android

需要 JDK 17、Android SDK 36、Build Tools 35.0.0 和可用的 System WebView。配置 `ANDROID_HOME` 或本机忽略的 `android/local.properties`。

```sh
cd android
./gradlew lintDebug testDebugUnitTest assembleDebug
```

产物位于 `android/app/build/outputs/apk/debug/`。发布版需要自己的签名密钥；不要提交 keystore 或签名密码。终端资源、共享资源同步和签名步骤见 [Android 开发说明](android/README.md)。

## 测试与发布方式

**本项目采用本地测试、构建和 GitHub Release 发布，不使用 GitHub Actions。** 历史验收中的 CI 记录仅代表当时的结果。

- iOS：在 Xcode 中运行 `ModerntermTests` / `ModerntermUITests`，或用 `xcodebuild test` 指定可用模拟器。
- Android：运行 JVM/lint 检查及 `connectedDebugAndroidTest`；SSH 集成测试先启动 [隔离测试服务器](android/README.md#integration-tests)。
- SSH/SFTP 集成脚本创建一次性测试凭据，不读取开发者的真实 SSH 配置或私钥。
- `.term` 测试覆盖格式互通、密码失败、数据边界、去重冲突、存储恢复和系统文件交接；模拟器通过不等于所有实体机通过。

[0.2.4 发布规范与验收](specs/008-public-release/validation.md) · [附件接收实机记录](specs/007-open-term-attachment/validation.md) · [跨平台格式验收](specs/004-term-transfer/validation.md)

## 目录结构

```text
Sources/                 iOS 应用与 SSH/SFTP/传输实现
Resources/               iOS 资源、配色与第三方声明
Tests/、UITests/           iOS 单元和界面测试
android/                 Kotlin / Compose 应用与本地构建脚本
shared/                  加密格式向量、共享图标等资源
Vendor/                  固定的 Swift SSH 依赖与兼容补丁
Scripts/                 iOS 集成测试和资源生成工具
specs/                   需求、方案、任务与验收记录
```

## 贡献与反馈

欢迎提交可复现的问题和范围清晰的 PR。报告问题时写明平台、系统版本、应用版本、安装方式、复现步骤和预期结果，并脱敏日志。新功能先说明需求与边界，再给出最小方案；保持平台原生交互，避免为单一功能引入大型框架。提交前运行与改动相关的测试，并同步更新验收记录。

## 许可证与致谢

项目自有代码使用 [MIT License](LICENSE)，允许使用、修改和商业分发，需保留版权与许可声明。第三方依赖及素材继续适用各自许可。

感谢 SwiftTerm、Citadel、SwiftNIO/NIOSSH、Swift Crypto、SSHJ、Bouncy Castle、xterm.js、AndroidX/Compose 及配色项目。详见 [iOS 第三方声明](Resources/ThirdParty.txt)、[Android 第三方声明](android/app/src/main/assets/licenses/NOTICE.txt)、[终端许可](android/app/src/main/assets/terminal/XTERM-LICENSE)和[图标来源](shared/branding/README.md)。
