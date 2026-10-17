# .term 导入导出验收

日期：2026-10-18（Europe/Copenhagen）。iOS、Android 均为 **0.2.3 (6)**。按用户要求，本次不部署实体 iPhone；真机安装由用户后续完成。

## 构建与测试证据

- Android 本机：API29 ARM64 手机、API36 ARM64 平板，各 **18 项仪器测试通过，无失败或跳过**；另有 **7 项 JVM 测试和 lint 通过**。覆盖受控真实 SSH/SFTP、终端输入、主机指纹、监控、生命周期及本次导入导出。日志：`build/term-android-final-full.log`。
- iOS 本机：原完整回归 33 项单元测试，无失败，7 项依赖独立 SSH/password/gateway 夹具的用例明确跳过；最终新增的 6 项连接包单元测试和系统文件往返 UI 测试全部通过。模拟器正常 adhoc 签名，以实际验证 Keychain。
- [最终 iOS CI 39078649556](https://github.com/liaoweiyang2017/ModernTerm-iOS/actions/runs/39078649556)：**通过**。Xcode16.4 / iOS18.5，34 项单元测试（上述 7 项明确跳过）加 1 项系统文件 UI 测试，零失败。UI 实际执行保存→打开→解密→预览。
- [最终 Android CI 39079382173](https://github.com/liaoweiyang2017/ModernTerm-iOS/actions/runs/39079382173)：**全部通过**。API29、API36 各 18 项仪器测试、7 项 JVM 测试及 lint 通过，随后自动签名 APK 构建通过。
- `shared/term-transfer/android-export.term` 由安卓模拟器实际生成，Swift 解码验证；`ios-export.term` 由 iOS 模拟器生成，Android 10/16 解码验证。完整记录与独立 Python 参考向量一致，覆盖 Unicode/NFC、缺省凭据和私钥换行。全部是虚构测试数据，仅作为测试资源，不进入生产安装包。

## 逐项验收

| ID | 结果与证据 |
|---|---|
| A01 | 两端多选、全选及配置导出流程通过；无选择时禁用导出。取消路径只清除待处理状态。iOS 使用真实系统“文件”，Android SAF 测试使用真实 FileProvider URI 读写。 |
| A02 | 两端实际产物交叉解码、完整字段相等；覆盖 Unicode、@ 用户名、IPv6、端口、分组、收藏、发行版元数据和私钥换行。 |
| A03 | 包含凭据/仅配置两种载荷均覆盖；Android UI 默认导出不含凭据。两端额外测试证明仅配置导出根本不调用凭据读取函数。 |
| A04 | 相同输入两次导出字节不同，文件中不存在样例主机明文，头部参与认证。文件密码使用安全输入框，不持久化或恢复到新进程。 |
| A05 | 错误密码、头部/salt/nonce/密文/tag 篡改、未知版本、截断、尾随数据、文件超限和短密码均拒绝。大批量导出达到 16 MiB 预算即停止继续读取秘密，防止先载入全部密钥。 |
| A06 | 完全相同条目合并，同 UUID 不同内容保留候选供明确选择；本机已有条目默认跳过，可作为新 UUID 副本导入。提交时重新检查 UUID 和 200 条容量限制。多文件 UI 和容量拒绝测试通过。 |
| A07 | 注入凭据写入后、配置提交前的故障验证回滚；启动日志恢复保留已提交凭据、清理未提交记录。额外覆盖 Android10 仅剩 AtomicFile 备份的中断状态，连接和凭据均恢复，随后保存不丢失。恢复日志损坏会阻止继续写入。 |
| A08 | 载荷不含指纹；导入路径不会调用连接。Android UI 验证没有打开会话。本机原已信任的相同端点仍遵循现有 SSH 策略，不从包中引入信任。 |
| A09 | Android 手机/平板和 iOS 系统文件流程通过；保留已有键盘、主题、旋转回归。实体 iPhone、华为/鸿蒙、OEM 文件选择器和第三方云盘仍未验证。 |
| A10 | 参考与平台产物向量已入库，两端 Actions 已配置；生产包元数据、签名/架构、安装启动和上传哈希见下文。云端结果单独记录，不以本机通过替代失败结果。 |

## 修复与边界

- Android 列表可能复用上一步内容，导致预览旁残留解密标题。现在按明确流程阶段重新建立列表，回归测试确认旧标题消失；切换步骤回到顶部。
- iOS 展示系统文件窗口时，底层视图也可能收到消失事件。导出文档现在保留至窗口回调完成，避免旧系统提前清理文档。
- 系统“文件”的自动化兼容大写分节标题、iOS18 的 **Move** 与 iOS26 的 **Save**，以及首次打开时为空的“最近使用”页；这些属于系统 UI 导航差异。
- 云端安卓模拟器较慢，文件解锁测试采用有界的 30 秒等待，而不是 5 秒；输出数字形式的 KDF 耗时和失败时的界面标签。未降低加密强度。本机 API29 派生+解码约 818 ms（同时构建时测得）；最终云端实测 API29 为 5259 ms、API36 为 9123 ms，解释了原 5 秒测试期限不足。
- Android10 的 AtomicFile 中断时可能只有 `.bak`。配置、凭据、恢复日志都通过 AtomicFile 恢复备份，清理也包括旁路文件。测试先红（读到空列表）后绿。见 [AOSP 实现](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-10.0.0_r1/core/java/android/util/AtomicFile.java) 和 `term-backup-red.log`、`term-backup-green.log`。
- 构建缓存放在同步 Documents 目录之外，避免生成文件重复和 Finder 扩展属性影响 dex/codesign。
- Android SAF 自动化提供系统选择结果、执行真实 URI IO，不代表所有 OEM 选择器都已验证；iOS 自动化实际操作系统“文件”。
- 限额为 20 个文件、合计 16 MiB、200 个条目。取消或校验失败不写入；进程重建丢弃尚未提交的预览。恢复机制针对中断写入，不宣称硬件断电下的绝对持久性或分布式事务。
- 导出/分享只生成密文。解密及预览期间秘密需要存在于进程内存，不能声称托管运行时内存能完美清零。文件密码遗忘无法恢复。

## 安装包与来源

- Android：`ModernTerm-Android-0.2.3-build6.apk`，minSdk29 / targetSdk36，包名 `com.modernterm.android`。固定签名 SHA-256：`5dcca3a86795783f10d3b44eaaa2f06ddc5ed6e4bfbbd6337df7edbf4e2e1c19`。签名和 16 KiB zip 对齐校验通过，最终包已在 API29/36 安装并冷启动。
- iOS：`ModernTerm-iOS-0.2.3-build6-LiveContainer.ipa`，iOS17+、Release arm64、未签名，供现有 LiveContainer 流程使用，由 LiveContainer 完成签名；更新时保留原数据容器。不是可直接安装的 App Store/开发者签名 IPA。版本、构建号、架构及不含 XCTest/测试包已检查。
- Android 产物来自 `ae0a27e085283d156491c35c803e9b84c189ad6c`，iOS 来自 `60e1f5f14397cbea3babb5d70253dd55b7faf493`。之后仅更新文档。安装包不含真实账户、签名私钥或测试 APK。
- 两个安装包、SHA256SUMS、build-info 和 INSTALL 均已上传，GitHub 资产摘要与本地 SHA-256 一致。[下载 Release v0.2.3-build6](https://github.com/liaoweiyang2017/ModernTerm-iOS/releases/tag/v0.2.3-build6)。
- Actions 产物上传可能受账户存储配额限制而警告；构建/测试失败不会被忽略。本次通过仓库 Release 附件交付，不删除其他项目的产物。

## 界面与复现资料

已检查 [Android 手机](screenshots/android-phone-import.png)、[Android 平板](screenshots/android-tablet-import.png)、[iOS 预览](screenshots/ios-import.png)，均为虚构连接。iOS 图片早于新增统计行，该行已由最终 UI 测试覆盖。

本机日志保留于忽略目录 `build/`：`term-android-final-full.log`、`term-ios-regression.log`、`term-ios-budget-tests.log`、`term-ios-picker-lifecycle.log`。云端以上述实际运行链接为准。测试结束后关闭本机临时 SSH 服务及本次创建的模拟器。
