# Orexin CLI 与并行工作请求

本接口从 `v0.2.0-preview` 起随应用发布，`v0.1.0-preview` 不包含此 CLI。从 V1.0.0 起改由独立后台任务服务提供接口，窗口进程无需常驻（V0.3.0 Preview.1 及更早版本仍要求主应用运行）。无需 Developer ID、公证或付费开发者会员即可构建和使用普通桌面请求；后台合盖与保持未锁定仍遵循现有辅助服务和本次原生授权要求。

## 安装包用法

打开当前版本界面会启动后台服务；也可以直接使用内置 CLI 启动服务，无需打开界面或配置 PATH：

```sh
orexin=/Applications/Orexin.app/Contents/Helpers/orexin
"$orexin" service-start
"$orexin" help
"$orexin" list --json
"$orexin" run --title Build -- make
```

若应用安装在其他位置，请相应调整路径；「任务管理 → 外部接入」会显示当前应用的准确路径。升级前等待命令与计划结束、结束保活；若旧版支持后台服务，运行 `service-stop`，再退出界面并替换应用。V0.3.0 Preview.1 及更早版本没有该服务命令，结束工作并退出旧版即可。退出界面不会停止服务任务；后台服务重启后，原活跃请求记为失联，未完成计划不重放。

## 构建与使用

```sh
swift build --arch arm64 --scratch-path /tmp/orexin-cli-build
/tmp/orexin-cli-build/debug/orexin help

# 同时生成应用包和独立 CLI，不安装、不注册服务
./scripts/build-app.sh
/tmp/orexin-dist/orexin help
```

构建脚本还会把 CLI 放入 `Orexin.app/Contents/Helpers/orexin`。可以直接使用绝对路径，不需要安装到 PATH。`service-start` 只启动无窗口进程，不注册登录项或安装 LaunchAgent；普通任务命令要求服务已启动。CLI 不会申请权限、输入密码或替换已安装应用。`OREXIN_SOCKET` 或 `--socket PATH` 可选择独立实例的接口；应用也读取 `OREXIN_SOCKET`。

## 后台服务与执行计划（V1.0.0 起）

- `service-start [--service-executable PATH]`：启动或复用当前用户的后台核心。构建目录中的 CLI 自动查找同目录 `WakeMac`，应用内 CLI 查找本应用主程序。
- `service-status`：查看 PID、实例 ID 与当前任务；`service-stop` 只在没有活跃请求、运行命令或未完成计划时退出。
- `plan-validate FILE`：只读校验，可离线执行；`plan-run FILE`：明确执行文件中的命令，提交后 CLI 可退出。
- `plan-list`、`plan-status UUID`：查看组与子任务进度；`plan-cancel UUID`：跳过待执行命令，已运行命令继续，最后释放整组保护。
- `stop-all`：立即撤销所有保活，并跳过计划中尚未启动的命令。已运行的命令继续，因此服务可能仍拒绝退出。
- `plan-run --id UUID` 可用同一 ID 重试同一份提交；已结束的 ID 不会重跑命令。

完整格式与例子见 [执行计划指南](EXECUTION-PLANS.md)。默认不安装常驻登录服务；登出、系统重启或服务异常退出后不会自动重放任务。界面中的旧会话、自动规则、鼠标与磁盘辅助效果仍由界面驱动，其保活需求作为带进程身份和 15 秒租约的请求提交；它们不等同于后台计划。界面退出或失联后仅此请求结束。后台任务、计划与原生电源保护由服务继续管理。

`OREXIN_STATE_DIR` 可与私有 `OREXIN_SOCKET` 配合隔离测试状态和偏好；普通使用无需设置。服务与界面应使用同一组路径。

## 包装命令

```sh
orexin run --title Build -- make
orexin run --title Backup --lease 60 -- /path/to/backup --verify
orexin run --title 'AI foreground task' --screen awake -- /path/to/agent
orexin run --title 'Short check' --timeout 300 --json -- /usr/bin/true
```

`--` 后的参数原样交给 `/usr/bin/env` 执行，默认继承当前目录和标准输入/输出；不会拼接成 shell 字符串。需要管道等 shell 语法时，显式使用 `-- /bin/zsh -c '...'`。只包装前台进程，不推断 GUI、后台分离任务或远端工作的完成。

- 默认是 `--mode desk --screen idle --after restore`。
- 包装器每隔租约的三分之一发送心跳，并使用自身 PID 和内核启动时间标识所有者。
- 正常退出保留子进程退出码；被信号终止时返回 `128 + signal`。SIGINT、SIGTERM、SIGHUP 转发给直接子进程。不会扫描或终止任意后代进程。
- 用户释放保活、全部停止或保护失效时，命令继续执行。若命令退出 0，但期间发现保活丢失或无法确认最终报告，包装器返回 75，并保留已知的实际退出码。
- `run --json` 将子命令输出送到 stderr，只在 stdout 输出一份最终 JSON。非 JSON 模式保留正常命令输出。
- `--after sleep` 仅在重叠请求全部成功、没有手动/会话/规则保活来源时安排可取消的 60 秒休眠倒计时。失败、取消、失联和到期都否决本批次的自动休眠；它们仍释放自身请求。

## 外部任务生命周期

适合能明确报告结果的脚本或工具：

```sh
# 所有者是这个长寿命报告脚本，而不是被等待的 worker。
handle=$(orexin register --title 'External build' --owner-pid $$ --lease 60)
orexin heartbeat "$handle"

# 由调用方运行自己的工作，并捕获真实结果。
/path/to/worker
code=$?
orexin complete "$handle" --exit-code "$code"
```

超过 60 秒的工作须在运行期间持续心跳，例如每 20 秒一次；普通前台命令优先使用 `run`，由包装器负责心跳和真实退出报告。登记本身不会执行命令。

```sh
orexin register --title 'Long report' --lease 120 --timeout 3600 --json
orexin heartbeat ID:TOKEN --json
orexin complete ID:TOKEN --exit-code 0 --json
orexin fail ID:TOKEN --exit-code 7 --json
orexin release ID:TOKEN --json
orexin cancel ID:TOKEN --json       # release 的别名，不发送进程信号
orexin status UUID --json
orexin list --json
orexin stop-all --json              # 明确的全局用户操作
```

`register` 输出 `ID:TOKEN` 所有者句柄；JSON 模式将其放在 `handle.id` 和 `handle.token`。变更单个请求必须携带该句柄。`status/list` 和持久记录不包含 token。`complete` 必须提供实际退出码，`fail` 必须提供非零退出码。

`--owner-pid` 可选，必须指向当前用户的、能够持续存活到 `complete` 的报告程序或 shell。不要填写随后会被 `wait` 的 worker PID。所有者消失只证明报告链失联，不证明工作成功。失联之后到达的有效报告会记录 `exitCode`，但不改变已经终止的保活状态，不重启保活或补发休眠。

租约为 5–3600 秒，默认 60 秒。心跳不能越过 `--timeout` 设置的绝对期限，不能复活已终止请求。每个实例最多 64 个活跃请求，并保留最近 200 个终态记录。应用重启将上次活跃记录标为 `lost`，不会重放命令或保活；旧句柄不能继续续约。

## 电源、屏幕与收尾规则

| 情况 | 结果 |
| --- | --- |
| 多项请求并行 | 各自拥有身份和生命周期；某一项完成或释放不撤销其他请求 |
| `desk` 与 `background` 重叠 | 合并为后台工作，继续走现有辅助服务及锁屏核验 |
| `awake`、`dim`、`idle` 重叠 | 正常亮度保持显示器 > 最低亮度保留显示器 > 允许系统闲置熄屏 |
| 手动工作、工作会话、自动规则仍有效 | 任务结束保留这些来源；自然会话/规则结束也保留其他任务 |
| 显示器断言、亮度或锁屏核验失败 | 不报告该屏幕需求已满足；新请求拒绝启动，已有请求显示未满足原因 |
| 用户选择“立即熄屏” | 暂停显示器需求，任务不会替用户点亮/解锁；状态会显示未满足 |
| 释放此请求 | 只撤销这一项保活，不杀命令 |
| 正常休眠、全部停止、全局定时到点 | 撤销当前全部请求，抑制当前规则；迟到完成/心跳不能重新开启 |
| 温度或低电量保护 | 具有最高优先级；保护收尾期间拒绝新登记，不终止命令 |
| 最后一项结束，默认 `restore` | 释放 Orexin 自己的保活；实际闲置休眠时机由 macOS 和原有正常模式策略决定 |
| 批次全部成功且选择了 `sleep` | 无其他保活来源时进入一次 60 秒倒计时；新请求或用户取消会撤销该倒计时 |

手动切换工作模式仍保留原有的会话/规则取消语义；独立任务需求参与合并，因此关闭合盖选项不能削弱另一项仍要求后台运行的任务。要撤销该需求，请释放对应请求或全部停止。不要把“保活已核验”理解为物理合盖、传感器或真实休眠已经验收。

在应用的「任务管理 → 任务列表」页面可以查看活跃请求、最近终态、来源、模式、屏幕需求、到期时间、实际退出码，以及每项命令的日志。单个请求与全部停止使用不同按钮。点击短 ID 旁的复制图标可复制完整请求 ID；「查看日志」打开该项任务的日志详情。已释放保活但仍在执行的内置命令会继续显示。

「运行命令」保留工作目录、语法预检与命令编辑器，已有任务运行时可继续准备并启动下一项任务。「外部接入」提供应用内置 CLI 的实际路径、可复制示例、本地接口状态，以及原有 AppleScript 控制。

## 本地协议 v1

默认地址 `/tmp/orexin-<uid>/control.sock`。父目录权限 0700，socket 权限 0600；客户端和服务端都检查对端 UID。端点锁防止第二个实例覆盖正在使用的接口，不监听 TCP、不对外公开、不提供远程服务。

每条连接处理一行 UTF-8 JSON 请求和一行 JSON 响应。请求上限 64 KiB、响应上限 512 KiB，读取/写入有超时；字段与 CLI 共用 `WakeMacCore/LocalControlProtocol.swift`。除请求生命周期与电源控制外，当前用户服务也接受明确提交的命令和执行计划（`command-start` / `plan-run`），以当前用户身份执行，不提权。它与仅执行固定电源接口的系统合盖辅助服务不同。

登记示例（用调用方生成的随机 UUID 替换占位符）：

```json
{"version":1,"operation":"register","handle":{"id":"REQUEST-UUID","token":"OWNER-TOKEN-UUID"},"spec":{"title":"Build","source":"external","mode":"desk","screen":"idle","leaseSeconds":60,"teardown":"restore"}}
```

可选 `deadline` 使用 ISO 8601 日期；可选 `process` 为当前用户报告进程的 `pid`、内核启动 `seconds` 与 `microseconds`，建议通过 CLI 生成。服务端固定来源为 `external`。相同句柄和相同参数的活跃登记可重试；已终止的句柄不能重新登记。旧终态超出保留数量后查询返回未知，不能将未知推断为成功。

其他操作为 `heartbeat`、`complete`、`release`、`status`、`list`、`stop-all`。前三者需要 `handle`，`complete` 另需整数 `exitCode`；`status` 可带 `id`。

响应的 `ok` 表示接口操作是否成功，任务真实结果看 `tasks[].request.state` 和 `exitCode`；当前保活是否满足看 `tasks[].satisfied`、`detail`、顶层 `mode` 与 `verified`。`commandRunning` 只描述应用内置命令，不推测外部任务。终态包括 `succeeded`、`failed`、`cancelled`、`lost`、`expired`、`overridden`、`rejected`。协议错误或不可核验状态不包装成成功。

V1.0.3 保持协议版本 1，新增可选 `capabilities` 和 `notices`。支持后台事件提醒的服务会返回 `capabilities: ["notices-v1"]`；`notices` 是经 JSON 编码后由 `Data` 字段转为 Base64 的有界消息数组，包含最多 64 KiB 的原始 JSON。旧服务不含这些字段时，界面提示提醒能力尚未完整启用；先完成任务，再退出旧服务并重开应用。

V1.0.4 的后台服务额外声明 `session-effects-v1`，工作请求可选 `preventScreenSaver` 以独立设置屏保行为。该字段未指定时沿用旧版行为；连接不支持此能力的旧服务时，界面会说明需要重启后台服务。

## 验证边界

V0.3.0 Preview.1 新增 `profiles`、`rules-try`、`power`、`events`、`config-export`、`config-import` 和注册/运行时的 `--profile UUID`。原有 v1 字段与操作兼容；检查操作不清理到期任务、不推进规则计时。配置导入默认只预览，应用要求精确预览令牌，导入脚本没有自动启用路径。完整格式、合并/替换、结果脚本与边界见 [工作配置指南](WORK-CONFIGURATION.md)。

自动测试包含策略合并、独立释放、真实 CLI 子进程经 Unix socket 调用实际 AppModel、退出码、信号、所有者丢失、租约/期限、用户与保护竞争、规则和屏幕状态。测试电源后端模拟原生状态；这些结果不代表真实合盖、整机休眠、锁屏或辅助服务授权已验收。构建脚本不安装应用，也不修改系统授权。
