# Android 移植调研

日期：2026-10-17。状态：规范阶段的技术建议，未实施、未运行 Android 测试、未验证任何华为真机。以下区分上游事实与项目决策；库和构建工具的确切版本须在实施时锁定并验证。

## 系统版本与构建目标

- Android 10 对应 API 29。`minSdk` 决定最低运行平台，`compileSdk` 决定编译时可用 API，`targetSdk` 声明适配的平台行为；提高后两者不等于提高最低安装版本。建议 `minSdk = 29`，不要为了支持旧手机把 `targetSdk` 降到 29。新 API 必须运行时守卫或兼容实现。[Android uses-sdk](https://developer.android.com/guide/topics/manifest/uses-sdk-element)、[构建配置](https://developer.android.com/build)
- 建议本阶段以 `compileSdk = 36`、`targetSdk = 36` 作为已发布且可核验的基线，不声称它是当前最新 SDK。API 36 对应 Android 16；构建工具、AGP、Kotlin、Compose BOM 组合待实施时一起锁定。Google Play 当前要求新应用/更新以 API 36 或以上为目标；本次 GitHub APK 分发无需因此提高 `minSdk`。[Android 16 SDK](https://developer.android.com/about/versions/16/setup-sdk)、[Play 目标 API 要求](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)
- Android APK 的 `versionName` 建议与现有 iOS 保持 `0.2.3`，初始 `versionCode = 5`；后续同名版本重发也必须有单调递增的 Android 构建号，最终以仓库版本事实为准。此项为项目版本政策建议，并非跨平台系统要求。

## Material 3 与旧系统

采用 Kotlin、Jetpack Compose 和 Material 3 的原生 Android 外壳。官方主题示例仅在 Android 12/API 31 及以上调用动态配色，低版本使用自定义浅色/深色配色。因此 Android 10 不需要丢失 Material 3 视觉与交互，只需提供静态配色回退。主题应覆盖界面和终端，并测试系统浅深色变化。[Material 3 官方指南](https://developer.android.com/develop/ui/compose/designsystems/material3)

所选 Compose/Material3 发布版本及其传递依赖的最低 API 尚待构建验证；不能用主题示例代替依赖兼容性证明。实施门槛为依赖合并 Manifest 的最低要求不超过 API 29、Lint 无未守卫的新 API、API 29 模拟器启动及主要界面测试通过。[Material3 版本记录](https://developer.android.com/jetpack/androidx/releases/compose-material3)

## 无实体设备的验证路径

GitHub 官方确认 hosted Linux runners 支持 Android SDK 硬件加速。上游 `ReactiveCircus/android-emulator-runner` 提供 Ubuntu、KVM 权限配置和 API 29 示例。建议 GitHub Actions 使用 x86_64 Ubuntu runner，先验证 `/dev/kvm` 可用，再运行模拟器；锁定 runner 标签、SDK 镜像和第三方 action 的 commit SHA。[GitHub runner 文档](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[硬件加速公告](https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/)、[Emulator Runner 上游](https://github.com/ReactiveCircus/android-emulator-runner)

建议必跑矩阵为 API 29（最低版本）、36（目标版本）；API 31 可作为动态色分界的扩展作业。每次提交执行编译、Lint、JVM 单测；完整集成作业执行 Compose UI 与真实 SSH/SFTP 测试夹具，输出 APK、测试报告及失败截图。测试夹具使用一次性账号/密钥，覆盖 RSA-SHA2、密码/密钥认证、首次指纹确认与指纹变更拒绝、PTY、含 `@` 用户名、SFTP 和监控。此为本项目测试设计，不是已通过结果；当前仓库 Actions 尚未启用，须在后续实施阶段启用 Android 专用工作流并记录实际结果。

模拟器可证明所测 Android API 上的行为，不能证明华为 ROM、电源管理、输入法、触摸手感、硬件密钥存储或 ARM 真机表现；后续发布说明必须保留“未完成华为真机验收”。普通 JVM SSH 测试也不能替代 Android ART 内的密码算法和提供者测试。

## 鸿蒙边界

用户补充目标机型是 Mate 70，去年购买，系统版本尚未确认。华为 Mate 70 官方规格明确列出 HarmonyOS 4.3，以及出厂搭载 HarmonyOS 5.0 的 NEXT 先锋版，且 4.3 可升级到 5.0。因此购买年份和机型不能确定当前系统；用户记忆中的“3”可能对应 4.3，但这只是待核实的解释，不能作为事实写进兼容承诺。应以手机“设置 → 关于手机”的完整 HarmonyOS 版本为准，再决定走 APK 直接安装测试还是兼容环境评估。[Mate 70 官方规格](https://consumer.huawei.com/cn/phones/mate70/specs/)

华为官方仍针对 HarmonyOS 2/3/4 系列手机提供外部应用安装说明，但也列出 CPU 不兼容、解析失败等安装问题。因此只能将具备兼容 Android 运行环境且实际 API 不低于 29 的旧鸿蒙设备列为候选，不能凭“鸿蒙”名称承诺全机型兼容。[华为外部应用安装说明](https://consumer.huawei.com/cn/support/content/zh-cn00766399/)

原生 HarmonyOS 应用以 HAP 作为安装运行单元，APK 不能通过修改 Android SDK 版本变成原生 HAP。特别注意，当前华为针对 HarmonyOS 5+ 的浏览器文档说明，下载 APK 后打开可拉起“卓易通”安装。因此也不能笼统宣称“鸿蒙 5+ 完全无法运行 APK”；应区分原生运行与兼容环境。本项目本期只交付 Android APK，不承诺 HarmonyOS NEXT/5+ 原生支持或卓易通内的可用性。若有具体机型和系统号，再安排独立兼容验收。[华为应用包术语](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/application-package-glossary)、[华为浏览器下载应用说明](https://consumer.huawei.com/cn/support/content/zh-cn16010239/)

项目建议不依赖 Google Play Services 完成 SSH、监控、SFTP、凭据存储与主题；这能减少非 GMS 设备的依赖障碍，仍不构成机型兼容保证。

## SSH 与终端组件选型

| 候选 | 已核验事实 | 决策与验证缺口 |
| --- | --- | --- |
| SSHJ | Apache 2.0；Java SSH 库，上游记录 Android 兼容修复、RSA-SHA2 和 SFTP 支持 | 优先候选。需锁定安全版本、传递依赖、Android 密码提供者，验证 API 29 的真实握手、密钥格式与取消连接 |
| mwiede/JSch | 维护中的 JSch 分支；BSD 风格许可证；支持 RSA-SHA2，默认关闭 RSA/SHA1；部分算法需较新 Java 或 Bouncy Castle | 备选。不能把桌面 JDK 可用算法推断成 Android 全部可用；须检查 Android 打包与提供者 |
| xterm.js | MIT 许可证；终端渲染组件，官方主要支持当前 evergreen 浏览器 | 推荐先评估本地 WebView 承载，外壳保持 Compose Material3；必须对 Android 10 旧 WebView、中文输入、软键盘、选择/复制、焦点、无网络资源加载做验证 |
| Termux 组件 | 仓库整体 GPLv3-only，但许可文件明确 `terminal-view`、`terminal-emulator` 使用的部分代码有 Apache 2.0 例外 | 不直接复制整个 Termux app 或假定所有终端模块都纯 Apache。若选原生组件，须逐文件、逐依赖确认确切快照许可；本轮不作可闭源分发保证 |

依据：[SSHJ README](https://github.com/hierynomus/sshj/blob/master/README.adoc)、[SSHJ LICENSE](https://github.com/hierynomus/sshj/blob/master/LICENSE)、[JSch README](https://github.com/mwiede/jsch)、[JSch LICENSE](https://github.com/mwiede/jsch/blob/master/LICENSE.txt)、[xterm.js LICENSE](https://github.com/xtermjs/xterm.js/blob/master/LICENSE)、[xterm.js 浏览器支持](https://github.com/xtermjs/xterm.js)、[Termux LICENSE](https://github.com/termux/termux-app/blob/master/LICENSE.md)。

Apache/BSD/MIT 路径适合作为保留闭源分发选项的工程候选，但仍须履行具体版本的版权、许可证及 NOTICE 保留条件，并审计传递依赖。若最终采用 GPL 组件，则应先明确分发与源码义务，不能仅因项目放在 GitHub 就忽略许可差异。

无论选哪一库，必须明确算法允许列表、保留主机指纹验证，不自动回退 RSA/SHA1，也不采用接受所有主机密钥的示例代码。优先复用先前 RSA-SHA2 失败案例作为验收条件，而非将 iOS 库补丁机械迁移到 JVM。

## 待实施验证项

1. 锁定 Gradle/AGP/Kotlin/Compose/SSH 库及传递依赖，记录许可证与哈希。
2. 用最小 Android 工程验证 API 29、31、36 编译、安装、主题和输入法。
3. 验证 SSH 库在 Android ART 上的 RSA-SHA2、Ed25519/ECDSA、加密私钥以及 SFTP；任何不满足现有 iOS 契约的点先反馈。
4. 选择并验证终端渲染路径，重点测试旧 WebView 或原生组件的中文 IME。
5. 启用 Actions 后以实际运行结果确定矩阵成本、稳定性与执行时间；不能提前声称 CI 已通过。
6. 明确签名和分发方案。测试 APK 与正式可持续升级签名分开记录；真实设备与鸿蒙兼容性保持待验证状态。


## Implementation-era verification

Android 16/API36 ignores app-requested orientation on displays with smallest width >=600dp. The application remains adaptive; tablet tests rotate the emulated device instead of forcing Activity orientation. [Android16 adaptive behavior](https://developer.android.com/about/versions/16/behavior-changes-16#large-screens)

Stock API29 cloud images use WebView74, whereas the local ARM API29 image uses WebView91. This distinction mattered: modern JS syntax and ParentNode.replaceChildren required compatibility handling. Local API36 tablet tests use WebView133. See validation.md for observed results rather than inferring compatibility solely from minSdk.
