# 证据与诊断状态

日期：2026-10-17。根因已复现：默认客户端仅提供 Ed25519/ECDSA 主机签名，目标只提供 RSA 系列主机签名，无交集，导致 keyExchangeNegotiationFailure。

## 初始规范阶段检查

- 通过已登录 `gh` 克隆用户指定仓库，HEAD 为 `8f80288bd3ae885c363e47dc5082a445731c731e`。初始工作区干净，无仓库 AGENTS.md、CONTEXT.md 或既有 .specify。
- `Sources/SSHSession.swift` 的 `connect` 分别把 `server.user` 传入 passwordBased，把 `server.host` / `server.port` 传入 SSHClient.connect；这段代码没有拆分用户名里的 `@`。
- 同一方法的 catch 只使用 `error.localizedDescription`。这说明当前错误呈现信息有限，不证明底层根因。
- `Scripts/integration.py` 显式设置 `PasswordAuthentication no`、`KbdInteractiveAuthentication no`；已有本机 SSH 集成夹具使用 Ed25519，未覆盖用户报告的密码登录场景。
- 锁定依赖为 Citadel 0.12.1、Wellz26/swift-nio-ssh 0.3.7（并非直接使用 apple 仓库版本）。任何错误类型分析必须对照这一确切版本。
- `xcodebuild -version` 返回 Xcode 27.1 / 27A9275。模拟器 Info.plist 检查得到 0.2.2 (4) 和 0.2.0 (2)，当前均未启动。本轮没有读取用户凭据或尝试目标服务器认证。

## 初始复现缺口（后续已补齐，见实施阶段证据）

截图没有底层错误详情；现有测试夹具不覆盖密码认证，也没有重放网关行为。不能将静态代码阅读或旧测试结果称为本问题的复现。下一阶段先在隔离环境构造与实际 SSHSession 相连的密码认证夹具，并捕获失败阶段；只有获得同症状可重复信号后才排序、验证根因假设。

真实账号凭据由设备现有安全存储或用户在界面输入，禁止写进规范、命令行、日志或 Git。若隔离夹具无法重现，使用实际设备的脱敏错误记录缩小夹具；不能用无关失败替代目标缺陷。

## 流程来源

- https://github.com/github/spec-kit
- https://github.com/github/spec-kit/blob/main/templates/spec-template.md
- https://github.com/github/spec-kit/blob/main/templates/plan-template.md
- https://github.com/github/spec-kit/blob/main/templates/tasks-template.md

已读取官方模板并按本项目缩减。当前为人工落实 Spec Kit 文档流程，没有安装 CLI 或声称执行了不存在的 slash command。

## 实施阶段证据

1. 原始 XCTest 使用与产品相同的 SSHClient.connect 默认设置，远端为用户目标；自定义认证代理永不提供凭据，主机验证代理只返回探针终止错误。测试 0.704 秒失败，实际 NIOSSHError.keyExchangeNegotiationFailure；localizedDescription 与截图逐字一致。
2. 服务器公开 KEXINIT 声明 host key 为 rsa-sha2-256,rsa-sha2-512,ssh-rsa；客户端默认 bundledAlgorithms 只有 ssh-ed25519 和三种 ecdsa。KEX 和加密列表存在交集。
3. 临时探针仅注册库内旧式 RSA 后，0.640 秒到达主机验证；确认主机签名交集是阻断点。该旧式配置从未加入产品。
4. 用户明确确认采用 RSA-SHA2。当前扩展点混淆公钥编码与协商算法，且同一个 key type 只注册第一个 signature type；本地固定源码修正两个边界，保持库版本及其他依赖固定。
5. RSA-SHA2 修复后的真实服务器探针通过（最终单独执行 0.623 秒）。它刻意拒绝主机验证，不提供凭据，不代表完整登录通过。
6. 密码测试服务使用测试用户名 test-account@ZONE-M6、随机一次性密码和临时 2048-bit RSA key，只提供 RSA-SHA2。实际 SSHSession 连续登录、PTY 回显、拒绝密码均通过。
7. SFTP 拒绝但不关闭子通道的回归测试在修复前连续三次超过 3 秒，修复后全部通过。修正只影响该子通道。
8. 手机 LiveContainer 中实际 Info.plist 确认为 0.2.2 (4)。桌面 known_hosts 已有目标 RSA 3072 位指纹，可用于真机核对；未读取密码。

日志位于本地忽略目录 build/：gateway-probe.log（原始红测）、gateway-rsa-probe.log（单变量诊断）、gateway-final.log（RSA-SHA2 真服务器握手）、sftp-rejection-red.log、full-final.log、error-mapping-final.log。失败测试结束后 Xcode 有时在结果收集阶段停留，已在结果落盘后终止对应测试进程；不将其算作成功退出。
