# Orexin 构建与发布

- 本机开发、测试和安装默认使用 Dev 渠道；当前本地版本为 `V1.1.3 Dev`。
- 本地执行 `scripts/build-app.sh` 默认生成 Dev 应用，沿用 Release 编译优化。
- 用户本机后续更新继续保留 Dev 标识，按开发进度调整版本号与构建号。
- GitHub 公开稳定版使用 `OREXIN_BUILD_CHANNEL=stable` 构建，版本不带 Dev 后缀；可通过 `OREXIN_VERSION` 指定公开版本号。
- GitHub 公开发布按用户授权执行；本地更新与公开发布分别处理。
