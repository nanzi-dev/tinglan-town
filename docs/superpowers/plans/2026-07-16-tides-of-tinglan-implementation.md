# 《听澜镇》春季样板实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `tinglan-town` 中交付可运行、可存档、可离线降级并通过十四日确定性模拟的《听澜镇》春季样板，同时在 Memoria 独立分支中提供版本化游戏接口。

**Architecture:** Godot 是世界事实的唯一权威，确定性核心与场景表现分离；Memoria 只对 Godot 提供的合法候选动作做社交选择并投影幂等社会事件。Godot 与 Memoria 通过 `/api/v1/game` JSON 契约异步通信，任何网络失败均立即走本地规则。

**Tech Stack:** Godot 4.7.1-stable、GDScript、GUT 9.7.0、FastAPI、Pydantic、pytest、HTTP JSON、Git worktree。

---

## 文件职责

### Godot 仓库

- `project.godot`：项目、输入映射、渲染和主场景设置。
- `scripts/core/world_clock.gd`：时间换算、暂停和序列化。
- `scripts/core/deterministic_rng.gd`：可序列化随机数状态。
- `scripts/core/simulation_scheduler.gd`：近场、离屏和社交批次调度。
- `scripts/core/utility_evaluator.gd`：合法候选动作评分。
- `scripts/core/task_board.gd`：公告板任务和幂等奖励。
- `scripts/core/relationship_ledger.gd`：隐藏关系值和公开阶段。
- `scripts/core/save_coordinator.gd`：检查点、事件日志与离线补算。
- `scripts/actors/player_controller.gd`：键盘移动、点击寻路和交互。
- `scripts/actors/agent_controller.gd`：NPC 候选动作、执行和回退。
- `scripts/services/memoria_client.gd`：异步 API、重试和健康状态。
- `scripts/services/conversation_manager.gd`：旁听、加入和会话日志。
- `scripts/services/game_state.gd`：组合核心服务并暴露运行时状态。
- `scripts/presentation/town_builder.gd`：生成连续 3D 镇区和十个室内入口。
- `scripts/presentation/character_visual.gd`：2D 精灵/名牌朝向相机和动画状态。
- `scripts/ui/hud.gd`：时间、日期、后端状态、提示和任务摘要。
- `scripts/ui/task_board_panel.gd`：三类任务的公告板操作。
- `scripts/ui/conversation_panel.gd`：旁听、申请加入、自由输入和记录。
- `content/spring/*.json`：角色、日程、任务、地点、节庆和项目数据。
- `tests/unit/*.gd`：纯规则测试。
- `tests/integration/*.gd`：场景与服务集成测试。
- `tests/simulation/test_fourteen_days.gd`：十名 NPC 十四日确定性验收。
- `tools/bootstrap_godot.sh`：安装固定版本 Godot、GUT 和导出模板。
- `tools/test.sh`：统一测试入口。
- `tools/export.sh`：Linux/Windows 导出入口。

### Memoria 独立工作树

CodeGraph 已确认现有路由、鉴权和持久化结构，新增文件职责固定为：

- `src/memoria/api/game.py`：版本化 Pydantic 契约和 `/api/v1/game` 路由。
- `src/memoria/core/game_service.py`：绑定、决策、社会事件和公告板业务。
- `src/memoria/db/repository.py`：增加绑定和幂等请求持久化函数。
- `src/memoria/main.py`：注册 `game_router`，不改动现有 Web 前端。
- `tests/test_game_api.py`：鉴权与 HTTP 契约。
- `tests/test_game_service.py`：非法动作、重复事件和模型回退。

## Task 1：固定工具链与最小可测试项目

**Files:**
- Create: `project.godot`
- Create: `.gitignore`
- Create: `tools/bootstrap_godot.sh`
- Create: `tools/test.sh`
- Create: `tests/unit/test_project_boot.gd`

- [ ] **Step 1: 写最小启动测试**

```gdscript
extends GutTest

func test_project_name_is_tides_of_tinglan() -> void:
    assert_eq(ProjectSettings.get_setting("application/config/name"), "Tides of Tinglan")
```

- [ ] **Step 2: 运行测试并确认因项目和 GUT 尚未建立而失败**

Run:

```bash
bash tools/test.sh tests/unit/test_project_boot.gd
```

Expected: 非零退出，提示 `tools/test.sh` 或 Godot/GUT 不存在。

- [ ] **Step 3: 建立固定版本工具链**

`tools/bootstrap_godot.sh` 必须：

1. 下载 Godot 4.7.1 Linux x86_64 到 `.tools/godot/`。
2. 下载并解压 GUT 9.7.0 到 `addons/gut/`。
3. 下载 Godot 4.7.1 导出模板到 `~/.local/share/godot/export_templates/4.7.1.stable/`。
4. 对已存在且版本匹配的文件保持幂等。
5. 打印实际 Godot 版本并在不匹配时失败。

`tools/test.sh` 使用：

```bash
.tools/godot/godot --headless --path . \
  -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit \
  -ginclude_subdirs \
  -gexit
```

- [ ] **Step 4: 建立项目设置**

`project.godot` 必须设置：

```ini
[application]
config/name="Tides of Tinglan"
config/description="《听澜镇》江南水乡生活模拟 RPG"
run/main_scene="res://scenes/main.tscn"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/default_filters/use_nearest_mipmap_filter=false
```

- [ ] **Step 5: 运行启动测试**

Run: `bash tools/test.sh tests/unit/test_project_boot.gd`

Expected: 1 test passed, 0 failed。

- [ ] **Step 6: 提交**

```bash
git add .gitignore project.godot tools addons tests/unit/test_project_boot.gd
git commit -m "build: bootstrap Godot test project"
```

## Task 2：世界时钟与确定性随机数

**Files:**
- Create: `scripts/core/world_clock.gd`
- Create: `scripts/core/deterministic_rng.gd`
- Create: `tests/unit/test_world_clock.gd`
- Create: `tests/unit/test_deterministic_rng.gd`

- [ ] **Step 1: 写时钟失败测试**

```gdscript
extends GutTest

const WorldClock = preload("res://scripts/core/world_clock.gd")

func test_one_real_second_advances_one_game_minute() -> void:
    var clock := WorldClock.new()
    clock.advance_real_seconds(1.0)
    assert_eq(clock.total_minutes, 1)

func test_pause_stops_time() -> void:
    var clock := WorldClock.new()
    clock.set_paused(true)
    clock.advance_real_seconds(60.0)
    assert_eq(clock.total_minutes, 0)

func test_day_rolls_after_1440_minutes() -> void:
    var clock := WorldClock.new()
    clock.advance_game_minutes(1440)
    assert_eq(clock.day, 2)
    assert_eq(clock.minute_of_day, 0)
```

- [ ] **Step 2: 运行并确认 `world_clock.gd` 缺失**

Run: `bash tools/test.sh tests/unit/test_world_clock.gd`

Expected: FAIL，无法预加载脚本。

- [ ] **Step 3: 实现最小时钟 API**

`WorldClock` 提供：

```gdscript
class_name WorldClock
extends RefCounted

const MINUTES_PER_DAY := 1440
var total_minutes := 0
var paused := false

var day: int:
    get: return total_minutes / MINUTES_PER_DAY + 1

var minute_of_day: int:
    get: return total_minutes % MINUTES_PER_DAY

func advance_real_seconds(seconds: float) -> void
func advance_game_minutes(minutes: int) -> void
func set_paused(value: bool) -> void
func to_dict() -> Dictionary
func restore(data: Dictionary) -> void
```

- [ ] **Step 4: 写 RNG 失败测试**

```gdscript
func test_same_seed_produces_same_sequence() -> void:
    var first := DeterministicRng.new(7319)
    var second := DeterministicRng.new(7319)
    for index in 20:
        assert_eq(first.next_int(0, 1000), second.next_int(0, 1000))

func test_restored_state_continues_sequence() -> void:
    var original := DeterministicRng.new(91)
    original.next_int(0, 100)
    var restored := DeterministicRng.new(0)
    restored.restore(original.to_dict())
    assert_eq(original.next_int(0, 100), restored.next_int(0, 100))
```

- [ ] **Step 5: 实现可序列化 xorshift64 RNG 并运行测试**

Run:

```bash
bash tools/test.sh tests/unit/test_world_clock.gd
bash tools/test.sh tests/unit/test_deterministic_rng.gd
```

Expected: 两组测试全部通过。

- [ ] **Step 6: 提交**

```bash
git add scripts/core tests/unit
git commit -m "feat: add deterministic world time"
```

## Task 3：效用评分、调度和 NPC 本地回退

**Files:**
- Create: `scripts/core/utility_evaluator.gd`
- Create: `scripts/core/simulation_scheduler.gd`
- Create: `scripts/actors/agent_controller.gd`
- Create: `tests/unit/test_utility_evaluator.gd`
- Create: `tests/unit/test_simulation_scheduler.gd`
- Create: `tests/unit/test_agent_controller.gd`

- [ ] **Step 1: 写合法候选评分测试**

```gdscript
func test_hunger_prefers_eating_over_chatting() -> void:
    var actions := [
        {"id": "eat", "base_utility": 0.2, "need_effects": {"hunger": -0.8}},
        {"id": "chat", "base_utility": 0.5, "need_effects": {"social": -0.4}},
    ]
    var scores := evaluator.score_all(
        {"hunger": 0.95, "social": 0.2},
        actions,
        {}
    )
    assert_gt(scores["eat"], scores["chat"])
```

- [ ] **Step 2: 写非法模型动作回退测试**

```gdscript
func test_unknown_memoria_action_uses_best_local_candidate() -> void:
    var candidates := [
        {"id": "work", "utility": 0.9},
        {"id": "rest", "utility": 0.4},
    ]
    var result := controller.resolve_decision(candidates, {
        "candidate_action_id": "invent-item"
    })
    assert_eq(result.id, "work")
    assert_eq(result.source, "local_fallback")
```

- [ ] **Step 3: 运行并确认失败**

Run:

```bash
bash tools/test.sh tests/unit/test_utility_evaluator.gd
bash tools/test.sh tests/unit/test_agent_controller.gd
```

Expected: FAIL，目标类不存在。

- [ ] **Step 4: 实现最小规则**

评分公式固定为：

```text
score = base_utility
      + need_urgency * need_relief
      + schedule_fit
      + relationship_context
      + task_priority
      - travel_cost
      - risk_cost
```

相同分数按候选动作 ID 字典序稳定排序。`AgentController.resolve_decision` 只接受候选集合中的 ID，否则返回最高本地分并标记 `local_fallback`。

- [ ] **Step 5: 写调度预算测试**

```gdscript
func test_social_batches_stay_within_daily_budget() -> void:
    var scheduler := SimulationScheduler.new(37)
    for tick in 144:
        scheduler.advance_logic_tick(tick * 10, [])
    assert_between(scheduler.social_batches_today, 30, 60)

func test_offscreen_agents_use_thirty_minute_ticks() -> void:
    var scheduler := SimulationScheduler.new(37)
    scheduler.advance_logic_tick(10, ["agent-a"])
    assert_false(scheduler.should_tick_offscreen("agent-a"))
    scheduler.advance_logic_tick(30, ["agent-a"])
    assert_true(scheduler.should_tick_offscreen("agent-a"))
```

- [ ] **Step 6: 实现调度并运行三组测试**

Expected: 所有测试通过，排序和预算结果固定。

- [ ] **Step 7: 提交**

```bash
git add scripts/core scripts/actors tests/unit
git commit -m "feat: add deterministic agent scheduling"
```

## Task 4：公告板、关系与幂等领域事件

**Files:**
- Create: `scripts/core/domain_event_log.gd`
- Create: `scripts/core/task_board.gd`
- Create: `scripts/core/relationship_ledger.gd`
- Create: `tests/unit/test_task_board.gd`
- Create: `tests/unit/test_relationship_ledger.gd`

- [ ] **Step 1: 写任务重复完成失败测试**

```gdscript
func test_duplicate_completion_pays_reward_once() -> void:
    board.add_task({
        "task_id": "herb-01",
        "status": "accepted",
        "reward": {"coins": 80},
        "completion_rules": [{"type": "has_item", "item_id": "mint", "count": 3}]
    })
    var inventory := {"mint": 3}
    var first := board.complete_task("herb-01", "event-100", inventory)
    var duplicate := board.complete_task("herb-01", "event-100", inventory)
    assert_eq(first.reward.coins, 80)
    assert_eq(duplicate.reward.coins, 0)
```

- [ ] **Step 2: 写关系公开阶段测试**

```gdscript
func test_relationship_hides_numeric_values() -> void:
    ledger.apply_change("lin-xi", 18, 12, 0, "履行了送茶承诺", "rel-1")
    var view := ledger.public_view("lin-xi")
    assert_has(view, "stage")
    assert_does_not_have(view, "affinity")
    assert_eq(view.recent_reasons[0], "履行了送茶承诺")
```

- [ ] **Step 3: 运行并确认失败**

Run:

```bash
bash tools/test.sh tests/unit/test_task_board.gd
bash tools/test.sh tests/unit/test_relationship_ledger.gd
```

- [ ] **Step 4: 实现领域事件去重、任务状态机和关系阶段**

任务状态只允许：

```text
draft -> open -> accepted -> completed -> rewarded
                    \-> withdrawn
open -> expired
```

公开关系阶段规则：

```text
guarded：戒备 >= 45
close：信任 >= 65 且好感 >= 60
familiar：信任 >= 30 或好感 >= 35
acquainted：其他情况
```

UI 中文映射分别为 `戒备`、`亲近`、`熟悉`、`初识`。

- [ ] **Step 5: 运行测试并提交**

```bash
bash tools/test.sh tests/unit/test_task_board.gd
bash tools/test.sh tests/unit/test_relationship_ledger.gd
git add scripts/core tests/unit
git commit -m "feat: add idempotent tasks and relationships"
```

## Task 5：检查点、事件日志和离线补算

**Files:**
- Create: `scripts/core/save_coordinator.gd`
- Create: `tests/unit/test_save_coordinator.gd`
- Create: `tests/integration/test_crash_recovery.gd`

- [ ] **Step 1: 写三日上限失败测试**

```gdscript
func test_offline_catchup_is_capped_at_three_days() -> void:
    var result := coordinator.calculate_catchup(
        0,
        10 * WorldClock.MINUTES_PER_DAY * 60
    )
    assert_eq(result.capped_days, 3)
    assert_eq(result.to_tick, 3 * WorldClock.MINUTES_PER_DAY)
```

- [ ] **Step 2: 写崩溃恢复去重失败测试**

测试先保存 `checkpoint.json`，再向 `events.jsonl` 写入两次同一 `event_id`，加载后断言奖励、关系和项目阶段各只推进一次。

- [ ] **Step 3: 运行并确认失败**

Run:

```bash
bash tools/test.sh tests/unit/test_save_coordinator.gd
bash tools/test.sh tests/integration/test_crash_recovery.gd
```

- [ ] **Step 4: 实现原子检查点**

保存顺序：

1. 写 `checkpoint.json.tmp`。
2. 关闭文件并检查错误码。
3. 将现有检查点改名为 `.bak`。
4. 将临时文件改名为 `checkpoint.json`。
5. 成功后删除 `.bak`。

事件日志每行一个 JSON 对象。加载时先恢复检查点的 `last_event_sequence` 和 `processed_event_ids`，再应用更高序号且未处理的事件。

- [ ] **Step 5: 实现离线摘要**

`OfflineCatchupResult` 必须输出 `from_tick`、`to_tick`、`capped_days`、`key_events`、`task_changes`、`relationship_changes` 和由本地模板生成的 `town_digest`。

- [ ] **Step 6: 运行测试并提交**

```bash
bash tools/test.sh tests/unit/test_save_coordinator.gd
bash tools/test.sh tests/integration/test_crash_recovery.gd
git add scripts/core tests
git commit -m "feat: add crash-safe world saves"
```

## Task 6：春季内容数据与校验器

**Files:**
- Create: `content/spring/characters.json`
- Create: `content/spring/schedules.json`
- Create: `content/spring/tasks.json`
- Create: `content/spring/locations.json`
- Create: `content/spring/community_project.json`
- Create: `content/spring/festival.json`
- Create: `scripts/core/content_repository.gd`
- Create: `tests/unit/test_spring_content.gd`

- [ ] **Step 1: 写内容数量失败测试**

```gdscript
func test_spring_content_has_required_scope() -> void:
    var content := ContentRepository.new()
    assert_true(content.load_spring())
    assert_eq(content.characters.size(), 10)
    assert_eq(content.locations.filter(func(item): return item.is_interior).size(), 10)
    assert_eq(content.task_templates.size(), 20)
    assert_eq(content.characters.filter(func(item): return item.romanceable).size(), 2)
```

- [ ] **Step 2: 写引用完整性失败测试**

所有日程地点必须存在；任务发布者必须存在；可恋爱角色年龄必须大于等于 18；项目必须有五个有序阶段；节庆日期必须为春季第十二日。

- [ ] **Step 3: 运行并确认失败**

Run: `bash tools/test.sh tests/unit/test_spring_content.gd`

- [ ] **Step 4: 写入设计规格中的十名角色、十一个区域和二十个任务模板**

任务类别数量固定为：采集 5、递送 4、探访 3、修缮 3、调查 2、社交承诺 2、节庆准备 1。

- [ ] **Step 5: 实现 JSON 校验和只读访问**

`ContentRepository.load_spring()` 在任何引用错误时返回 `false` 并保留具体 `validation_errors`。

- [ ] **Step 6: 运行测试并提交**

```bash
bash tools/test.sh tests/unit/test_spring_content.gd
git add content scripts/core/content_repository.gd tests/unit
git commit -m "feat: add spring town content"
```

## Task 7：主场景、连续镇区和玩家移动

**Files:**
- Create: `scenes/main.tscn`
- Create: `scenes/town/town.tscn`
- Create: `scenes/actors/player.tscn`
- Create: `scripts/presentation/town_builder.gd`
- Create: `scripts/actors/player_controller.gd`
- Create: `scripts/presentation/isometric_camera.gd`
- Create: `tests/integration/test_town_scene.gd`
- Create: `tests/integration/test_player_navigation.gd`

- [ ] **Step 1: 写镇区结构失败测试**

实例化 `town.tscn` 并断言：

- 有三段可识别街区。
- 有一条连续河道和至少两座桥。
- 十个室内入口均存在且 ID 唯一。
- 导航区域已烘焙或运行时生成。

- [ ] **Step 2: 写输入和寻路失败测试**

模拟 `move_left` 后断言玩家速度向量变化；向可达导航点发出点击命令后断言路径非空；点击河道不可达区域时断言目标被投影到最近可达点。

- [ ] **Step 3: 运行并确认失败**

Run:

```bash
bash tools/test.sh tests/integration/test_town_scene.gd
bash tools/test.sh tests/integration/test_player_navigation.gd
```

- [ ] **Step 4: 建立程序化简化 3D 镇区**

使用 `MeshInstance3D`、`StaticBody3D`、`NavigationRegion3D`、`CSGBox3D` 或预制基础网格组成白墙、青灰瓦、木桥、河岸和道路。正交相机固定 35 度俯角，可在有限范围内缩放。

- [ ] **Step 5: 实现键盘和点击寻路**

输入动作：

```text
move_up: W / Up
move_down: S / Down
move_left: A / Left
move_right: D / Right
interact: E / Enter
open_tasks: J
open_inventory: I
pause_game: Escape
```

- [ ] **Step 6: 运行测试和无头场景启动**

Run:

```bash
bash tools/test.sh tests/integration/test_town_scene.gd
.tools/godot/godot --headless --path . --quit-after 120
```

Expected: 测试通过；主场景无解析错误或孤儿节点警告。

- [ ] **Step 7: 提交**

```bash
git add project.godot scenes scripts tests/integration
git commit -m "feat: build playable Tinglan town"
```

## Task 8：十个室内与场景切换

**Files:**
- Create: `scenes/interiors/interior.tscn`
- Create: `scripts/presentation/interior_builder.gd`
- Create: `scripts/services/location_manager.gd`
- Create: `tests/integration/test_interiors.gd`

- [ ] **Step 1: 写十个室内失败测试**

依次加载 `player_home`、`tea_house`、`general_store`、`clinic`、`workshop`、`bookshop`、`community_center`、`shen_home`、`gu_home`、`qiao_home`，断言每个场景有：

- 唯一地点 ID。
- 玩家出生点。
- 返回室外的出口。
- 至少一个用途交互点。

- [ ] **Step 2: 运行并确认失败**

Run: `bash tools/test.sh tests/integration/test_interiors.gd`

- [ ] **Step 3: 实现数据驱动室内**

`InteriorBuilder` 根据 `locations.json` 的尺寸、地板色、墙色、家具布局和用途交互点生成室内。`LocationManager` 保存室外离开位置，并在返回时恢复。

- [ ] **Step 4: 运行测试并提交**

```bash
bash tools/test.sh tests/integration/test_interiors.gd
git add scenes/interiors scripts content tests/integration
git commit -m "feat: add ten town interiors"
```

## Task 9：NPC 日程、需求和十四日模拟

**Files:**
- Create: `scenes/actors/npc.tscn`
- Create: `scripts/actors/needs_component.gd`
- Create: `scripts/actors/schedule_component.gd`
- Create: `scripts/services/game_state.gd`
- Create: `tests/unit/test_needs_component.gd`
- Create: `tests/unit/test_schedule_component.gd`
- Create: `tests/simulation/test_fourteen_days.gd`

- [ ] **Step 1: 写需求暂停和离屏结算失败测试**

暂停时需求不变化；离屏 30 分钟结算结果与三个连续 10 分钟粗 tick 的容差不超过 `0.001`。

- [ ] **Step 2: 写日程失败测试**

对每名 NPC 的春季普通日运行 144 个逻辑 tick，断言工作时段到达职业地点、睡眠时段到达住宅、日程不存在空地点。

- [ ] **Step 3: 写十四日确定性失败测试**

```gdscript
func test_fourteen_days_are_reproducible() -> void:
    var first := simulate(20260716, 14)
    var second := simulate(20260716, 14)
    assert_eq(first.sha256_text(), second.sha256_text())
    assert_eq(first.unique_agents, 10)
    assert_gt(first.encounters, 0)
    assert_gt(first.task_changes, 0)
    assert_gt(first.relationship_changes, 0)
```

- [ ] **Step 4: 运行并确认失败**

Run:

```bash
bash tools/test.sh tests/unit/test_needs_component.gd
bash tools/test.sh tests/unit/test_schedule_component.gd
bash tools/test.sh tests/simulation/test_fourteen_days.gd
```

- [ ] **Step 5: 实现十名 NPC 模拟**

近场角色使用导航代理实时移动；离屏角色按调度器粗结算并只记录地点级位置。相遇事件由同地点且时间段重叠产生，使用稳定事件 ID：

```text
encounter:<day>:<tick>:<sorted-character-ids>
```

- [ ] **Step 6: 运行十四日测试并保存黄金摘要**

生成 `tests/fixtures/fourteen_day_seed_20260716.json`，后续运行必须逐字段一致。

- [ ] **Step 7: 提交**

```bash
git add scenes/actors scripts content tests
git commit -m "feat: simulate ten autonomous residents"
```

## Task 10：HUD、公告板、关系档案和背包

**Files:**
- Create: `scenes/ui/hud.tscn`
- Create: `scenes/ui/task_board_panel.tscn`
- Create: `scenes/ui/relationship_panel.tscn`
- Create: `scenes/ui/inventory_panel.tscn`
- Create: `scripts/ui/hud.gd`
- Create: `scripts/ui/task_board_panel.gd`
- Create: `scripts/ui/relationship_panel.gd`
- Create: `scripts/ui/inventory_panel.gd`
- Create: `scripts/ui/theme_factory.gd`
- Create: `tests/integration/test_ui_workflows.gd`

- [ ] **Step 1: 写 HUD 状态失败测试**

断言 HUD 显示春季日、时间、天气、Memoria 状态、交互提示和任务摘要；暂停时显示明确暂停状态。

- [ ] **Step 2: 写公告板发布任务失败测试**

填写结构化类型、目标、地点、期限、报酬、完成条件和自由描述后提交，断言任务来源为 `player` 且进入 `open` 状态；缺失结构化目标时显示字段级错误。

- [ ] **Step 3: 写关系隐私失败测试**

关系档案只显示四类中文阶段和最近三条原因，不渲染底层数值。

- [ ] **Step 4: 运行并确认失败**

Run: `bash tools/test.sh tests/integration/test_ui_workflows.gd`

- [ ] **Step 5: 实现 8 像素间距体系和语义配色**

颜色令牌：

```text
ink: #21302d
paper: #f4f1e8
mist: #dbe5df
willow: #6e8b63
wood: #8a6747
seal: #a93d35
water: #5f8991
warning: #b56a2d
```

正常正文与背景对比度达到 4.5:1；所有按钮最小高度 44 像素并有键盘焦点。

- [ ] **Step 6: 运行测试并提交**

```bash
bash tools/test.sh tests/integration/test_ui_workflows.gd
git add scenes/ui scripts/ui tests/integration
git commit -m "feat: add town HUD and civic panels"
```

## Task 11：旁听、申请加入与对话记录

**Files:**
- Create: `scripts/services/conversation_manager.gd`
- Create: `scenes/ui/conversation_panel.tscn`
- Create: `scripts/ui/conversation_panel.gd`
- Create: `scripts/presentation/speech_bubble.gd`
- Create: `tests/unit/test_conversation_manager.gd`
- Create: `tests/integration/test_join_conversation.gd`

- [ ] **Step 1: 写加入状态机失败测试**

```gdscript
func test_player_cannot_speak_before_join_is_accepted() -> void:
    var context := manager.start_npc_conversation(["lin-xi", "shen-yan"], "听雨桥")
    manager.listen(context.conversation_id)
    var result := manager.submit_player_text(context.conversation_id, "我能帮忙吗？")
    assert_false(result.accepted)
    assert_eq(result.reason, "join_required")
```

- [ ] **Step 2: 写完整加入流程失败测试**

旁听后申请加入，本地或 Memoria 返回 `accepted`，再提交自由输入和 `offer_help` 情境动作；展开记录后能看到 NPC 原对话、加入请求和玩家发言。

- [ ] **Step 3: 运行并确认失败**

Run:

```bash
bash tools/test.sh tests/unit/test_conversation_manager.gd
bash tools/test.sh tests/integration/test_join_conversation.gd
```

- [ ] **Step 4: 实现对话状态机和本地模板**

状态严格为 `listening -> requested -> accepted|declined`。普通场景气泡来自本地模板；重要社交选择可请求 Memoria，但超时后在 250 毫秒内使用本地人格规则作答。

- [ ] **Step 5: 运行测试并提交**

```bash
bash tools/test.sh tests/unit/test_conversation_manager.gd
bash tools/test.sh tests/integration/test_join_conversation.gd
git add scripts/services scripts/ui scripts/presentation scenes/ui tests
git commit -m "feat: add listen-and-join conversations"
```

## Task 12：社区项目和上巳水灯会

**Files:**
- Create: `scripts/core/community_project.gd`
- Create: `scripts/core/festival_manager.gd`
- Create: `tests/integration/test_community_project.gd`
- Create: `tests/integration/test_festival.gd`

- [ ] **Step 1: 写项目阶段和重复投票失败测试**

同一 NPC 的同一 `project_vote` 事件重复提交时只记录一票；材料、资金和支持票达到阈值后依次进入 `proposed`、`collecting`、`voting`、`construction`、`completed`。

- [ ] **Step 2: 写节庆分支失败测试**

春季第十二日 18:00 触发节庆。准备度低、中、高分别产生不同装饰级别和出席人数，但都生成完成事件，不产生坏结局。

- [ ] **Step 3: 运行并确认失败**

Run:

```bash
bash tools/test.sh tests/integration/test_community_project.gd
bash tools/test.sh tests/integration/test_festival.gd
```

- [ ] **Step 4: 实现本地权威规则**

项目投票依据人格权重、与提案者关系、玩家提供证据和资源缺口计算；Memoria 只能在 `support`、`oppose`、`abstain` 候选中选择。

- [ ] **Step 5: 运行测试并提交**

```bash
bash tools/test.sh tests/integration/test_community_project.gd
bash tools/test.sh tests/integration/test_festival.gd
git add scripts/core content tests/integration
git commit -m "feat: add bridge project and spring festival"
```

## Task 13：隔离 Memoria 工作树并实现游戏 API

**Files:**
- Modify/Create in: `/home/nanzi/PY3/Memoria-tinglan-game-api`
- Test in: Memoria existing test tree

- [ ] **Step 1: 使用 CodeGraph 探索现有结构**

Run:

```bash
cd /home/nanzi/PY3/Memoria
codegraph explore "FastAPI app creation, router registration, authentication dependencies, story service, memory service, relationship service, event service, and their tests"
```

Expected: 返回当前文件路径、行号、符号源码和调用路径。不得先用 grep 猜测。

- [ ] **Step 2: 检查隔离状态并创建独立工作树**

Run:

```bash
git -C /home/nanzi/PY3/Memoria rev-parse --git-dir
git -C /home/nanzi/PY3/Memoria rev-parse --git-common-dir
git -C /home/nanzi/PY3/Memoria worktree add \
  /home/nanzi/PY3/Memoria-tinglan-game-api \
  -b feat/tinglan-game-api
```

Expected: 当前 Memoria 工作目录保持原分支和全部未提交修改；新工作树位于指定路径并处于 `feat/tinglan-game-api`。

- [ ] **Step 3: 运行 Memoria 基线测试**

使用仓库现有虚拟环境和测试命令。若全量测试过慢，至少运行路由、鉴权、故事、记忆、关系和事件相关测试并记录结果。

- [ ] **Step 4: 先写契约失败测试**

覆盖：

```text
POST /api/v1/game/world-bindings
GET  /api/v1/game/world-bindings/{world_id}/{save_id}
POST /api/v1/game/agent-decisions:batch
POST /api/v1/game/social-events:batch
POST /api/v1/game/board-tasks/{task_id}/responses
GET  /api/v1/game/health
```

每个写请求检查鉴权、`request_id`、`tick_id`、枚举约束和状态码。

- [ ] **Step 5: 运行测试并确认 404 或导入失败**

Run: 仓库对应的精确 pytest 文件。

Expected: 新路由测试失败，现有测试仍通过。

- [ ] **Step 6: 实现 Pydantic 契约和路由**

决策响应验证：

```python
candidate_ids = {
    candidate.candidate_action_id
    for snapshot in request.snapshots
    for candidate in snapshot.legal_candidates
}
if decision.candidate_action_id not in candidate_ids:
    decision = local_fallback(snapshot)
```

社会事件存储以 `event_id` 唯一；重复请求返回首次处理结果和 `duplicate: true`，不再次调用投影服务。

- [ ] **Step 7: 接入现有人格、记忆、关系、事件与故事服务**

通过适配器调用现有公开服务，不修改 Web 前端，不让游戏路由直接操作前端数据结构。

- [ ] **Step 8: 运行契约和全量测试**

Expected: 新增测试全部通过；现有测试无回归。

- [ ] **Step 9: 在 Memoria 独立分支提交**

```bash
git add \
  src/memoria/api/game.py \
  src/memoria/core/game_service.py \
  src/memoria/db/repository.py \
  src/memoria/main.py \
  tests/test_game_api.py \
  tests/test_game_service.py
git commit -m "feat: add versioned game integration API"
```

## Task 14：Godot 异步 Memoria 客户端与恢复同步

**Files:**
- Create: `scripts/services/memoria_client.gd`
- Create: `scripts/services/pending_event_queue.gd`
- Create: `tests/unit/test_memoria_client.gd`
- Create: `tests/integration/test_memoria_degraded_mode.gd`

- [ ] **Step 1: 写候选动作验证失败测试**

模拟服务返回不存在的候选 ID，断言客户端标记协议错误，`AgentController` 使用本地最高效用动作，世界状态不接受服务端附带的位置、物品或时间字段。

- [ ] **Step 2: 写不可用降级失败测试**

连接拒绝时断言：

- 主线程未阻塞。
- 连接状态为 `recoverable_error`。
- 本地行为继续。
- 社会事件进入去重队列。
- 服务恢复后只发送未确认事件。

- [ ] **Step 3: 运行并确认失败**

Run:

```bash
bash tools/test.sh tests/unit/test_memoria_client.gd
bash tools/test.sh tests/integration/test_memoria_degraded_mode.gd
```

- [ ] **Step 4: 实现异步请求**

使用 Godot `HTTPRequest` 信号，不使用同步 shell 或阻塞等待。重试延迟为 0.5、1、2、4 秒，上限四次；健康检查与游戏请求分开。

- [ ] **Step 5: 实现待同步事件队列**

队列按 `event_id` 去重并持久化到存档目录。收到 Memoria 成功确认后删除；重启后继续发送。

- [ ] **Step 6: 运行测试并提交**

```bash
bash tools/test.sh tests/unit/test_memoria_client.gd
bash tools/test.sh tests/integration/test_memoria_degraded_mode.gd
git add scripts/services tests
git commit -m "feat: integrate Memoria with offline fallback"
```

## Task 15：真实视觉资产、角色表现与场景截图验收

**Files:**
- Create: `assets/environments/tinglan_spring_key_art.png`
- Create: `assets/characters/resident_portraits.png`
- Create: `assets/ui/paper_texture.png`
- Modify: relevant materials and scenes
- Create: `tests/visual/README.md`

- [ ] **Step 1: 使用内置图像生成工具生成项目资产**

生成三类项目内资产：

1. 江南春季镇区关键画面，用于标题和暂停背景。
2. 十名居民的统一风格头像图集。
3. 低对比、可平铺纸纹理。

生成结果必须复制到上述 `assets/` 路径，不引用工具默认目录。

- [ ] **Step 2: 本地检查资产尺寸、色彩模式和可读性**

使用图像查看工具确认无水印、无错误文字、角色数量正确、关键主体未裁切。用 ImageMagick 或 Pillow 检查 PNG 可读取且 alpha/色彩模式符合用途。

- [ ] **Step 3: 接入场景与 UI**

标题画面不放入卡片；头像只在对话和关系档案使用；纸纹理透明度保持在不影响正文对比度的范围。

- [ ] **Step 4: 启动游戏并截取桌面与小窗口画面**

使用 1280×720 和 960×540 视口检查：

- 无 UI 重叠。
- 中文文字不溢出。
- HUD 不遮挡玩家和交互对象。
- 对话、公告板和暂停面板可由键盘关闭。

- [ ] **Step 5: 提交**

```bash
git add assets scenes scripts tests/visual
git commit -m "feat: add Tinglan visual identity"
```

## Task 16：端到端、构建与完成审计

**Files:**
- Create: `tests/e2e/test_spring_playthrough.gd`
- Create: `export_presets.cfg`
- Create: `tools/export.sh`
- Create: `README.md`
- Create: `docs/verification/requirements-audit.md`

- [ ] **Step 1: 写端到端春季流程**

自动化流程依次执行：

1. 新建固定种子世界。
2. 旁听并加入群聊。
3. 发布玩家任务。
4. 让 NPC 接取并完成任务。
5. 推进听雨桥项目、投票、施工和落成。
6. 推进到春季第十二日并运行水灯会。
7. 保存、模拟崩溃、恢复。
8. 模拟离线五天并验证只补算三天。
9. 验证所有奖励、记忆、任务和项目事件无重复。

- [ ] **Step 2: 运行全部 Godot 测试**

Run:

```bash
bash tools/test.sh
```

Expected: 所有单元、集成、模拟和端到端测试通过，退出码 0。

- [ ] **Step 3: 运行 Memoria 契约测试**

在 `/home/nanzi/PY3/Memoria-tinglan-game-api` 中运行新增测试和相关回归测试。

- [ ] **Step 4: 导出 Linux 与 Windows**

Run:

```bash
bash tools/export.sh
```

Expected:

```text
build/linux/tides-of-tinglan.x86_64
build/windows/tides-of-tinglan.exe
```

- [ ] **Step 5: 运行 Linux 构建冒烟测试**

使用虚拟显示或无头兼容模式启动构建，确认进入主场景且无资源缺失。

- [ ] **Step 6: 逐项填写需求审计**

`docs/verification/requirements-audit.md` 为原始需求的每一项记录：

- 对应实现文件。
- 对应测试或构建证据。
- 实际运行命令及结果。
- 无法由自动化覆盖时的截图或人工检查路径。

任何缺少直接证据的要求都视为未完成并返回对应任务修补。

- [ ] **Step 7: 最终提交**

```bash
git add README.md export_presets.cfg tools tests docs/verification
git commit -m "release: verify Tides of Tinglan spring prototype"
```
