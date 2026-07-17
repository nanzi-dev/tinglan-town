# 《听澜镇》春季样板需求审计

审计日期：2026-07-17

审计基线：

- 原始需求：`pasted-text-1.txt`（江南自主小镇游戏实施计划）
- 设计规格：`docs/superpowers/specs/2026-07-16-tides-of-tinglan-design.md`
- 实施计划：`docs/superpowers/plans/2026-07-16-tides-of-tinglan-implementation.md`
- Godot 仓库分支：`main`
- Memoria 工作树：`/home/nanzi/PY3/Memoria-tinglan-game-api`
- Memoria 分支及提交：`feat/tinglan-game-api`，`05e9f8f`

结论：原始需求中的春季十四日样板范围均有实现和自动化、构建或视觉证据。
夏、秋、冬和年度结局按原需求明确属于后续独立内容包，不在本次验收范围内。

## 1. Memoria 游戏接口

| 原始要求 | 实现 | 证据 | 状态 |
| --- | --- | --- | --- |
| 新增版本化 `/api/v1/game` 路由，不改现有 Web 前端 | Memoria `src/memoria/api/game.py`、`src/memoria/main.py` | `tests/test_game_api.py` 覆盖路由注册、方法和未鉴权拒绝；Memoria 目标回归 102 项通过 | 通过 |
| 绑定 Godot `world_id/save_id` 到用户与 `story_id` | Memoria `game.py` 的 WorldBinding 模型与路由，`core/game_service.py`、`db/repository.py` | `test_world_binding_is_idempotent_and_requires_next_revision` 及 API 创建、读取、冲突测试 | 通过 |
| 批量智能体决策只能引用 Godot 合法候选动作 | Memoria `game.py` 的 AgentSnapshot/AgentDecision；`game_service.py` 的合法候选校验与本地回退 | Memoria 服务/API 测试；Godot `scripts/actors/agent_controller.gd`、`tests/unit/test_agent_controller.gd` | 通过 |
| 幂等批量社会事件投影到记忆、关系、事件和故事 | Memoria `game_service.py`、`repository.py`；Godot `pending_event_queue.gd` | Memoria 重试/冲突测试；`test_memoria_degraded_mode.gd` 和端到端恢复同步 | 通过 |
| 公告板任务响应支持接取、协商、拒绝或退出 | Memoria BoardTask 契约、`respond_to_board_task` | `tests/test_game_service.py` 与 `tests/test_game_api.py` 的任务响应枚举和回退断言 | 通过 |
| 所有接口携带 `request_id/tick_id`，模型不能改写世界 | Memoria Pydantic 契约；Godot `memoria_client.gd` 丢弃服务端世界变更字段 | Memoria 非法请求/响应测试；`test_valid_decision_strips_server_world_mutations` | 通过 |

所有 `/api/v1/game` 路由使用 `require_current_user_id`。Godot 从
`MEMORIA_ACCESS_TOKEN` 发送 Bearer token。

## 2. Godot 世界与智能体

| 原始要求 | 实现 | 证据 | 状态 |
| --- | --- | --- | --- |
| 独立 WorldClock、SimulationScheduler、AgentController、UtilityEvaluator、TaskBoard、ConversationManager、SaveCoordinator、MemoriaClient | `scripts/core/`、`scripts/actors/`、`scripts/services/` 对应同名模块 | 各模块独立单元测试；全量 Godot 测试 | 通过 |
| 一个游戏日为 24 分钟现实时间，支持暂停 | `world_clock.gd`：一现实秒推进一分钟，1,440 分钟换日 | `test_world_clock.gd` 的速率、换日、暂停和序列化测试 | 通过 |
| 移动、需求、工作、设施和寻路本地计算 | `player_controller.gd`、`needs_component.gd`、`schedule_component.gd`、`town_builder.gd`、`interior_builder.gd` | 玩家导航、需求、日程、室内和镇区集成测试 | 通过 |
| 近场实时、离屏粗时间片；普通行为不调用模型 | `simulation_scheduler.gd` 的 10/30 分钟 tick；`game_state.gd`、`utility_evaluator.gd` | `test_simulation_scheduler.gd`、`test_needs_component.gd`、十四日模拟 | 通过 |
| 重要社交选择每日 30 至 60 次批量预算 | `simulation_scheduler.gd` 的确定性每日预算 | 单元测试和 `test_fourteen_days.gd` 对每一天断言 30..60 | 通过 |
| 模型失败执行本地最高效用合法动作，HTTP 不阻塞主线程 | `agent_controller.gd`、异步 `memoria_client.gd`，重试为 0.5/1/2/4 秒 | AgentController、MemoriaClient 和降级模式测试 | 通过 |
| 检查点、幂等事件日志、崩溃恢复 | `save_coordinator.gd`、`domain_event_log.gd` | `test_save_coordinator.gd`、`test_crash_recovery.gd`、端到端恢复断言 | 通过 |
| 离线补算最多三个游戏日并产生“镇上近况”结构 | `SaveCoordinator.calculate_catchup` | `test_offline_catchup_is_capped_at_three_days`；端到端模拟离线五天只补三天 | 通过 |

十四日确定性证据：

- 固定种子：`20260716`
- 角色数：10
- 天数：14
- 黄金摘要：`tests/fixtures/fourteen_day_seed_20260716.json`
- 测试：`tests/simulation/test_fourteen_days.gd`

## 3. 场景、玩法与内容

| 原始要求 | 实现 | 证据 | 状态 |
| --- | --- | --- | --- |
| 正交等距镜头、简化 3D 江南建筑和手绘 2D 角色表现 | `isometric_camera.gd`、`town_builder.gd`、关键画面与居民头像资产 | `test_town_scene.gd` 验证正交 35 度镜头；`test_visual_identity.gd` 验证资产和十名居民头像 | 通过 |
| 一张连续室外镇区 | `scenes/town/town.tscn`、`town_builder.gd` | 三片可识别区域、连续河道、两座桥和统一导航区测试 | 通过 |
| 十个重点室内 | `content/spring/locations.json`、`interior_builder.gd`、`location_manager.gd` | `test_interiors.gd` 逐一构建十个唯一室内并验证出入口、家具和交互点 | 通过 |
| 键盘移动和点击寻路 | `player_controller.gd`、项目输入映射 | `test_player_navigation.gd` 覆盖键盘、点击、河流投影、建筑边界滑动和过桥 | 通过 |
| NPC 场景气泡；旁听后申请加入 | `speech_bubble.gd`、`conversation_manager.gd`、`conversation_panel.gd` | `test_join_conversation.gd`、`test_conversation_manager.gd`、端到端旁听加入流程 | 通过 |
| 自由输入、情境动作、可展开会话记录 | `conversation_panel.gd` 的发送、提供帮助和记录展开 | `test_player_can_join_speak_offer_help_and_expand_transcript` | 通过 |
| 关系数值隐藏，只显示初识/熟悉/亲近/戒备及最近原因 | `relationship_ledger.gd`、`relationship_panel.gd` | 关系单元测试和 UI 测试验证不泄露数值、仅显示最近三条原因 | 通过 |
| 公告板含结构化玩家任务 | `task_board.gd`、`task_board_panel.gd` | 任务状态机、20 个模板完成规则、玩家发布与字段错误测试 | 通过 |
| 十名 NPC、约二十个任务、一场节庆、一个项目、至少两名成年可恋爱 NPC | `content/spring/*.json` | `test_spring_content_matches_the_approved_scope` 精确断言 10/20/1/1/2；可恋爱角色年龄为 29 和 27 | 通过 |
| 不加入战斗、自由建造、复杂农业或重经营 | 春季内容与场景未定义对应系统；采集和物品只进入任务、送礼/项目所需数据流 | 代码和内容清单人工审计；README 明确样板边界 | 通过 |

## 4. 社区项目、节庆与端到端流程

| 验收流程 | 实现与测试证据 | 状态 |
| --- | --- | --- |
| 旁听并加入群聊 | `tests/e2e/test_spring_playthrough.gd`、`test_join_conversation.gd` | 通过 |
| 玩家发布任务，NPC 接取、完成并只领取一次奖励 | `TaskBoard` 状态机和端到端重复完成断言 | 通过 |
| 听雨桥收集、投票、施工、落成 | `community_project.gd`、`test_community_project.gd`、端到端五阶段推进 | 通过 |
| 春季第十二日 18:00 上巳水灯会 | `festival_manager.gd`、`festival.json` | 三种准备度分支测试和端到端高准备度分支 | 通过 |
| 保存、强制退出、恢复后状态一致 | `save_coordinator.gd`、崩溃恢复集成测试和端到端恢复 | 通过 |
| 重启不重复奖励、记忆、任务或项目事件 | 稳定事件 ID、按消费者去重、恢复高水位 | `test_crash_recovery.gd` 和端到端 effect count/event ID 断言通过 |
| Memoria 不可用时本地继续，恢复后同步 | `memoria_client.gd`、`pending_event_queue.gd` | `test_memoria_degraded_mode.gd` 和端到端同步载荷断言通过 |

端到端测试还验证了固定种子十四日模拟、关系事件幂等、离线五天只补算三天，
以及 Linux/Windows 导出预设和脚本存在。

## 5. 视觉证据

生成命令：

```bash
.tools/godot/godot --path . --resolution 1280x720 \
  --script res://tests/visual/capture_visuals.gd -- --size 1280x720

.tools/godot/godot --path . --resolution 960x540 \
  --script res://tests/visual/capture_visuals.gd -- --size 960x540
```

2026-07-17 两条命令均退出 0，各生成六张 PNG。证据目录被 Git 忽略：

```text
tests/visual/screenshots/1280x720-title.png
tests/visual/screenshots/1280x720-gameplay.png
tests/visual/screenshots/1280x720-task-board.png
tests/visual/screenshots/1280x720-conversation.png
tests/visual/screenshots/1280x720-relationships.png
tests/visual/screenshots/1280x720-pause.png
tests/visual/screenshots/960x540-title.png
tests/visual/screenshots/960x540-gameplay.png
tests/visual/screenshots/960x540-task-board.png
tests/visual/screenshots/960x540-conversation.png
tests/visual/screenshots/960x540-relationships.png
tests/visual/screenshots/960x540-pause.png
```

人工检查结果：

- 标题直接覆盖真实江南春季关键画面，不使用标题卡片。
- 两个视口的 HUD、对话、关系和暂停界面无文字或控件重叠。
- `960x540` 公告板采用紧凑纵向布局，表单可滚动且无横向裁切。
- 十名居民头像映射正确，关系面板只显示公开阶段和原因。
- 暂停层完全遮住实时世界，继续按钮和当前焦点清晰。

自动化视觉约束位于 `tests/integration/test_visual_identity.gd`；完整人工清单位于
`tests/visual/README.md`。

## 6. 实际验证命令

### Godot 全量测试

```bash
bash tools/test.sh
```

2026-07-17 结果：

```text
Scripts: 28
Tests: 215
Passing Tests: 215
Asserts: 6098
Exit: 0
```

测试输出中的 `ExpectedError` 是非法输入与恢复失败用例主动捕获的预期错误。

### Memoria 契约与相关回归

当前系统 Python 缺少仓库已声明的 `python-multipart==0.0.12`，因此使用临时
目录补齐该依赖，不修改仓库或用户环境：

```bash
deps_dir="$(mktemp -d /tmp/memoria-test-deps.XXXXXX)"
python3 -m pip install --target "$deps_dir" python-multipart==0.0.12
PYTHONPATH="${deps_dir}:src" pytest \
  tests/test_game_service.py \
  tests/test_game_api.py \
  tests/test_repository.py -q
```

结果：

```text
102 passed in 3.66s
Exit: 0
```

### 双平台导出

```bash
bash tools/export.sh
```

预期和实际产物：

```text
build/linux/tides-of-tinglan.x86_64
build/windows/tides-of-tinglan.exe
```

两个文件均为非空嵌入式 PCK 可执行文件；发布预设排除测试、工具和文档资源。
导出日志无 `ERROR` 或 `WARNING`。产物检查结果：

```text
Linux:   ELF 64-bit x86-64, 79,331,368 bytes
Windows: PE32+ GUI x86-64, 114,932,472 bytes
```

### Linux 构建冒烟

```bash
timeout 20s \
  build/linux/tides-of-tinglan.x86_64 --headless --quit-after 5
```

结果：退出 0，输出 Godot `4.7.1.stable` 启动标识，无主场景解析错误或资源缺失。

### 最终一致性检查

发布提交前执行：

```bash
git diff --check
bash tools/test.sh
bash tools/export.sh
git status --short --untracked-files=all
```

`.codegraph/`、`.vscode/`、`build/` 和视觉截图不进入发布提交。
