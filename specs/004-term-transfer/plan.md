# Implementation plan: .term v1

状态：用户已确认；实施结果见 validation.md。

## 格式草案

所有整数为无符号大端。固定头部共 48 字节：magic 8 字节 `MTERM\0\r\n`，格式版本 uint16=1，KDF 标识 uint8=1，AEAD 标识 uint8=1，PBKDF2 迭代次数 uint32=600000，随机 salt 16 字节，随机 nonce 12 字节，密文长度 uint32（不含 tag）。其后是密文和 16 字节 GCM tag。整个头部作为 AAD。

采用 PBKDF2-HMAC-SHA256 派生 32 字节密钥，AES-256-GCM 加密；v1 仅接受固定的 KDF/AEAD/迭代参数，拒绝攻击者控制的大迭代数。随机源来自各平台系统安全随机数。先检查长度与参数，再执行昂贵 KDF。工作在后台队列，进度可取消；API29 ARM64 实测一次派生加解码约 0.8 秒，锁定 600000 次。若需要改变格式参数，先更新方案和测试向量。

载荷为 schemaVersion=1、entries 数组；每项含 server 和可选 credentials。显式字段映射复用已有 Server/Credentials，不直接序列化平台内部状态。UUID 统一大小写无关解析。只允许已支持的载荷版本，忽略安全的可选未知字段不能替代必填字段验证。

## 模块和平台衔接

1. shared/term-transfer：格式说明、仅含虚构数据的固定 salt/nonce 测试向量。生产接口不得允许固定随机值；测试使用内部可注入随机源。
2. Swift 编解码器：系统 PBKDF2 接口 + 现有 Crypto AES.GCM；Kotlin：JCA PBKDF2/AES-GCM。先验证 Unicode 密码在两端派生结果一致，必要时显式 UTF-8 实现避免 provider 字符编码差异。
3. 独立 import planner：解密与验证、去重/冲突、容量计算与预览。提交前再次核对当前存储状态，避免预览期间修改产生覆盖。
4. 存储提交：仅新增 UUID，先写带新增 ID 的恢复日志，再写凭据和原子配置；完成后清理日志。下次启动以配置文件提交结果判断清除孤立凭据或完成清理。日志不能包含秘密；损坏日志/回滚失败应明确提示并阻止继续写入，而非静默成功。实现前核对两端现有存储与文件提交顺序。
5. iOS 列表选择/导入预览、FileDocument/分享、UTType；Android Material3 选择栏、密码对话框、OpenMultipleDocuments/CreateDocument。文件名只用通用名称/日期，不泄露主机信息。
6. 配置缺少凭据时保留 keyLogin，连接前提示补充；已保存的空凭据和未包含凭据应在包结构中区分。

## 验证与交付

先做格式/密码编码互通和存储故障测试，再接 UI。运行现有 SSH、终端、监控及迁移回归；追加 API29/36 仪器测试与 Swift 单元测试。继续维护 specs/003 的基础 Android CI 结果，新增功能在 specs/004 单独验收，不能用旧构建结果代替新功能验证。最终 Android APK 包含此功能后交付；iOS 构建产物与限制单独记录。代码、规范、验收文档提交推送当前仓库；凭据、签名私钥、真实连接包不入库。

## 实施补充

- iOS 模拟器必须正常 adhoc 签名才能验证 Keychain；禁用签名会导致凭据读写失败，不能据此跳过测试。构建缓存放在 Documents 之外，避免同步目录生成 Finder 扩展属性影响 codesign。
- 构建号两端统一提升为 6，显示版本仍为 0.2.3。iOS 真机安装由用户下一天执行，交付 LiveContainer 使用的 arm64 IPA，不冒充 App Store/开发者签名分发。
- 解密/加密可通过取消关闭界面，固定成本 KDF 在后台结束后丢弃结果；已明确提交的存储写入不在中途取消，以保护事务恢复语义。
