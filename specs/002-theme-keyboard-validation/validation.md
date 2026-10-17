# Validation — 0.2.3 (5), same-version redeployment

日期：2026-10-17，Europe/Copenhagen。

- TH-01：通过。新增 TerminalThemeTests 对实际挂载的终端视图检查 dark → light → dark，以及重新挂载到浅色窗口。原产品逻辑无需修改。
- KB-01：通过。正常终端的 inputView 为 nil（使用系统文字键盘），焦点、隐藏和重新显示的既有测试通过。
- KB-02：通过。退出电脑 Device Hub 后，用户在手机端确认“能弹出”。不声称修复了不存在的焦点回归。
- 全量测试：build/theme-keyboard-final.log，28 项，27 通过、1 个 opt-in 外网探针跳过、0 失败。外网探针在 SSH 修复阶段已单独通过。
- Release 构建：build/redeploy-release.log，BUILD SUCCEEDED。
- DL-01：通过。LiveContainer 替换安装后 Info.plist 仍为 0.2.3 / build 5，installationDate 对应本地 22:32；LCDataUUID 与原数据容器相同。IPA 无测试夹具、XCTest bundle 或用户凭据。安装后退出 Device Hub。
- DL-02：文档与代码合并提交到 origin/codex/ios；远端引用核对结果及提交链接在交付回复中报告，不把提交自身哈希写入其内容。

仅提交本轮 SSH 修复、明确的回归测试和规范/验收记录；自动主题和键盘产品逻辑未作无证据改动。上游源码快照保留原格式；app-owned staged whitespace check 通过，Vendor 原有空白不做批量改写。
