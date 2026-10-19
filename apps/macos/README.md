# Chaos Cat macOS native overlay

macOS 原生桌面浮层：用透明、置顶、跨空间的小型 `NSPanel` 承载小猫和道具特效，菜单栏贴纸图标提供调试与照片清理入口。

## 双击启动

在仓库根目录执行一次 `npm run build:macos`，会生成 `apps/macos/ChaosCat.app`。之后直接在 Finder 双击这个 App 即可启动，不需要打开终端；App 会自动启动内置的本地 bridge。系统已安装 Node.js 时可使用完整的编辑器联动功能。

这不是网页窗口，也不是一个铺满屏幕的大透明窗口。它避免拦截 IDE / 文档软件的普通点击；只有小猫窗口和控制条窗口会响应点击。

重要边界：

- 原生桌宠只负责小猫身体动作和短暂道具特效。
- 真实 `/shit/` 文本插入由 VS Code / Obsidian / Notion Web 集成执行。
- 原生桌宠不会再在桌面随机排布 `shit` 文字。

先在 repo 根目录启动 bridge：

```bash
npm run bridge
```

再运行：

```bash
cd apps/macos
swift run ChaosCatMac
```

构建需要 Swift 工具链、Python 3 和 Pillow，可用 `CHAOS_CAT_PYTHON` 指定 Python。`npm run package:macos` 会构建 App 并生成 `dist/Chaos-Cat-macOS-arm64.dmg`（架构取决于构建机器）。

App 只打包当前 Behavior 清单引用的动画、静态道具、菜单图片、App 图标和 bridge/web 运行文件。原工作区的历史 GIF、导出图和生成的编辑母版不进入安装包，也不提交到 Git；构建所需的当前素材均在仓库中。

左右动画只有在逐帧透明度、可见像素、尺寸、时序完全一致时才共用文件；播放时在原始分辨率反射像素，点击区域也使用同一画面。存在微小差异的 GIF 仍分别保留。没有重编码 GIF，也没有改变画质或帧率。

`tests/PackagedAnimationTests.swift` 用 macOS 原生解码器对比源码素材和打包素材的全部帧；通过 `CHAOS_CAT_BEHAVIOR_ASSETS=apps/macos/ChaosCat.app/Contents/Resources/Assets/Behavior` 可让行为回归测试直接使用安装包素材。构建在暂存目录验证完成后才替换已有 App，随后执行本地 ad-hoc 签名与校验。
