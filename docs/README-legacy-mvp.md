# Chaos Cat 桌面小猫

当前动画已使用 2026-10-14 重命名的 12 段视频重新抠图、分段并导入透明 GIF。
新版规则、素材位置和测试结果见 [实现说明](docs/behavior-implementation-20261014.md)。

运行 `npm run build:macos`，然后打开 `apps/macos/ChaosCat.app`。应用自动启动本地桥接服务。VS Code 使用 `extensions/vscode` 扩展；状态栏为“小猫”。菜单提供追虫、跳垃圾堆、拉屎、休息和埋屎清理。

无损透明动画母版位于 `media/behavior-masters/`，运行用 GIF 位于 `apps/macos/Assets/Behavior/`。原视频保留。

---

以下为旧 MVP 原型说明，旧的跳箱、emoji 和 `//shit//` 描述不再用于新版 macOS 状态机；浏览器实验页仍是独立原型。

# Chaos Cat Desktop Pet MVP

一个“小猫桌面宠物”的可运行 MVP 骨架：先实现屏幕效果分层，猫本体使用固定 2D 占位素材。默认不修改真实代码/文档，所有 `shit`、便便图像、飞虫、字符踢乱优先作为覆盖层或 editor decoration 出现。

## What is included

- `apps/bridge`：本机事件中继服务，零依赖 Node.js HTTP + WebSocket。
- `apps/macos`：真正的 AppKit 桌面宠物 overlay。使用多个小型透明浮窗承载猫和短暂特效，避免一个全屏透明窗口挡住 IDE / 文档软件点击。
- `extensions/vscode`：VS Code extension，默认用 decorations 做视觉捣乱；可选插入/清理带标记注释。
- `extensions/obsidian`：Obsidian plugin 原型，用 DOM overlay 做文档视觉层；可选插入/清理 Markdown 注释。

## Run the local MVP

```bash
npm run bridge
```

Then open:

```text
http://127.0.0.1:44777
```

The Pet Web prototype exposes the six screen layers:

1. document layer
2. virtual text layer
3. dirty image layer
4. prop layer
5. cat layer
6. interaction layer

## macOS native floating overlay

Build the clickable app once:

```bash
npm run build:macos
```

Then double-click `apps/macos/ChaosCat.app` in Finder. The app bundles its animation assets and starts the local bridge automatically, so normal use does not require a terminal.

For development, the bridge can still be run manually:

```bash
cd apps/macos
swift run ChaosCatMac
```

This opens always-on-top macOS pet/effect windows above VS Code, Obsidian, Notion, or any document app. It intentionally avoids a full-screen transparent hit-test window, so normal clicks continue going to the app underneath.

If the bridge is not already running, the app now tries to launch it automatically from the repo root.

Important behavior change:

- The native pet no longer randomly draws `shit` text on the desktop.
- `PoopChaos` asks the active editor integration to insert real `//shit//` text.
- VS Code and Obsidian then decorate that real text with 💩/dirty visual effects.
- Cleanup removes the real generated `//shit//` text.
- If no editor integration is installed/connected, the native pet falls back to image-only 💩 overlays around the active work window.
- The cat has autonomous behavior: it roams around the active work window and periodically picks calm / bug chase / box dive / poop chaos.

## VS Code extension

Local install path:

```text
~/.vscode/extensions/chaos-cat-local-dev-0.1.0
```

After copying the extension, restart VS Code or run:

```text
Command Palette → Developer: Reload Window
```

When loaded, the VS Code status bar shows `Chaos Cat`.

Open `extensions/vscode` in VS Code and run the extension host, or symlink/copy it into your local extension development flow. Commands:

- `Chaos Cat: Trigger Poop Chaos`
- `Chaos Cat: Trigger Box Dive`
- `Chaos Cat: Trigger Bug Chase`
- `Chaos Cat: Calm`
- `Chaos Cat: Clear Visual Effects`
- `Chaos Cat: Toggle Real Comment Mode`
- `Chaos Cat: Insert Cat Shit Comment`
- `Chaos Cat: Clean Cat Shit Comments`

Poop chaos now inserts real `//shit//` text by default, then decorates the inserted ranges with 💩 visual effects. Cleanup removes generated `//shit//` chunks.

## Obsidian plugin

Copy `extensions/obsidian` into an Obsidian vault under:

```text
.obsidian/plugins/chaos-cat/
```

Then enable the plugin in Obsidian community plugin settings. Commands mirror the MVP states and default to overlay-only visual effects.

## Safety defaults

- No hidden install.
- No remote control.
- No real document mutation except the explicit Notion/VS Code mutation actions the user triggers.
- All generated real comments are marked and cleanable.
- Visual effects can always be cleared.
