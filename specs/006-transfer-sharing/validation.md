# 验收记录

日期：2026-10-18。iOS / Android 版本均保留 0.2.3 (6)，保留统一新版图标。

| 验收项 | 证据与结果 |
| --- | --- |
| 导出失败有明显反馈且保留输入 | iOS 先运行短密码 UI 回归失败（export-feedback-red.log），修复后通过（export-feedback-green.log）；Android 同场景通过。长度、重复输入、选择数量和加密进度靠近操作按钮。 |
| 保存功能保留 | iOS 原生保存再打开 UI 测试通过；Android 原生文件接口替身验证保存内容与分享内容解密一致。 |
| iOS 原生分享 | iPhone 和 iPad 模拟器分享 UI 测试通过；实际 iPhone 经 LiveContainer 替换安装后，单连接、凭据关闭、有效文件密码打开系统分享面板，附件为 ModernTerm-connections.term，“更多”列表有 WeChat。未选择微信联系人或验证微信最终收件。 |
| Android 原生分享 | API 29 与 API 36 分别通过 10 项针对性仪器测试（分享、传输 UI、格式和存储）；确认 ACTION_SEND / chooser、content URI、只读授权、无密码文本。没有 Android 实体机，微信实际接收待设备验证。 |
| 格式互通与清理 | iOS 6 项格式测试及分享文件单测通过；Android 使用既有跨平台格式测试和解密器读取分享附件。二进制格式、KDF、AEAD 参数未变。清理仅限功能私有 UUID 缓存目录；Android 保留24小时供异步读取，随后按需清理。 |
| 构建与数据保留 | iOS Release 和 Android 签名 Release 构建通过；Android 7 项 JVM 测试和 lint 通过。iPhone 替换前后 servers.json 字节一致，12条配置保留，数据容器 UUID 未变。 |

## 实机观察与限制

旧版在有效密码条件下可以打开保存窗口，不能认定用户所有“没反应”情况都来自同一原因。已明确复现并修复的是短密码错误原先位于长表单底部且输入被清空的问题。

实机分享检查期间，系统面板显示向用户本机 Mac 完成 AirDrop，Downloads 中出现291字节加密测试附件。该测试仅含一条配置、不含凭据，附件已移入本机废纸篓。未向微信联系人发送文件；不将“分享面板关闭”当作对方收件成功。电脑端手机预览在测试后退出，避免干扰软键盘。

本地日志位于忽略的 build/：share-ios-tests.log（格式、文件单测和保存通过，分享测试初版选择器失败）、share-ios-sheet.log（修正 AX 选择器后通过）、share-ipad-test.log、share-android-final.log、share-ios-release.log、share-android-release.log。Android 文件选择测试修正为语义点击，以消除 Dialog 动画期间的点击竞争；最终 API 29/36 均通过。实机连接资料及截图不入库。
