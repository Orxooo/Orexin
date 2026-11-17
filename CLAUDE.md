# Orexin

macOS 15+ 的保持唤醒工具（Stay awake. Rest on time.）。SwiftPM 工程，许可证 GPL-3.0-only。

## 结构
- `Sources/` — `WakeMacCore`、`WakeMacPower`，以及可执行目标 `WakeMac`、`WakeMacPowerHelper`
- `Tests/` — `WakeMacCoreTests`、`WakeMacAppTests`
- `Assets/`、`Resources/` — 图标、本地化资源
- `scripts/` — `build-app.sh`（打包 .app）、本地化提取/生成脚本
- `CHANGELOG.md`、`FEATURES.md`、`CONTRIBUTING.md` — 变更、功能与贡献说明

## 命令
- `swift build` / `swift test`
- CI 使用 `swift build --arch arm64`、`swift test --arch arm64`
- 打包 App：`./scripts/build-app.sh`

## 约定
- 遵循 `CONTRIBUTING.md`；涉及电源/唤醒逻辑的改动必须说明验证方式并补测试。
- 保持 macOS 15+ 兼容；Swift 源文件保留 SPDX 头（GPL-3.0-only）。
- 不提交构建产物、签名材料或本机配置。
- 系统电源状态相关行为要区分：编译通过、单元测试通过、真机验证通过，不能混为一谈。
