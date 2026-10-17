# 0.2.3 (5) 验收记录

日期：2026-10-17，Europe/Copenhagen。结果：本次缺陷修复及已定义验收范围通过。

## 原因和修复

原始探针在用户图1服务器上复现截图的 NIOSSH error 1，底层为 keyExchangeNegotiationFailure。目标仅提供 RSA 主机签名，原客户端默认仅提供 Ed25519/ECDSA。按用户确认新增 RSA-SHA2，保留主机指纹验证且不启用 SHA-1 回退。用户名 @ 不是这个已复现握手失败的原因。

真机核对发现两张截图对应不同已保存条目：图1为 ParaCloudDomesticIPV4；图2标题为 ParaCloudCPU_ali，使用另一域名和端口。因此保留各自配置，分别验收；没有把两者当作相同 endpoint，也没有覆盖配置。

## 验收矩阵

| 条款 | 结果 | 证据与范围 |
|---|---|---|
| AC-01 真实目标登录 | 通过 | iPhone 17 / iOS 27.2 / LiveContainer 3.8.10，安装 0.2.3 (5)。图2 ParaCloudCPU_ali 手动连接、断开、重连共 3 次均成功；首次终端通过 printf 输出 MT_OK，其余连接获得新 shell 提示符。图1 ParaCloudDomesticIPV4 显示 Connected 和持续刷新监控数据。|
| AC-02 用户名原样 | 通过 | Codable 往返测试 + 受控 SSH 服务仅接受包含 @ 的精确用户名 + 两个真实条目保留原用户名并认证成功。未改写用户配置。|
| AC-03 密码成功/失败 | 通过 | 隔离 Paramiko RSA-SHA2 服务对正确测试密码成功，错误测试密码拒绝；真实目标使用设备现存凭据成功。|
| AC-04 安全错误诊断 | 通过 | ConnectionFailureTests 覆盖协商、认证、指纹、地址/超时和未知错误；未知错误不展示原始敏感诊断。真实协商失败已红测，修复后握手通过。DNS/TCP 分类为单元注入，未故意破坏真实网络。|
| AC-05 既有支持 | 通过 | localhost/127.0.0.1/::1、非默认端口均由 SSHSession 实际连接；Ed25519 现有 OpenSSH 集成通过，RSA 用户私钥经新增受控服务认证通过。IPv6 是本机回环，未宣称完成外网 IPv6 验证。|
| AC-06 信任与生命周期 | 通过 | 已知指纹改变拒绝；IPv6 首次指纹拒绝不保存，取消连接后重连，旧回调不关闭新连接；真机重连 3 次。真实目标新指纹与桌面 known_hosts 相符后才接受。|
| AC-07 能力隔离 | 通过 | 受控服务拒绝 exec 和 SFTP；终端依然回显。只发 CHANNEL_FAILURE、不关闭通道的 SFTP 测试修复前 3 次超时，修复后全部及时返回，SSH/PTY 保持可用。|
| AC-08 数据及全量回归 | 通过 | 最新完整套件 27 项：26 项通过，1 项显式外网探针跳过；外网探针已单独通过。迁移、Keychain、监控、键盘、SSH/SFTP 原有测试通过。真机更新前后 LCDataUUID 相同，列表保留，凭据直接可用。|

## 执行记录

构建环境 Xcode 27.1；模拟器 iPhone 18 Pro / iOS 27.0。

- `MODERNTERM_DERIVED_DATA=<既有 DerivedData> build/ssh-fixture-env/bin/python Scripts/password_integration.py`：最新 `build/full-acceptance-final.log`，27 项，1 跳过，0 失败，TEST SUCCEEDED。
- `MODERNTERM_DERIVED_DATA=<既有 DerivedData> python3 Scripts/gateway_probe.py <图1主机>`：`build/gateway-final.log`，1 项通过；在主机验证处主动停止，不发送凭据。
- `xcodebuild ... -only-testing:ModerntermTests/ConnectionFailureTests ... test`：`build/error-mapping-final.log`，4 项通过；其后全量测试也再次覆盖。
- `xcodebuild -project ModerntermIOS.xcodeproj -scheme ModerntermIOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath <既有 DerivedData> CODE_SIGNING_ALLOWED=NO build`：`build/release-device.log`，BUILD SUCCEEDED。
- `git diff --check`：通过。
- 真机安装由 LiveContainer 完成签名和容器处理；安装后读取实际 Info.plist 确认 0.2.3 (5)，比较 LCAppInfo 确认原数据容器保持不变。

发布产物 `build/ModernTerm-0.2.3-LiveContainer.ipa` 不含 XCTest bundle、测试夹具或用户凭据。测试用一次性密钥与密码夹具已删除；产品源码没有临时诊断输出。未变更服务器设置、用户密码、存储结构或 App Store 分发配置。

## 限制

验证针对当前两条实际连接及受控服务，不等于所有 SSH 网关兼容。未覆盖公网 IPv6、所有认证扩展（keyboard-interactive/MFA）、长时间后台保活或所有 RSA 加密私钥变体。现有 RSA 用户私钥认证语义保留；新增 RSA-SHA2 策略针对服务器主机签名，不宣称同时升级了 RSA 用户认证签名算法。两个固定依赖带局部补丁，后续升级需保留或上游合并这些补丁，详见 Vendor/README.md。
