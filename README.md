# 听澜镇

《听澜镇》是一个使用 Godot 4 和 GDScript 制作的 2.5D 江南水乡生活模拟
RPG 春季样板。玩家作为新居民进入持续运转的小镇，与十名自主居民相处、
发布委托、参与听雨桥社区项目，并在春季第十二日参加上巳水灯会。

Godot 是世界状态的权威来源，负责时间、移动、需求、物品、任务、奖励和
完成条件。Memoria/FastAPI 负责人格、记忆、关系、社交意图与自然语言提示；
后端不可用时，游戏继续使用确定性的本地规则，并在连接恢复后同步待处理事件。

## 样板范围

- 一张连续室外镇区、正交等距镜头、键盘移动和点击寻路。
- 玩家住所、茶馆、杂货铺、诊所、工坊、书屋、社区中心和三处居民住宅。
- 十名居民的日程、需求、近场/离屏模拟，以及固定种子的十四日模拟。
- 旁听、申请加入、自由输入、情境动作和可展开会话记录。
- 居民委托、玩家结构化任务、隐藏数值的关系档案和背包。
- 听雨桥提案、收集、投票、施工、落成，以及上巳水灯会。
- 检查点、幂等事件日志、崩溃恢复和最多三个游戏日的离线补算。
- Linux 与 Windows 发布导出。

春季样板不包含战斗、自由建造、复杂农业或重经营系统。

## 环境

仓库自带固定版本工具链引导脚本。首次运行会下载并校验：

- Godot `4.7.1.stable`
- GUT `9.7.0`
- Linux 和 Windows 导出模板

需要 Bash、`curl`、`unzip`、`tar`、`sha256sum`、`sha512sum`、`flock` 和
基础 GNU 工具。运行测试不需要预先安装 Godot。

## 运行游戏

```bash
bash tools/bootstrap_godot.sh
.tools/godot/godot --path .
```

主要操作：

| 操作 | 按键 |
| --- | --- |
| 移动 | `WASD` 或方向键 |
| 点击寻路 | 鼠标左键 |
| 交互 | `E` 或回车 |
| 公告板 | `J` |
| 背包 | `I` |
| 关闭面板/暂停 | `Esc` |

## Memoria

游戏默认连接 `http://127.0.0.1:8000/api/v1`。Memoria 游戏接口位于独立
Memoria 分支 `feat/tinglan-game-api`，接口前缀为 `/api/v1/game`。

在 Memoria 仓库安装依赖并以 8000 端口启动：

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
uvicorn memoria.main:app --host 127.0.0.1 --port 8000
```

所有游戏接口需要有效的 Memoria Bearer token。启动游戏前设置：

```bash
export MEMORIA_ACCESS_TOKEN="<token>"
```

未启动服务、认证失败或网络暂时中断时，HUD 显示“可恢复错误”，本地模拟和
玩法仍可继续。连接恢复后，客户端按稳定事件 ID 同步待处理社会事件。

## 测试

运行全部 Godot 单元、集成、模拟和端到端测试：

```bash
bash tools/test.sh
```

运行单个测试文件或目录：

```bash
bash tools/test.sh tests/e2e/test_spring_playthrough.gd
bash tools/test.sh tests/simulation
```

十四日模拟使用固定种子 `20260716`，黄金摘要位于
`tests/fixtures/fourteen_day_seed_20260716.json`。

Memoria 契约和相关回归在 Memoria 工作树中运行：

```bash
PYTHONPATH=src pytest \
  tests/test_game_service.py \
  tests/test_game_api.py \
  tests/test_repository.py -q
```

## 视觉验收

生成桌面和小窗口视口截图：

```bash
.tools/godot/godot --path . --resolution 1280x720 \
  --script res://tests/visual/capture_visuals.gd -- --size 1280x720

.tools/godot/godot --path . --resolution 960x540 \
  --script res://tests/visual/capture_visuals.gd -- --size 960x540
```

截图写入被 Git 忽略的 `tests/visual/screenshots/`。检查项目、文件命名和人工
验收标准见 `tests/visual/README.md`。

## 导出

```bash
bash tools/export.sh
```

产物：

```text
build/linux/tides-of-tinglan.x86_64
build/windows/tides-of-tinglan.exe
```

Linux 构建可用以下命令做无图形冒烟：

```bash
build/linux/tides-of-tinglan.x86_64 --headless --quit-after 5
```

`build/` 被 Git 忽略，不进入源代码提交。

## 结构

```text
assets/             关键画面、居民头像和 UI 纹理
content/spring/     角色、地点、日程、任务、社区项目和节庆数据
scenes/             主场景、镇区、室内、角色和 UI 场景
scripts/core/       时间、随机数、任务、关系、项目、节庆和存档规则
scripts/services/   模拟、地点、对话、Memoria 客户端和待同步队列
scripts/ui/         HUD 与各交互面板
tests/              单元、集成、十四日模拟、端到端和视觉验收
tools/              固定工具链、测试和导出入口
```

完整设计、实施计划和逐项验收证据位于 `docs/`。
