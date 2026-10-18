# 手机图标统一与部署

日期：2026-10-18。用户明确要求复用桌面 Modernterm 最新图标、两端统一、版本不变并部署 iPhone。

## 范围与实现

- 来源固定为桌面仓库 main 的 `1e08e044a587fd7a87c9492c015aab1ec596aa9a`（0.5.6），`assets/Modernterm.png`；保留原图于 `shared/branding/`，没有重新绘制图标。
- iOS 与 Android 使用字节一致的 1024×1024 RGB 图标。仅将原透明区域合成到 #111827，以适配 iOS 的不透明应用图标。来源说明见 `shared/branding/README.md`。
- 两端版本均保持 **0.2.3 (6)**。不修改连接、终端、加密导入导出或监控代码。

## 验收

- [x] 两端图标文件完全相同；iOS 图标无 alpha，尺寸 1024×1024；目视检查与上游终端及三色块图形一致。
- [x] iOS Release arm64 构建通过；生成的 IPA 版本为 0.2.3 / 6，不含 XCTest 包。
- [x] Android Release 构建与签名验证通过；APK 元数据确认 0.2.3 / 6、minSdk29 / targetSdk36。
- [x] 通过已有 LiveContainer 替换安装到 iPhone 17 / iOS27.2；新图标已显示，应用启动成功。
- [x] 安装前后 LCDataUUID 相同；12 条已保存连接的配置文件逐字节相同，启动后原列表正常显示。未连接远程服务器或修改凭据。
- [x] 核验结束后关闭 Device Hub 手机预览，避免影响系统软键盘。

本次仅替换资源，采用两端 Release 构建、产物检查与真机安装启动验证；没有为图标改动重新增加业务测试。原版本的功能验收保留于 specs/004-term-transfer/。

本机日志与设备核验材料在忽略目录 build/，不将手机截图、连接配置或设备容器信息上传到仓库。
