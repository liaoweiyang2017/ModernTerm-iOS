# 0.2.4 本地发布验收

版本：iOS/Android 0.2.4，build/versionCode 7。日期：2026-10-18。

## 开源与维护

- 自有代码采用用户确认的MIT许可，完整LICENSE入库，第三方许可保留。
- README重写为项目首页，覆盖实际优势、平台表、合成数据截图、安装、首次连接、加密分享和接收、源码构建、本地测试、限制与贡献。
- GitHub Actions仓库权限已关闭，移除两个工作流；后续构建和测试均在本地运行。
- Gitleaks扫描全部Git历史，发现20条候选：18条为上游SSH源码的测试密钥/格式标记/变量误报，涉及7个文件，已与Vendor声明的上游固定提交逐字节核对一致；2条为xterm压缩代码FourKeyMap变量误报。未发现个人连接JSON、迁移文件、签名密钥或安装包进入Git历史。此检查不代表通用安全审计。

## 局部改进

- iOS外部附件与文件选择器读取移至后台，保留读取期间security-scoped权限、大小/格式约束和取消token，显示处理进度；批量读取复用同一小型函数。
- Android附件读取任务使用ViewModel生命周期和applicationContext，旋转后仍可接收；读取时显示进度。文件名元数据查询异常使用默认名称，不阻断可读附件。
- 不改变.term格式、600000次KDF、密码/密钥存储策略和现有平台设计。

## 测试结果

- iOS本地全套：36项单元测试（7项独立SSH环境测试按既有规则跳过）、4项UI测试通过；新增批量读取边界单测单独通过。日志024-ios-test.log、024-ios-batch.log。
- Android最终代码：API29和API36各24项设备测试通过（含隔离SSH/SFTP、RSA-SHA2、英文/中文IME、VT、终端视口、旋转、加密附件接收与分享）；7项JVM及lint通过。日志024-android-terminal-final.log、024-api29-final.log。设备顺序执行以避免本机多模拟器负载干扰。
- iOS Release arm64构建通过，IPA内部版本核对0.2.4(7)，未包含测试bundle或生成的SSH测试凭据。
- Android保持既有签名，Release生成后校验versionName/versionCode、minSdk和签名指纹，并核对附件SHA-256。
- README本地文件/图片引用检查通过；共享资源同步检查通过；git diff --check通过。

初次并行运行API36出现文件选择回调/短密码测试超时。加诊断日志后完整运行通过；移除日志并调整短密码测试为实际点击后，最终完整测试通过。没有将其声称为某种OEM逻辑故障，也没有通过跳过相关测试掩盖失败。

## 安卓终端修复证据

- 新增隔离SSH尺寸查询：修复前resize(43,17)早于openShell(80,24)时，远端返回SIZE=80,24，测试失败（024-terminal-red.log）。
- 缓存最新尺寸并将resize与openShell串行后，远端返回43,17；创建中及创建后仍可调整窗口，未改动SSH认证或安全策略。
- Keyboard按钮移到可滚动辅助栏之外；UI测试滚动辅助栏后确认按钮仍可见，IME/视口测试通过。
- WebView显式固定100%文本缩放；聚焦DOM输入框完成后再请求原生键盘，轻点终端可请求输入。主题参数未变时不重复设置渲染器，resize按帧合并，监听视口尺寸变化。
- 当前只有ColorOS17截图和用户概述，缺少具体机型/输入法复现；没有ColorOS实体机测试。不把模拟器通过等同于所有OEM键盘都已验证。用户应以0.2.4重新实测。

## 发布约定

安装包由本机构建，源码与构建信息随v0.2.4发布；GitHub Actions关闭。新资产上传并逐一校验后删除4个旧0.2.3 Release及附件，保留Git标签。仓库在公开检查后切换为Public，MIT许可覆盖自有代码，第三方许可不变。

## 发布完成核验

- 生产源码提交：`5be98bc`；v0.2.4 Release已发布，IPA/APK/build-info/SHA256SUMS共4项资产状态均为uploaded，GitHub返回的SHA256逐一与本地一致。
- Android实际包：versionName0.2.4、versionCode7、minSdk29、targetSdk36；签名SHA256仍为`5dcca3a86795783f10d3b44eaaa2f06ddc5ed6e4bfbbd6337df7edbf4e2e1c19`，未包含ssh-fixture或参考测试附件。
- 最新提交Gitleaks检查无命中；仓库API确认PUBLIC、许可证识别为MIT。
- 4个旧Release（build6、icons、sharing、open-attachments）及附件已删除；列表仅剩v0.2.4。旧标签未删除。
- Actions权限API确认enabled=false，无新增工作流运行。隔离SSH服务及安卓测试模拟器已停止。
- 本次生成发布包，没有将0.2.4安装到用户实体手机；ColorOS17实测仍待用户进行。
