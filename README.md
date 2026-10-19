# Chaos Cat 桌面小猫

macOS 桌宠负责动画和屏幕移动；VS Code 扩展负责真实文档坐标、输入事件以及 `/shit/`、`/rubbish/` 的插入和删除。二者通过本机 `127.0.0.1:44777` 桥接联动。

## 当前需求

- 默认走路，按步距移动；左右转向随机使用内转或外转。
- 三种捣乱：输入追虫、跳垃圾堆、三轮拉屎。埋屎与真实 `/shit/` 删除同步。
- 垃圾堆插入临时 `/rubbish/` 占位挤开文字；小猫走近并面向垃圾堆，发现→冲刺→跳入→摇尾巴。点击或拖拽退出，只移除自身占位，保留期间的其他编辑。
- 三种休息随机播放：蹲坐甩尾 60%、蹲坐后舔爪 28%、睡觉 12%。坐下和躺下只播一次；蹲坐往返循环，舔爪可重复，睡眠呼吸循环 3–5 次，然后起身。
- 拖拽使用正式视频切分的提起、悬空保持和放下动作；快速拖拽松手触发埋屎，轻拖只移动。放下后接蹲坐起身，再进入行走。
- 菜单“调试动作”立即切换到拉屎、跳垃圾堆、追虫或休息；点击监狱鱼眼照片按钮取消当前动作，立即清除所有小猫屎标记和桌面效果。
- 当前透明 GIF 保留原始尺寸和逐帧时序；打包仅复用逐帧验证完全相同的镜像动画，不降低动画质量。

完整规则见 [行为规则](docs/behavior-rules-20261014.md)，素材和实现见 [实现说明](docs/behavior-implementation-20261014.md)。

## 运行

需要 macOS 13 或更新版本、Swift 5.9 或更新工具链、Node.js、Python 3 和 Pillow。可用 `CHAOS_CAT_PYTHON` 指定安装了 Pillow 的 Python。

```sh
git clone https://github.com/alde998/ChaoCat.git
cd ChaoCat
npm run build:macos
open apps/macos/ChaosCat.app
```

App 自动启动桥接。通过分发 DMG 安装时，若已安装正式版 VS Code，小猫首次启动会自动为当前用户安装内置扩展；若之后才安装 VS Code，可在小猫菜单中选择“安装 VS Code 插件”。扩展兼容 VS Code 1.79 及以上。开发环境也可手动构建并安装：

```sh
python3 scripts/package_vscode.py
code --install-extension dist/chaos-cat-0.1.7.vsix --force
```

标准安装目录为 `~/.vscode/extensions/local-dev.chaos-cat-0.1.7`。更新扩展后执行 **Developer: Restart Extension Host**，保留当前编辑缓冲区。

打开文本文件并聚焦编辑器后，状态栏应显示 **小猫 · 已联动**。点击状态栏或执行 **Chaos Cat: 查看联动诊断** 可查看桥接、原生桌宠、窗口身份和运行版本。只显示桌宠动画或有桥接心跳不等于文档联动成功。

命令面板支持 **Chaos Cat: 跳垃圾堆**、**拉屎**、**立即清理所有屎**、**调试埋屎动画**、**Trigger Bug Chase** 和 **Calm**。输入文字也会触发追虫。

`/shit/` 直接插入当前文档正文，文字可见、可选择、可搜索、可复制，旁边显示小图标。每次插入支持独立撤销，保存时随代码写入文件；埋屎到达对应位置后删除这段正文。

菜单“清理”广播给已连接的编辑器，一次清除当前文档和所有已记录受影响文档（包括关闭的标签页）中的 `/shit/`；保留周围编辑，不保存其他未保存内容，不搜索无关文件。它同时取消未完成的排便和延迟插入。快速拖拽和“调试埋屎动画”仍逐个走到标记处埋屎。

## 验证

```sh
node --test tests/markers.test.cjs
bash tests/run-drag-tests.sh
python3 tests/behavior-assets.py
node tests/run-vscode-host.mjs
```

最后一项会打开隔离的 VS Code 扩展测试宿主、原生桌宠和本地测试桥接，只编辑临时 JavaScript 文件；验证真实输入、三次标记插入、单次撤销与重做、保存后的文件内容、埋屎删除、垃圾堆恢复、受惊狂奔，以及跨文档立即清理和延迟请求取消。用 `CHAOS_CAT_CODE_APP` 指定其他已安装的 VS Code 路径。结果为 `docs/vscode-host-validation.json`。

`tests/behavior-integration.mjs` 是内存适配器测试，不能替代真实宿主验证。Obsidian / Notion 适配器仍需在对应宿主安装后验收。浏览器实验页和 [旧 MVP 文档](docs/README-legacy-mvp.md) 仅供历史参考。

## 打包与素材

`npm run package:macos` 构建 App，并生成当前机器架构的 `.pkg` 安装器和 `.dmg` 拖拽镜像。安装包自带 Node.js 与 VS Code 扩展；详细过程见 [macOS 构建说明](apps/macos/README.md)，原始动画的体积和画质校验记录见 [软件包优化记录](docs/package-optimization.md)。

当前公开 DMG 使用本地 ad-hoc 签名，尚未经过 Apple 公证。另一台 Mac 首次打开时若提示无法验证开发者，可按 [Apple 的“仍要打开”步骤](https://support.apple.com/zh-cn/102445)为单个 App 放行；若提示软件损坏或会损坏电脑，应停止安装。要让下载后正常双击打开，需要 Developer ID Application 证书与 Apple 公证。

仓库包含当前全部动画、静态图片、图标源图、测试所需参考素材和构建脚本。安装包、构建缓存、历史素材副本、生成的 APNG 编辑母版与临时导出不提交；这些文件仍保留在原工作区。构建当前 App 无需重新抠图或生成动画。`scripts/` 中的历史素材处理工具可能需要额外的原视频、逐帧图片或编辑母版，不属于常规构建步骤。
