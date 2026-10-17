# Implementation Plan: Kotlin / Material3

状态：已确认，实施中。关联 spec.md 与 research.md。初始仓库基线 698cba9；本机未发现可用JDK或Android SDK，仓库Actions当前disabled。

## 技术选择

- android/ 独立Gradle工程，Kotlin + Jetpack Compose + Material3 + Coroutines/Flow。界面状态由ViewModel管理，SSH阻塞IO在专用调度器，不阻塞主线程。
- minSdk29，compileSdk/targetSdk36；JDK/AGP/Gradle/Kotlin/Compose BOM实施时按官方兼容矩阵锁定精确版本，禁止动态latest依赖。首个可执行任务先验证API29可运行，而不是只编译。
- SessionRepository管理最多8个会话；配置与凭据存储分离；SSH/SFTP/监控接口服务于具体测试场景，避免抽象层泛滥。
- SSH首选候选 SSHJ，备选 mwiede/jsch（维护中的JSch分支）；必须验证Android29上的RSA-SHA2、Ed25519、加密OpenSSH私钥和加密provider。许可证、依赖树和配置写入第三方清单。若首选不通过，比较JSch后再锁定，不削弱主机验证。
- 终端初选本地打包 xterm.js（MIT），仅终端画布使用受限WebView；连接列表、监控、SFTP、设置全部原生Compose。JS不联网、不加载CDN、不读取凭据；Kotlin负责SSH与文件，桥接只暴露终端字节和尺寸。远端输出按字节传递，不能插入HTML/执行JS。
- 终端接入必须先验证Android10 WebView、中文IME、软键盘、选择复制和resize；如果效果达不到原生使用要求，再评估许可清晰的Android终端模块。不得直接把整个Termux app作为依赖移入。
- Material3：手机底部导航/服务器列表和详情内Monitor-Terminal-SFTP切换；大屏导航栏及双栏；FAB新增连接、ModalBottomSheet编辑、Snackbar反馈；Android12+动态色，其余版本固定品牌色。终端色板独立于界面动态色。
- 本地配置使用DataStore/小型结构化存储，凭据Android Keystore + AES-GCM。密钥失效需明确重新输入，不把空凭据当成正常成功迁移。排除秘密备份。
- 文件使用SAF；迁移v1通过选中文件导入，不照搬LiveContainer容器路径。监控shell协议和18套配色从仓库共享源生成/校验，避免两平台漂移。

## 目录建议

android/app/src/main/：ui、session、ssh、sftp、monitoring、storage、terminal。
android/app/src/test/：配置、错误映射、监控解析、生命周期纯逻辑。
android/app/src/androidTest/：Compose、IME、SAF、Keystore、SSH集成。
shared/：无秘密的主题与监控黄金夹具；保留iOS消费兼容，不移动现有Sources。
.github/workflows/android-ci.yml：只触发Android或共享源相关变更及手动执行。
specs/003-android-material/：本规范、调研、计划、任务、验收。

## 无设备测试方案

1. 启用当前仓库Actions，设置contents:read和最少权限；action固定commit SHA。push/PR运行lint、JVM测试和assembleDebug；不用pull_request_target执行外来代码。
2. Linux runner开启受支持的KVM，Android emulator矩阵API29和36，仪器测试安装APK并启动受控SSH服务。主机Docker服务经10.0.2.2访问，API29/36各自验证算法和IME，避免只在JVM通过。
3. OpenSSH+专用拒绝场景服务使用一次性账户/密钥，不连接用户现有服务器。上传JUnit、截图、logcat脱敏片段、APK、SHA256和构建版本清单。
4. 设置任务超时、并发取消和短期artifact保存；私有仓库runner额度依账户而定，不承诺免费或无限。仅Android/共享源路径触发；不把iOS全构建加入本轮CI。
5. 本机补齐JDK/SDK后可运行静态构建与ARM模拟器辅助查看UI；GitHub Actions不是模拟华为系统，也不保证国产输入法、后台限制和卓易通兼容。

## 发布与签名

早期CI产出明确标注debug的可安装测试APK，不能当正式发行包。正式可持续升级的Release APK需要固定签名身份：在发布阶段生成/保存专用keystore并配置受保护的GitHub secret，私钥不入Git；建立备份说明。未配置签名时Release只能标为未签名，不能宣称可直接安装。AAB/Play或华为商店上架不包含在当前任务。

## 实施顺序与门槛

先验证SSH算法、终端IME及API29三个最高风险点，再完成UI和功能对齐。各里程碑产物明确标为阶段版；最终必须对A01…A12逐项给出通过/未验证/不适用及证据。功能缺失不能仅以“首版”理由宣布全部完成。用户于本轮明确确认实施；已建立Android工程、工具链、受控服务和CI，按实际运行结果逐项记录。


## 实施收敛与偏差记录

- 实际锁定 AGP 8.10.1 / Gradle 8.11.1 / Kotlin 2.1.20 / Compose BOM 2025.05.01 / SSHJ 0.41.2 / BC 1.84；BC版本与SSHJ传递依赖保持一致。
- Android10本机ARM模拟器WebView91的SSH、加密私钥、IME、SFTP与UI均通过；云端API29镜像WebView74暴露额外兼容问题，终端脚本已降为Chrome70语法，继续以该环境的真实结果验收。
- AndroidView中的WebView需显式MATCH_PARENT布局。设备截图/DOM高度断言复现了键盘出现后零高度，已修正；另修正初始化缓冲与会话重放重复显示同一输出。
- 云端Actions artifact账户额度耗尽，不能上传测试附件。保留失败可见的构建/测试步骤，附加JUnit摘要到日志/step summary，附件上传单独标记失败；APK用本地文件与私有仓库Release附件交付，不删除无关项目数据。
- 已生成固定专用Release签名，私钥/口令仅在本机私有目录和GitHub加密Secrets，仓库只有使用说明。
- 本机同步目录产生重复生成dex文件，已将本地build和project cache迁到普通cache目录；CI保持标准目录。不是修改产品代码规避编译错误。
