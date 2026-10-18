# 0.2.4 公开发布

用户确认 MIT 开源，要求先查 GitHub 实现、保持代码简洁易维护、保证操作响应、本地构建 iOS IPA/Android APK，停用 GitHub Actions，并用单个0.2.4 Release替代全部旧Release。

## 范围和验收

- 保持 iOS SwiftUI/UIKit 与 Android Material 3；沿用原生文件选择、分享、应用打开，不引入通用路由框架或新的传输协议。
- 两端0.2.4，build/versionCode递增为7，Android保持原签名以支持覆盖升级。
- 文件读取和加密不阻塞界面；接收过程有进度反馈，旋转不丢失正在读取的安卓附件；无效文件可见错误。
- 验证外部冷/热打开、密码重试、导入预览、批量传输、临时文件与大小边界；不得以禁用测试掩盖失败。
- README完整介绍优势、平台兼容、安装、使用、安全、构建、测试、限制与贡献；新增MIT LICENSE，保留第三方许可。
- 公开之前检查Git历史与发布附件，不公开凭据。停用Actions且移除触发工作流。本地测试与打包。
- 新Release上传、校验成功后才删除旧Release；保留Git标签/历史，用户要求删除的是Release及其附件。

## 调研与选择

已搜索GitHub：
- [Skip Kit](https://github.com/skiptools/skip-kit)：文件选择的security-scoped授权必须覆盖实际读取生命周期。
- [CodePath Android sharing](https://github.com/codepath/android_guides/wiki/sharing-content-with-intents)：FileProvider content URI、EXTRA_STREAM、临时读权限；与现有实现相符。
- [OpenSwiftUI onOpenURL](https://github.com/OpenSwiftUIProject/OpenSwiftUI/blob/main/Sources/OpenSwiftUI/App/Scene/SceneBridge.swift)：事件交付依赖Scene生命周期。

采用这些成熟平台机制，无需移植整个第三方框架。项目已有格式与批量预览逻辑继续复用。查明的局部改善：iOS外部附件和选择器读取移到后台；Android接收任务绑定ViewModel避免旋转取消，显示名查询失败回退。保留加密强度，优化执行位置而非削弱KDF。

## ColorOS 17 终端问题补充

用户提供截图：top列折行、残留内容，并反馈键盘输入异常。具体手机和输入法未提供，用户随后只确认ColorOS17，不能声称已在该实体机验证。

新增验收：键盘按钮不随辅助栏滚动消失；轻点终端或按按钮可发起焦点/IME请求，DOM焦点建立后再调用系统输入法；文本缩放与字符网格测量一致。PTY创建前到达的43×17测量必须覆盖默认80×24，通道创建期间尺寸更新不丢失。保持英文/中文IME、窗口缩放和VT转义回归，不替换整个终端组件。

参考GitHub的[xterm移动输入问题](https://github.com/xtermjs/xterm.js/issues/2403)与[移动端限制](https://github.com/xtermjs/xterm.js/issues/5377)。不引入第三方输入框hack或复制不明许可代码。本项目聚焦已有WebView/原生输入法的焦点时序及SSH PTY状态。
