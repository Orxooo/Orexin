<p align="center"><img src="Assets/AppIcon.png" width="136" alt="Orexin 月牙图标"></p>

<h1 align="center">Orexin · V0.1.0 Preview</h1>

<p align="center">让 Mac 在工作时保持唤醒，在任务结束后安心休息。</p>

<p align="center">
  <a href="https://github.com/Orxooo/Orexin/releases/tag/v0.1.0-preview">下载 Preview</a> ·
  <a href="#功能">功能</a> ·
  <a href="#从源码构建">构建</a> ·
  <a href="FEATURES.md">完整功能清单</a> ·
  <a href="SECURITY.md">安全说明</a> ·
  <a href="https://github.com/Orxooo/Orexin/issues">问题反馈</a>
</p>

Orexin 是一款原生 macOS 菜单栏应用，管理保持唤醒、合盖运行、工作会话和任务完成后的休眠。它读取系统状态并核验模式切换；恢复正常休眠时释放**自身**的保活效果，由 macOS 决定实际休眠时机。

> **V0.1.0 Preview** 是 Orexin 的首个公开预览版本，面向 Apple Silicon Mac。代码采用 **GPL-3.0-only**：允许商业使用；对外分发衍生版本须按 GPL 提供对应源码并保留许可及版权声明。字体等第三方资源遵守各自许可，详见 [NOTICE](NOTICE)。

## 下载与安装

1. 前往 [V0.1.0 Preview 发布页](https://github.com/Orxooo/Orexin/releases/tag/v0.1.0-preview)，下载 `Orexin-0.1.0-Preview-arm64.zip`。
2. 解压并把 `Orexin.app` 移入「应用程序」，再打开应用。已有 Orexin 用户先在应用内结束工作并退出，再替换应用；现有数据与偏好保留。
3. 需要合盖继续运行时，按应用「偏好设置」中的提示批准辅助服务。临时保持未锁定仅在你亲自在原生窗口完成本次授权后生效。

**签名状态：**本预览包使用 Apple Development 证书签名，尚未通过 Developer ID 公证。macOS 可能阻止首次打开；请先核对下载来源与发布页的 `SHA256SUMS.txt`，再按「系统设置 → 隐私与安全性」中的提示处理。无需关闭全局 Gatekeeper 或系统完整性保护。不希望运行未公证包时，可以等待后续公证版本或自行构建。

Preview 版中的「关于软件 → 检查更新」也会识别 GitHub 的预发布版本。所有下载、更新记录和问题反馈集中在本仓库，现阶段没有独立官方网站。


## 功能

- **三种电源模式：**后台工作、桌面工作、正常休眠。主窗口与菜单栏面板均可切换，并显示实际核验结果。
- **工作会话：**手动结束、持续时长、指定时间、应用或进程退出、所选下载完成等结束条件。
- **自动触发和收尾：**根据电源、显示器、设备、应用、网络或周计划启动；按时长、命令结果或低电量结束。
- **命令任务：**执行由用户输入的非交互前台 zsh 命令；成功后进入可取消的 60 秒休眠倒计时，失败则保留状态和日志。
- **温度保护：**根据 macOS 提供的温度压力等级释放 Orexin 的保活效果，不推测摄氏温度，也不终止正在运行的命令。
- **外观与交互：**创：电子世界争霸战、齐马蓝、银翼杀手 2049 三套主题；菜单栏快捷面板、动效和可选的单声点击反馈。
- **七种界面语言：**简体中文、繁体中文、英语、日语、法语、德语、西班牙语，可在「主题外观」中切换。
- **本地控制：**全局快捷键、AppleScript、系统通知及最多 200 条本机运行记录。

![Orexin — Keep working. Rest when done.](Assets/README/cover.svg)

详细行为、适用条件和限制见 [功能清单](FEATURES.md)。

## 系统要求

- Apple Silicon Mac，macOS 15 或更新版本。
- 合盖继续运行需要使用同一 Apple 开发者证书签名的主程序和辅助服务，并在 macOS「登录项与扩展」中批准服务。普通桌面工作无需这项批准。
- 「工作时保持未锁定」需要授权系统服务，并在每次新工作会话开始时由你输入 Mac 账户密码。密码仅用于本次系统授权，不保存；工作结束、退出或服务恢复会恢复即时密码保护。Orexin 不解锁已锁定的 Mac。

### 工作时的屏幕行为

主窗口与菜单栏共用同一套屏幕策略，后台和桌面模式分别保存选择。

| 模式 | 屏幕选择 | 工作状态 |
| --- | --- | --- |
| 后台工作 | 亮度 0%、正常亮度、按系统时间熄屏；支持一次性立即熄屏 | 保持系统唤醒；已授权未锁定工作时，合盖后继续任务 |
| 桌面工作 | 亮度 0%、正常亮度、按系统时间熄屏；支持一次性立即熄屏 | 保持系统唤醒；合盖后允许正常休眠 |
| 正常休眠 | 按系统熄屏时间结束闲置 | 恢复亮度与密码保护，闲置到点请求休眠和锁定 |

最低亮度保留显示器会话，供截图和界面操作使用；熄屏会影响依赖显示器的自动化。按时熄屏分别读取电池与外接电源的 macOS 设置。定时结束、温度保护和低电量保护共同使用工作收尾路径。最低亮度使用系统 DisplayServices 能力，不可用或回读不一致时会显示未核验状态。

### 网络与设备权限

Wi-Fi 网络名称由 macOS 定位权限保护。自行构建的开源版本若没有定位授权声明或适用签名，系统可能不弹出授权窗口；Orexin 无法读取名称时会把条件标记为未知，规则不会匹配。可在「系统设置 → 隐私与安全性 → 定位服务」检查权限。

Cisco VPN 条件只读取 macOS 网络服务中名称包含 Cisco、AnyConnect 或 Secure Client 且向系统公开的连接状态。客户端若没有公开状态，Orexin 不会猜测，也不会把它当成已连接。

## 从源码构建

需要 Xcode 26 或兼容的 Swift 6 工具链。请在本项目检出目录执行：

```sh
swift test --arch arm64 --scratch-path /tmp/orexin-test-build
./scripts/build-app.sh
```

默认产物为 `/tmp/orexin-dist/Orexin.app`。默认使用 ad hoc 签名；合盖服务需要同一 Apple 开发者证书签名：

```sh
OREXIN_SIGN_IDENTITY='证书名称或 SHA-1' ./scripts/build-app.sh
```

`OREXIN_BUILD_DIR` 和 `OREXIN_OUTPUT_DIR` 可指定仓库外的构建与输出位置。签名脚本只生成本机应用包，不注册服务，也不修改系统权限。

### AppleScript

在「命令任务」页面可查看和复制脚本示例。Orexin 的脚本接口与界面共用状态核验：

```applescript
tell application "Orexin"
    start session mode "desktop" for minutes 30
    session status
    -- end session
end tell
```

完整词典见 [Orexin.sdef](Resources/Orexin.sdef)。

## 数据与隐私

新应用的 bundle ID 是 `com.orxooo.Orexin`，偏好设置键使用 `orexin.` 前缀；运行记录、命令日志和自定义资源存放在 `~/Library/Application Support/Orexin/`。旧 WakeMac 的 bundle ID、偏好和数据不会自动迁移或删除。运行记录和命令输出只保存在本机；分享日志前请检查私人信息。

## 参与项目

欢迎提交范围明确的改进。开发与验证约定见 [CONTRIBUTING.md](CONTRIBUTING.md)，许可见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)，安全问题处理方式见 [SECURITY.md](SECURITY.md)。功能建议和缺陷反馈请使用 [Issues](https://github.com/Orxooo/Orexin/issues)。
