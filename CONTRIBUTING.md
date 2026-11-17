# 贡献指南

欢迎提交问题、文档修正和范围明确的 Pull Request。新功能或较大改动请先开 Issue 说明用途，避免重复工作。

## 开发

- 支持 Apple Silicon 与 macOS 15+；构建需要 Xcode 26+、Swift 6。
- 按 [README](README.zh-Hans.md#从源码构建) 构建；开发分支不必切到发布标签。
- 使用 `swift test --arch arm64 --scratch-path /tmp/orexin-test-build` 验证相关逻辑。
- 使用 `./scripts/build-app.sh` 检查 Release 包；需要合盖服务时用自己的 Apple 开发者证书签名。
- 不提交 `.build`、应用包、日志、签名证书、凭据或本机偏好。

## 构建渠道

本地构建默认使用 Dev 渠道，当前源码版本为 `V1.1.3 Dev`；Dev 渠道仍采用 Release 编译优化。

GitHub 公开稳定版显式使用 `OREXIN_BUILD_CHANNEL=stable`，并通过 `OREXIN_VERSION` 指定独立的公开版本号。渠道设置仅修改输出应用的 Info.plist，源码保持本地 Dev 默认值。

## Pull Request

描述具体问题、行为变化和实际验证结果。界面变化附前后截图；说明未验证的硬件或系统范围。保持改动聚焦，不在普通修复中增加无关依赖或功能。

主程序、脚本、快捷键和自动规则应共用状态核验与收尾逻辑。账户密码仅可在用户明确开启自动授权后保存到本机钥匙串；不得写入普通设置、文件、日志、进程参数或服务消息。保持系统认证，不自动解锁，也不扩大合盖服务接受的命令范围。Orexin 使用独立于旧 WakeMac 的 bundle ID 与数据目录，后续版本应保持 Orexin 的升级兼容性。

提交到当前版本的项目代码采用 GPL-3.0-only；外部资源须明确来源和独立许可。参与者遵守 [行为准则](CODE_OF_CONDUCT.md)。
