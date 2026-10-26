# Orexin

**简体中文** · [English](README.en.md)

[![Release](https://img.shields.io/badge/Release-v1.0.3-56d7df)](https://github.com/Orxooo/Orexin/releases/tag/v1.0.3)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-8ba6b8)
[![CI](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml/badge.svg?branch=main)](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml)
[![GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-b7c8d6)](LICENSE)

Orexin 是 macOS 菜单栏保活工具，适合编译、下载和演示。支持合盖运行，按时间或任务完成情况结束保活。

[下载 V1.0.3](https://github.com/Orxooo/Orexin/releases/tag/v1.0.3) · [更新记录](CHANGELOG.md) · [使用手册](https://github.com/Orxooo/Orexin/wiki)

![Orexin V1.0.3 工作模式页面，创主题](Assets/README/orexin-1.0.3-modes.png)

## 功能

- **工作模式**：后台工作可阻止合盖休眠；桌面工作防止闲置休眠，合盖时仍可休眠。
- **屏幕控制**：亮度降至 0%、正常亮度、按系统时间熄屏，或立即熄屏。两种工作模式分别记住设置。
- **工作会话**：按时长、指定时间、应用或进程退出、下载完成等条件结束。
- **命令与执行计划**：并行运行命令，查看退出码和日志；用 JSON 编排依赖、并发数量和失败分支。
- **自动规则与配置**：按电源、显示器、设备、应用、网络或时间触发；支持嵌套条件、试运行和配置导入导出。
- **保护与提醒**：可启用低电量和高温保护，查看服务异常、会话结束预告和更新提醒。

提供创、齐马蓝、银翼杀手 2049 三套主题，支持中简、中繁、英、日、法、德、西七种语言。详细说明见 [功能清单](FEATURES.md)。

## 开始使用

<a id="系统要求"></a>

需要 **Apple Silicon Mac、macOS 15 或更新版本**。

1. 从 [发布页](https://github.com/Orxooo/Orexin/releases/tag/v1.0.3) 下载 `Orexin-1.0.3-arm64.zip`，解压并将 `Orexin.app` 放入「应用程序」。
2. 打开应用，选择工作模式和结束条件。合盖运行需要在「偏好设置」批准辅助服务。
3. 如需系统通知，在「消息提醒」中允许通知并发送测试提醒。

安装包使用 **Apple Development 签名，尚未完成 Developer ID 公证**。首次打开被拦截时，核对下载来源后按 macOS「隐私与安全性」提示操作，无需关闭 SIP 或全局 Gatekeeper。

将 ZIP 和发布页的 `SHA256SUMS.txt` 放在同一目录，可校验下载：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

### 升级

等待命令和执行计划完成，结束保活。旧版为 V1.0.0 或更新版本时，先退出后台任务服务：

```sh
/Applications/Orexin.app/Contents/Helpers/orexin service-stop
```

再退出 Orexin，替换应用并重新打开。预览版无需运行上述命令。现有偏好、记录和日志会保留，旧任务不会重放。

### 使用注意

- “工作时保持未锁定”是可选设置，需单独授权。它会在本次工作期间关闭唤醒密码要求，结束后恢复即时密码保护；Orexin 不保存密码，也不会解锁已锁定的 Mac。
- 亮度 0% 与熄屏不同。依赖显示器的截图或界面自动化可能在熄屏后受影响。
- 恢复正常模式只释放 Orexin 的保活，其他应用仍可能阻止休眠。
- 高温保护依据 macOS 的温度压力等级，不提供摄氏温度；降温后不会自动重启已停止的工作。

## 任务管理与 CLI

后台命令和执行计划可在退出界面后继续运行；手动会话和自动规则需要界面进程运行。服务重启后，未完成任务记为失联，不会自动重跑。

内置 CLI 位于应用包中，无需另行安装：

```sh
orexin=/Applications/Orexin.app/Contents/Helpers/orexin
"$orexin" service-start
"$orexin" run --title Build -- make
"$orexin" list --json
```

默认在命令结束后释放该任务的保活。加上 `--after sleep`，可在成功后进入 60 秒休眠倒计时；需要所有重叠请求成功，且没有其他会话或规则仍在保活。释放保活不会终止命令。

“工作时保持未锁定”的授权需先在界面完成，CLI 不会弹出密码窗口。参数、外部任务接入和计划格式见 [CLI 指南](docs/CLI.md) 与 [执行计划指南](docs/EXECUTION-PLANS.md)。

## 消息提醒与更新

「消息提醒」保留最近 100 条消息。应用在启动后及每 6 小时检查正式版更新，同一版本只提醒一次，下载和安装需手动完成。完全退出界面后停止检查。

系统通知受 macOS 权限和专注模式控制；未开启时仍可查看应用内消息。重要事件弹窗和高温提示音可单独设置。

## 从源码构建

需要 **Xcode 26+、Swift 6**。

```sh
git clone https://github.com/Orxooo/Orexin.git
cd Orexin
swift test --arch arm64 --scratch-path /tmp/orexin-test-build
./scripts/build-app.sh
```

输出为 `/tmp/orexin-dist/Orexin.app`，默认使用 ad hoc 签名。合盖服务要求主程序和辅助服务使用同一 Apple 开发者证书：

```sh
OREXIN_SIGN_IDENTITY='证书名称或 SHA-1' ./scripts/build-app.sh
```

可用 `OREXIN_BUILD_DIR`、`OREXIN_OUTPUT_DIR` 指定构建与输出目录。CI 配置为 Xcode 26.3、macOS 15 / 26，运行结果见 [Actions](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml)。

## 文档与反馈

- [工作配置](docs/WORK-CONFIGURATION.md) · [AppleScript 词典](Resources/Orexin.sdef) · [安全说明](SECURITY.md)
- [报告问题](https://github.com/Orxooo/Orexin/issues/new/choose) · [讨论](https://github.com/Orxooo/Orexin/discussions) · [私密漏洞报告](https://github.com/Orxooo/Orexin/security/advisories/new)
- [贡献指南](CONTRIBUTING.md) · [行为准则](CODE_OF_CONDUCT.md)

本地记录与日志位于 `~/Library/Application Support/Orexin/`。旧 WakeMac 数据不会自动迁移或删除，分享日志前请检查私人信息。

## 许可

[GPL-3.0-only](LICENSE) · © 2026 Orxooo。第三方资源许可见 [NOTICE](NOTICE)。
