# 拖拽动画占位与快速拖拽埋屎

新状态机已预留以下槽位，路径为 `apps/macos/Assets/Behavior/`。当前均取自原来实际使用的 carried 素材，保留原像素、透明度和每帧时长，左向文件仅镜像。

| 槽位（各有 left / right） | 当前临时素材 | 播放规则 |
| --- | --- | --- |
| `drag-enter-*.gif` | `cat-carried.gif` | 拖动开始时提起，单次 |
| `drag-*.gif` | `cat-carried-hold.gif` | 提起后悬空保持，持续到松手 |
| `drag-exit-*.gif` | `cat-carried-return.gif` | 松手放下，单次 |

后续视频按提起、悬空保持、放下切分，替换以上文件及 `catalog.json` 对应条目的 `frames`、`duration`、`fps`、`frameDurations`、`width/height`、`footX/footY`、`scale` 和来源信息即可。`footX/footY` 是原始画布内的脚底锚点，`scale` 仅控制屏幕显示比例。`frameDurations` 单位为秒，可省略以使用固定帧率。提起和放下的 `loop` 为 false，悬空保持为 true。收到正式素材后应移除临时 `placeholder` 标记并更新生成脚本。

轻拖只移动小猫；一次拖拽累计移动至少 24 屏幕点、峰值速度达到 900 屏幕点/秒，松手放下后触发埋屎。速度使用鼠标事件时间戳计算，不受 GIF 解码延迟影响。每次按下清空手势统计，避免一次快速拖拽污染后续轻拖。

快速拖拽期间保留原编辑器和文档；松手后查询该文档的真实 `/shit/`，走到对应位置，在埋屎动画的消失帧删除该标记。没有可见标记时回到走路。打断拉屎时保留受惊狂奔，快拖的清理请求排在狂奔后执行。拖出垃圾堆时先恢复垃圾堆占位；重新抓起会取消上一次放下后的待执行动作。

回归测试：`bash tests/run-drag-tests.sh`，结果保存到 `docs/drag-behavior-validation.json`。使用真实原生视图回调、动画时钟和控制器，编辑器响应为测试夹具；真实 VS Code 协议另由 `tests/run-vscode-host.mjs` 验证。
