> 2026-10-14 更新：新视频的抠图、帧数、源文件映射和验证见 `docs/video-replacement-20261014.md` 及 `Assets/imported-videos/runtime-segments.json`。下方尺寸／时长数据为此前素材版本。跳箱与拖拽素材暂未提供对应新视频。

# Chaos Cat 动画切片目录

本文档对应 macOS 桌面宠物当前使用的动画资源。所有切片使用 `156×156` GIF 画布，动画本身是否循环，以及桌面浮层是否同步移动，分别由“循环”和“窗口位移”说明。

## 切片列表

| 切片名 | 文件 | 播放状态 | 播放时机 | 循环 | 窗口位移 |
| --- | --- | --- | --- | --- | --- |
| `idle` | `cat-idle.gif` | 正面坐姿，安静待机 | 启动后默认状态；动作结束后回到这里 | 是 | 否 |
| `walk_left` | `cat-walk-left.gif` | 向左闲逛 | 猫在桌面工作区内自主漫步，或移动到目标点 | 是 | 是 |
| `walk_right` | `cat-walk-right.gif` | 向右闲逛 | 猫在桌面工作区内自主漫步，或移动到目标点 | 是 | 是 |
| `run_left` | `cat-run-left.gif` | 向左快速奔跑（备用） | 作为运行时初始方向资源和快速移动备用片段；当前自主闲逛主要使用 `walk_left` | 是 | 是 |
| `run_right` | `cat-run-right.gif` | 向右快速奔跑（备用） | 作为运行时初始方向资源和快速移动备用片段；当前自主闲逛主要使用 `walk_right` | 是 | 是 |
| `poop` | `cat-poop.gif` | 蹲下拉屎 | 收到 `poop.started`，开始一轮便便动作 | 否 | 否 |
| `poop_transition` | `cat-poop-transition.gif` | 拉下一坨的短过渡 | 同一轮便便中，上一坨完成后切到下一坨 | 否 | 否 |
| `frenzy_left` | `cat-frenzy-run-left.gif` | 狂暴向左奔跑 | 拉屎过程中被点击或触发打断，猫向左逃跑 | 是 | 是 |
| `frenzy_right` | `cat-frenzy-run-right.gif` | 狂暴向右奔跑 | 拉屎过程中被点击或触发打断，猫向右逃跑 | 是 | 是 |
| `box_dive` | `cat-box-dive.gif` | 向箱子跳入 | 触发跳箱动作，从行走状态进入箱子 | 否 | 是 |
| `box_jump` | `cat-box-jump.gif` | 跳箱接触/落入瞬间 | `box_dive` 结束、猫接触箱子时播放的短衔接片段 | 否 | 否 |
| `box_inside` | `cat-box-inside.gif` | 躲在箱中 | 跳入完成后保持，直到箱子动作结束或被拖拽 | 是 | 否 |
| `chase_start_left` | `cat-chase-start-left.gif` | 向左追虫启动 | 追虫开始，猫先警觉并准备向左 | 否 | 否 |
| `chase_start_right` | `cat-chase-start-right.gif` | 向右追虫启动 | 追虫开始，猫先警觉并准备向右 | 否 | 否 |
| `chase_start_left_reverse` | `cat-chase-start-left-reverse.gif` | 向左启动的逆放/回转 | 追虫中需要从左侧转回另一朝向时 | 否 | 否 |
| `chase_start_right_reverse` | `cat-chase-start-right-reverse.gif` | 向右启动的逆放/回转 | 追虫中需要从右侧转回另一朝向时 | 否 | 否 |
| `chase_left` | `cat-chase-left.gif` | 向左追虫 | 完成左向启动后持续追逐虫子 | 是 | 是 |
| `chase_right` | `cat-chase-right.gif` | 向右追虫 | 完成右向启动后持续追逐虫子 | 是 | 是 |
| `chase_left_alt` | `cat-chase-left-alt.gif` | 向左追虫变化段 | 左向追逐循环中，用于改变步态，避免重复感 | 是 | 是 |
| `chase_right_alt` | `cat-chase-right-alt.gif` | 向右追虫变化段 | 右向追逐循环中，用于改变步态，避免重复感 | 是 | 是 |
| `pounce_left` | `cat-pounce-left.gif` | 向左扑虫 | 追逐过程中接近虫子，执行扑击 | 否 | 是 |
| `pounce_right` | `cat-pounce-right.gif` | 向右扑虫 | 追逐过程中接近虫子，执行扑击 | 否 | 是 |
| `scratch_move_left` | `cat-scratch-move-left.gif` | 向左移动并准备刨沙 | 清理便便时，猫移动到下一处目标 | 否 | 是 |
| `scratch_move_right` | `cat-scratch-move-right.gif` | 向右移动并准备刨沙 | 清理便便时，猫移动到下一处目标 | 否 | 是 |
| `scratch_left` | `cat-scratch-left.gif` | 向左刨沙/埋屎 | 猫到达便便位置后执行清理 | 是 | 否 |
| `scratch_right` | `cat-scratch-right.gif` | 向右刨沙/埋屎 | 猫到达便便位置后执行清理 | 是 | 否 |
| `carried_hold` | `cat-carried-hold.gif` | 被拖拽悬空 | 用户按住猫并拖动时持续播放 | 是 | 否 |
| `carried_return` | `cat-carried-return.gif` | 松手落地 | 用户松开鼠标后，从悬空姿态回到坐姿 | 否 | 否 |
| `lick_paw` | `cat-lick-paw.gif` | 舔爪 | 点击猫触发的短暂反馈，或自主休息动作 | 否 | 否 |
| `sleep` | `cat-sleep.gif` | 躺下休息并起身 | 自主行为进入休息时播放；结束后回到 `idle` | 否 | 否 |

## 常用播放链路

### 普通待机与移动

`idle → walk_left / walk_right → idle`

猫在当前工作区内自主移动时，GIF 循环播放，同时 macOS 浮层窗口同步移动。到达目标点后切回 `idle`。

### 便便动作

`idle / walk → poop → poop_transition → poop → …`

便便事件开始时播放 `poop`。每增加一处便便，使用一次 `poop_transition` 作为短过渡，再回到 `poop`。动作结束后回到 `idle`。若猫被点击或触发打断，则转入 `frenzy_left` 或 `frenzy_right`。

### 跳箱动作

`idle / walk → box_dive → box_inside`

`box_dive` 负责接触箱子和跳入过程，窗口会同步向箱子位置移动；进入后用 `box_inside` 循环保持。释放或结束后接 `carried_return`，再回到 `idle`。

### 追虫动作

`chase_start_left / chase_start_right → chase_left / chase_right`

追虫先播放启动片段，再进入对应方向的追逐循环。追逐中可在基础片段和 `*_alt` 变化片段之间切换，也可插入 `pounce_left / pounce_right`。方向改变时使用对应的 `*_reverse` 片段衔接。

### 清理便便

`scratch_move_left / scratch_move_right → scratch_left / scratch_right → idle`

猫先移动到目标位置，再原地循环刨沙。目标清理完成后停止刨沙并回到 `idle`。

### 拖拽与休息

- 拖拽：`carried_hold → carried_return → idle`
- 点击反馈：`lick_paw → idle`
- 自主休息：`sleep → idle`

## 资源命名规则

- `left` / `right`：猫的朝向和移动方向。
- `start`：进入追虫状态的启动片段。
- `reverse`：启动片段逆向播放，用于方向转换。
- `alt`：同一动作的变化循环，减少连续播放的重复感。
- `move`：动作中包含桌面位置移动；播放时需要同时移动浮层窗口。
- `hold`：保持状态，通常循环播放直到外部事件结束。

注：程序会优先使用追虫和扑击动作对应的“大尺寸切片”文件映射，以保持追虫时猫头尺寸一致；文件名和状态名仍按上表记录。
