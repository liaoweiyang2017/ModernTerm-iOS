# Implementation Plan: SSH 网关登录

状态：已确认并实施的方案；关联 [spec.md](spec.md)、[research.md](research.md)。

## Technical Context

Swift（工程语言模式 5）、SwiftUI/UIKit、iOS 17+；Citadel 0.12.1、NIOSSH fork 0.3.7；XCTest、临时 SSH 服务；配置沿用 Codable，秘密沿用 Keychain。改动限制于本 iOS 仓库，沿用现有连接、指纹和会话生命周期。

## Constitution Check / 本次约束

仓库暂无 constitution；本轮以用户明确要求作为门槛：先规范后实现、确认前不大规模编码、需求可追溯、必要测试、偏差先说明。额外沿用现有项目的凭据隔离和主机指纹校验。没有为了形式增设架构或更换 SSH 库。

## 技术路径

1. 以模拟器 0.2.2 (4) 为基线，核对设备构建。先捕获同一失败的阶段和脱敏 NIOSSH 细节；确切类型对照锁定依赖源码。
2. 扩展隔离 SSH 测试服务，使其接受测试用户名中包含 `@`、提供密码成功/拒绝场景，并让测试调用实际 SSHSession。保留原 OpenSSH 密钥测试；不修改 macOS 用户密码或系统 SSH 服务。
3. 在 `SSHSession.swift` 的连接边界保留阶段和类型信息，在独立且小的错误映射组件呈现安全说明。未知错误不推测原因；日志不能包含凭据及认证数据包。
4. 得到稳定失败后列出可证伪假设，逐项单变量验证。只修复被证据定位的输入、认证或协议边界；没有证据时不升级依赖、不重写连接层。
5. 若需要 keyboard-interactive/算法扩展，先提交方案差异与新增验收条款。否则继续最小修复，并检查 Monitor/Terminal/SFTP 错误隔离。
6. 运行针对性回归、完整已有测试、模拟器与设备构建，然后在实际目标上验收。未获得真实目标证据时报告未验证，不能宣称解决。

## Data / Contracts

Server、Credentials 存储模型预计不变。内部连接诊断至少包含阶段、错误类别、用户说明及脱敏详情；具体类型在复现后确定。认证边界输入契约为 host / port / username 独立参数，username 原样；失败输出契约为阶段已知则准确、未知则明确未知。主机验证必须在认证获准前完成。

## 验证与范围调整

AC-01 真实目标；AC-02/05 输入与保存；AC-03 密码服务；AC-04 错误映射；AC-06 生命周期与指纹；AC-07 通道隔离；AC-08 全量回归。每项保存命令、结果与未覆盖项。取消、超时不得导致无限后台重试或不断重发密码。

初始计划未预设根因；现已根据复现证据和用户确认收敛为下列方案，并同步 research、spec、tasks 与 validation。

## 实际方案收敛

- Vendor/swift-nio-ssh 保留锁定 0.3.7 源码和许可证；3 个源码文件区分 host signature algorithm / wire key format、强制签名匹配、修正一 key 多 signature 注册。
- Sources/RSAHostKey.swift 使用已存在的 Swift Crypto _CryptoExtras 做 SHA-256/512 RSA 验签，未自己实现 RSA 运算。Sources/SSHSession.swift 仅接入配置及安全错误映射。
- Vendor/Citadel 保留锁定 0.12.1；SFTPClientInboundHandler 对 CHANNEL_FAILURE 失败初始化并关闭子通道。
- 锁定源码用于可复现构建，不依赖修改本机包缓存或未发布分支。来源和全部差异见 Vendor/README.md。
- 新版本 0.2.3 (5)；配置、凭据、指纹数据模型不变。
