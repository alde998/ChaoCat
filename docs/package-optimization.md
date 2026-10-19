# 软件包优化记录（2026-10-19）

| 项目 | 结果 |
|---|---:|
| App 优化前 | 1185.3 MB |
| App 优化后 | 213.5 MB |
| App 减少 | 81.99% |
| DMG 分发包 | 205.4 MB |
| ZIP 备用包 | 211.6 MB |
| 架构 | Apple Silicon / arm64 |

体积均按 1 MB = 1,000,000 字节统计。最小系统版本 macOS 13；编辑器联动仍使用已安装的 Node.js。

## 改动

- 清除主程序中已经被 BehaviorController 替代的旧绘制、动作、定时器与事件分支，main.swift 由 3032 行缩至 650 行；不再初始化隐藏的旧 GIF 播放器。
- 按资源清单打包，不再把原视频、历史动画、导出记录与编辑母版复制进 App。源素材保留在工作区。
- 将逐帧验证完全一致的左右 GIF 共用：68 个独立 GIF 减为 38 个，显示配置仍为 70 个。拖拽与蹲坐等存在像素差异的版本仍单独保存。
- 镜像在原分辨率以整数像素反射完成，无插值重采样；使用反射后的图像进行透明区域点击判定。
- 按文件/帧/方向共享解码缓存，减少显示变体重复解码；同一帧不重复要求重绘，淡入仍会正确刷新。
- 桥接事件去重历史限制为 512 条，日期解析器复用，避免长期增长和重复创建。
- Release 使用 -Osize，清除调试符号；清理照片直接采用用户原始 JPEG，像素与之前的 PNG 相同。
- 在暂存目录完成打包与本地签名校验后替换 App；提供可复现的 npm run package:macos 命令。

## 验证

通过：70 个动画配置、3640 帧 macOS 原生解码 RGBA 像素逐帧完全一致；帧时长、循环、尺寸、缩放、锚点、步距、动作标记时间完全相同。

通过：行为策略、12 项拖拽/控制器回归、菜单动作与立即清理、浮层点击与前台应用归属、左右追虫/扑击/翻滚、休息循环、输入触发概率和 7 项文档标记测试。通过本地签名校验、ZIP CRC 与每个文件字节比对、DMG 全卷校验。

真实 VS Code 全流程尚未完成最终复测：早期运行已执行插入/撤销/埋屎/垃圾堆/狂奔，后续输入断言仍使用旧 10.5 秒等待而当前追虫冷却为 25 秒，已修正。随后 Mac 锁定，编辑器无法取得焦点；保持前台焦点限制，未绕开。解锁后运行 node tests/run-vscode-host.mjs 完成验收。

## 文件

- apps/macos/ChaosCat.app
- dist/Chaos-Cat-macOS-arm64.dmg
- dist/Chaos-Cat-macOS-arm64.zip
- exports/package-optimization/native-animation-validation.json
- exports/package-optimization/assets.json
- exports/package-optimization/after.json
