# 执行计划（V1.0.0 起）

计划把命令归成一组，由独立后台进程推进。单个保活请求覆盖整组，包含命令切换间隙。界面或提交计划的 CLI 退出后继续运行。

```json
{
  "version": 1,
  "title": "Build and archive",
  "mode": "desk",
  "screen": "idle",
  "teardown": "restore",
  "maxConcurrent": 2,
  "tasks": [
    {"id": "build", "command": "make", "directory": "/absolute/project"},
    {"id": "backup", "command": "./backup.sh", "directory": "/absolute/project"},
    {"id": "archive", "command": "./archive.sh", "directory": "/absolute/project", "dependencies": ["build", "backup"], "condition": "success"}
  ]
}
```

```sh
orexin service-start
orexin plan-validate plan.json
orexin plan-run plan.json
orexin plan-list
orexin plan-status RUN_UUID --json
orexin plan-cancel RUN_UUID
```

界面入口：**任务管理 → 任务列表 → 任务组与执行计划 → 导入计划**。先查看完整命令、工作目录和依赖，再点“运行计划”。它会以当前用户身份执行 zsh 命令，不自动请求辅助服务或认证授权。

- `version`、`title`、`tasks` 必填。模式默认为 `desk`，屏幕 `idle`，收尾 `restore`。
- `maxConcurrent` 默认为 1，即按列表顺序在依赖允许时串行执行。2–16 允许并行；每次最多 8 个活跃计划，每个计划 1–64 条命令。
- ID 仅包含 ASCII 字母、数字、下划线、连字符，不能重复。依赖 ID 必须存在，不能形成环。
- 工作目录必须为存在的绝对路径。命令非交互运行，stdin 关闭；依赖和并发只适用于明确提交的前台命令，不追踪自行脱离的后台后代。
- `condition: "success"`（默认）：所有依赖成功后运行。失败会跳过依赖它的成功分支。
- `condition: "completion"`：所有依赖进入终态后运行，包括失败或跳过。
- `condition: "failure"`：所有依赖结束，且至少一项失败后运行。必须有依赖。
- 失败分支可以清理现场，但不能把整组失败改为成功。任意命令非零退出会令整组失败，并禁止成功后休眠。
- `teardown: "sleepOnSuccess"` 仅在整组成功、没有其他保活需求且当前批次无失败/取消等否决条件时进入既有 60 秒休眠倒计时。默认仅恢复正常休眠能力，不请求立即睡眠。
- **取消计划**：跳过待运行命令；已运行命令继续，结束后释放整组，不执行成功收尾。
- **全部停止保活**：立即撤销所有请求与计划保护，并禁止队列继续启动。命令继续运行；只有等实际命令结束后，服务才能空闲退出。
- 服务崩溃、登出或重启：原活跃请求和未完成计划标记为 `lost`，不推断成功，不重跑。命令是否仍在执行以实际进程为准。

每条命令的输出保存在 `~/Library/Application Support/Orexin/Task Logs/plan-RUN_UUID/TASK_ID.log`，上限 5 MiB。计划历史保存最近 30 个终态组及所有活跃组。`plan-status --json` 中 `document` 使用既有控制协议的 Base64 JSON 字段；`plan-status` 不带 `--json` 会直接输出计划 JSON。

普通桌面服务无需注册系统服务。合盖与保持未锁定仍需要现有辅助服务和明确的界面授权；服务与 CLI 不自动弹出密码框。测试不替代真实合盖、系统休眠、辅助服务重授权或高温/低电量验收。
