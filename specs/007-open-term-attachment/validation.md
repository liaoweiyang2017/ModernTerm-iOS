# 附件接收验收

2026-10-18；版本保持 iOS / Android 0.2.3 (6)。

| 项目 | 结果 |
| --- | --- |
| Android 文件关联 | 新测试在修复前失败于“ModernTerm must appear in Open with”（build/open-term-red.log）；补充 Manifest VIEW/SEND/SEND_MULTIPLE 后通过。只注册通用二进制和 ModernTerm MIME，拒绝网络 URL。 |
| Android 热启动 | 已运行 MainActivity 收到 ACTION_VIEW content URI 后进入密码页，参考文件解密到预览，未自动保存。 |
| Android 冷启动与多附件 | ACTION_SEND 冷启动进入密码页，取消不改变存储；SEND_MULTIPLE 解析两份附件并成功解密。既有批量导入 UI 测试覆盖逐文件密码、去重预览、确认导入、导出与分享。 |
| iOS 冷/热打开 | XCTest 使用 XCUIApplication.open(fileURL) 冷启动，再通过 XCUIDevice.system.open(fileURL) 使用系统默认文档关联热启动。均自动出现文件密码页；错误密码可纠正后进入预览，取消不写入。首次测试锁定 sheet 捕获旧状态的问题，改为 item sheet 携带文件后通过。 |
| iOS 读取边界 | 单测验证本地参考附件解密、拒绝网络 URL/明文/超过16MiB文件。security-scoped 授权在读取期间持有并释放。 |
| Android 读取边界 | 仪器测试覆盖有效参考附件、明文、超过16MiB、超过20份、无效 provider、网络 URL；仅读取被传入的 content URI，不申请存储权限。 |
| 自动化 | Android API29/API36 各5项相关仪器测试通过，7项JVM和lint通过；iOS附件单测与冷/热打开UI测试通过。两端Release构建通过。 |

## 限制与部署状态

初次构建期间设备不可连接；用户随后连接解锁，现已完成下述实机补验。没有Android实体机或微信端到端收件测试。

iOS 原生安装可以通过系统文档关联打开 ModernTerm。当前用户的 LiveContainer 安装方式需要在分享面板选择 **LiveContainer → ModernTerm**；系统不直接注册客体应用。此路径来自[LiveContainer 官方 Open In App 说明](https://github.com/LiveContainer/LiveContainer#open-in-app-support)，本轮已按下述流程实测。此差异不会靠修改客体 Info.plist 消除。

导入只复用已有解密、预览、冲突处理和确认保存逻辑；不自动连接、不自动覆盖已有 UUID。已有传输页面时拒绝新请求并提示完成/取消后重试。进程被终止不保留待解密状态，重新打开附件即可。

## 测试诊断记录

- 本地日志（忽略目录）：open-term-red.log、open-term-green.log、open-term-ios.log、open-term-ios-green.log、open-term-ios-final.log、open-term-android-final.log、open-term-android-final2.log、open-term-android-final3.log、open-term-ios-release.log、open-term-android-release.log。
- iOS 自动键盘无法完整输入 Unicode 测试密码，新增仅用于 UI 的 ASCII 密码附件 attachment.term（无真实凭据），不改变原 Unicode 密码互通测试。
- 上一提交4909489的Android CI 39117229947有UI点击/等待超时：API29未打开传输页，API36在第二文件解锁阶段超时。同步测试改用可访问性动作并等待可用状态，加密等待上限调整为60秒；本地复测通过。GitHub新一轮结果需另查，不把本地通过表述为CI通过。

参考接口：[Android 接收数据](https://developer.android.com/develop/ui/compose/sharing/receive)、[Apple onOpenURL](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:))。

第二次本地同步测试在短密码按钮上暴露尚未启用时触发语义动作的竞争；测试助手改为先等待 enabled 再执行，不在应用代码加入延迟。

## 实机补验（2026-10-18）

- 通过 LiveContainer 替换现有 ModernTerm 安装，核对0.2.3(6)与新文档配置；保持既有数据容器。
- 系统 Files 打开合成 `attachment-test.term`，选择分享 → 更多 → LiveContainer → ModernTerm，自动进入文件密码页。
- 输入合成测试密码后，显示2条连接的导入预览（1条含合成凭据、1条仅配置）和“Import 2 connections”按钮；未连接服务器。
- 取消测试导入，原12条连接文件与安装前逐字节相同；未向联系人发送、不将合成连接写入真实列表。设备预览已退出，避免占用软键盘。测试附件留在LiveContainer/Documents，名称attachment-test.term，仅含合成数据。
- 此次证明系统附件交接与解密预览可用；没有实际从微信会话接收文件，不把它表述为微信端到端收件验证。

## CI补充

提交dbc602d的CI仍失败：iOS18测试运行器的定向app.open冷启动未交付文件事件，Android29长列表中未组合到屏幕的节点无法performScrollTo。测试改用系统默认文档打开（冷/热均走真实系统关联）和LazyColumn的ScrollToNode定位。本机iOS26.5系统冷/热UI测试、Android29三项传输UI测试复测通过（open-term-system-cold.log、open-term-lazylist.log）。后续CI结果待确认，未将失败或排队状态记为通过。应用二进制未因这些测试改动而变化。
