import AppKit
import ApplicationServices
import Foundation

private let bridgeBase = "http://127.0.0.1:" + (ProcessInfo.processInfo.environment["CHAOS_CAT_PORT"] ?? "44777")
private let bridgeURL = URL(string: bridgeBase + "/api/events")!

private func behaviorCatalogURL() -> URL? {
  let manager = FileManager.default
  let cwd = URL(fileURLWithPath: manager.currentDirectoryPath, isDirectory: true)
  // A packaged app must be self-contained; do not silently load source assets.
  if Bundle.main.bundleURL.pathExtension == "app" {
    let url = Bundle.main.resourceURL?.appendingPathComponent("Assets/Behavior/catalog.json")
    return url.flatMap { manager.fileExists(atPath: $0.path) ? $0 : nil }
  }
  return ["apps/macos/Assets", "Assets", "../Assets"].map {
    cwd.appendingPathComponent($0).appendingPathComponent("Behavior/catalog.json").standardizedFileURL
  }.first { manager.fileExists(atPath: $0.path) }
}

struct EditorViewport {
  let uri: String
  let visibleStartLine: Int
  let visibleEndLine: Int
  let lineCount: Int
  let fontSize: CGFloat
  let lineHeight: CGFloat
}

final class ChaosCatApp: NSObject {
  private var rules: BehaviorController?
  private var bridgeFetchPending = false
  private let launchedAt = Date()
  private var seenEventIDs = Set<String>()
  private var seenEventOrder: [String] = []
  private var pollTimer: Timer?
  private var bridgeProcess: Process?
  private var editorViewports: [String: EditorViewport] = [:]
  private let dateFormatter = ISO8601DateFormatter()
  private let fractionalDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  func show() {
    ensureBridgeRunning()
    if let catalog=behaviorCatalogURL() {
      do {
        let library=try BehaviorLibrary(directory:catalog.deletingLastPathComponent())
        rules=BehaviorController(library:library,screen:NSScreen.main ?? NSScreen.screens[0],
          emit:{[weak self] type,payload in self?.postEvent(type:type,payload:payload)},
          resolve:{[weak self] anchor in self?.pointForEditorAnchor(anchor)},
          editorRect:{[weak self] in
            if ProcessInfo.processInfo.environment["CHAOS_CAT_TEST"] == "1" { return NSScreen.main?.visibleFrame ?? .zero }
            return self?.editorContentRect() ?? .zero
          },
          workArea:{[weak self] in
            if ProcessInfo.processInfo.environment["CHAOS_CAT_TEST"] == "1" { return NSScreen.main?.visibleFrame ?? .zero }
            return self?.frontmostWorkWindowFrame() ?? .zero
          },
          workIdentity:{[weak self] in
            if ProcessInfo.processInfo.environment["CHAOS_CAT_TEST"] == "1" { return "test-window" }
            return self?.frontmostWorkWindowIdentity() ?? "desktop"
          },
          isEditorForeground:{[weak self] source in
            ProcessInfo.processInfo.environment["CHAOS_CAT_TEST"] == "1" || (self?.isEditorForeground(source) ?? false)
          },
          isEditorContext:{[weak self] in
            // Browsers are editors only while an active adapter owns the
            // page; ordinary browser/app windows may spawn ambient insects.
            (self?.isEditorForeground("vscode-extension") ?? false)
              || (self?.isEditorForeground("obsidian-plugin") ?? false)
          },
          bugChanceRoll:{
            // UI integration fixtures need a deterministic successful roll;
            // trigger probability/throttling are covered by controller tests.
            ProcessInfo.processInfo.environment["CHAOS_CAT_TEST"] == "1" ? 0 : Double.random(in:0..<1)
          })
        rules?.start()
      } catch { NSLog("Behavior assets could not load: %@",error.localizedDescription) }
    }
    guard rules != nil else {
      let alert=NSAlert();alert.messageText="动画素材未完整导入";alert.informativeText="请重新构建 Chaos Cat，缺少 Behavior/catalog.json 或素材清单无法读取。";alert.runModal();return
    }
    startPollingBridge()
  }

  func shutdown() {
    pollTimer?.invalidate()
    pollTimer = nil
    rules?.shutdown()
  }

  @objc func calm() { rules?.performDebugAction("calm") }
  @objc func poopChaos() { rules?.performDebugAction("poopChaos") }
  @objc func boxDive() { rules?.performDebugAction("rubbish") }
  @objc func bugChase() { rules?.performDebugAction("bugChase") }
  @objc func clearEffects() { rules?.clearAll() }

  private func screenFrame() -> CGRect {
    NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
  }

  private func frontmostUserWindow() -> (frame: CGRect, pid: pid_t, id: Int)? {
    guard
      let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return nil }

    let ownPID = ProcessInfo.processInfo.processIdentifier
    let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var candidates: [(frame: CGRect, pid: pid_t, id: Int)] = []
    for info in windowList {
      guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
      let layer = info[kCGWindowLayer as String] as? Int ?? 1
      let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
      guard ownerPID != ownPID, layer == 0, alpha > 0 else { continue }
      guard
        let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
        let x = boundsDict["X"] as? CGFloat,
        let y = boundsDict["Y"] as? CGFloat,
        let width = boundsDict["Width"] as? CGFloat,
        let height = boundsDict["Height"] as? CGFloat,
        width > 240,
        height > 180
      else { continue }

      let screen = NSScreen.main?.frame ?? screenFrame()
      let convertedY = screen.maxY - y - height
      let id = info[kCGWindowNumber as String] as? Int ?? 0
      candidates.append((CGRect(x: x, y: convertedY, width: width, height: height), ownerPID, id))
    }

    if let foregroundPID,foregroundPID != ownPID,
       let window=candidates.first(where:{$0.pid == foregroundPID}) { return window }
    return candidates.first
  }

  private func frontmostWindowFrame() -> CGRect {
    frontmostUserWindow()?.frame ?? screenFrame()
  }

  private func frontmostWorkWindowFrame() -> CGRect {
    let frame=frontmostWindowFrame()
    return NSScreen.screens.map{frame.intersection($0.visibleFrame)}
      .filter{!$0.isNull}.max(by:{$0.width*$0.height < $1.width*$1.height}) ?? frame
  }

  private func frontmostWorkWindowIdentity() -> String {
    guard let window=frontmostUserWindow() else { return "desktop" }
    return "\(window.pid):\(window.id)"
  }

  private func isEditorForeground(_ source: String) -> Bool {
    guard let window=frontmostUserWindow(),
          let bundle=NSRunningApplication(processIdentifier:window.pid)?.bundleIdentifier?.lowercased() else { return false }
    switch source {
    case "vscode-extension":
      return bundle.contains("vscode") || bundle.contains("vscodium")
    case "obsidian-plugin":
      return bundle.contains("obsidian")
    case "notion-web-extension":
      return bundle.contains("chrome") || bundle.contains("edge") || bundle.contains("safari")
        || bundle.contains("firefox") || bundle.contains("notion")
    default:
      return false
    }
  }

  private func axFrame(for element: AXUIElement, preferContent: Bool = false) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
          let position = axPoint(positionValue),
          let size = axSize(sizeValue),
          size.width > 240,
          size.height > 180 else {
      return nil
    }

    let screen = NSScreen.main?.frame ?? screenFrame()
    let frame = CGRect(
      x: position.x,
      y: screen.maxY - position.y - size.height,
      width: size.width,
      height: size.height
    )

    if preferContent {
      return CGRect(
        x: frame.minX + 72,
        y: frame.minY + 38,
        width: max(240, frame.width - 144),
        height: max(180, frame.height - 114)
      )
    }

    return frame
  }

  private func axPoint(_ value: CFTypeRef?) -> CGPoint? {
    guard let rawValue = value, CFGetTypeID(rawValue) == AXValueGetTypeID() else { return nil }
    let value = rawValue as! AXValue
    guard AXValueGetType(value) == .cgPoint else { return nil }
    var point = CGPoint.zero
    AXValueGetValue(value, .cgPoint, &point)
    return point
  }

  private func axSize(_ value: CFTypeRef?) -> CGSize? {
    guard let rawValue = value, CFGetTypeID(rawValue) == AXValueGetTypeID() else { return nil }
    let value = rawValue as! AXValue
    guard AXValueGetType(value) == .cgSize else { return nil }
    var size = CGSize.zero
    AXValueGetValue(value, .cgSize, &size)
    return size
  }

  private func axStringAttribute(_ attribute: String, for element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
  }

  private func axChildren(of element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let rawValue = value,
          CFGetTypeID(rawValue) == CFArrayGetTypeID() else {
      return []
    }

    return (rawValue as! NSArray).compactMap { item in
      guard let rawChild = item as CFTypeRef?,
            CFGetTypeID(rawChild) == AXUIElementGetTypeID() else {
        return nil
      }
      return (rawChild as! AXUIElement)
    }
  }

  private func focusedAXWindow() -> AXUIElement? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
          let rawValue = value,
          CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
      return nil
    }
    return (rawValue as! AXUIElement)
  }

  private func axRect(_ value: CFTypeRef?) -> CGRect? {
    guard let rawValue = value, CFGetTypeID(rawValue) == AXValueGetTypeID() else { return nil }
    let value = rawValue as! AXValue
    guard AXValueGetType(value) == .cgRect else { return nil }
    var rect = CGRect.zero
    AXValueGetValue(value, .cgRect, &rect)
    return rect
  }

  private func boundsForTextRange(offset: Int, length: Int) -> CGRect? {
    let screen = NSScreen.main?.frame ?? screenFrame()
    guard let textElement = detectedEditorTextElement(in: screen) else { return nil }
    var range = CFRange(location: max(0, offset), length: max(0, length))
    guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
    var boundsValue: CFTypeRef?
    let result = AXUIElementCopyParameterizedAttributeValue(
      textElement,
      kAXBoundsForRangeParameterizedAttribute as CFString,
      rangeValue,
      &boundsValue
    )
    guard result == .success else { return nil }
    return axRect(boundsValue)
  }

  private func detectedEditorCandidate(in window: CGRect) -> (element: AXUIElement, frame: CGRect)? {
    guard let focusedWindow = focusedAXWindow() else { return nil }

    var bestCandidate: (element: AXUIElement, frame: CGRect)?
    var bestScore = CGFloat.leastNormalMagnitude
    var visited = 0

    func visit(_ element: AXUIElement, depth: Int) {
      guard depth <= 8, visited < 900 else { return }
      visited += 1

      let role = axStringAttribute(kAXRoleAttribute, for: element) ?? ""
      let description = axStringAttribute(kAXDescriptionAttribute, for: element) ?? ""
      let title = axStringAttribute(kAXTitleAttribute, for: element) ?? ""

      if let frame = axFrame(for: element) {
        let intersection = frame.intersection(window)
        let mostlyInsideWindow = !intersection.isNull && intersection.width > 220 && intersection.height > 160
        let notWholeWindow = frame.width < window.width * 0.96 || frame.height < window.height * 0.90
        let startsPastActivityBar = frame.minX > window.minX + 70
        let notMenuBand = frame.maxY < window.maxY - 45
        let plausibleRole = role.contains("Text") || role.contains("Scroll") || role.contains("Group") || role.contains("Web")
        let hints = "\(role) \(description) \(title)"
        let textualHint = hints.localizedCaseInsensitiveContains("editor")
          || hints.localizedCaseInsensitiveContains("text")
          || hints.localizedCaseInsensitiveContains("monaco")

        if mostlyInsideWindow && notWholeWindow && startsPastActivityBar && notMenuBand && plausibleRole {
          var score = intersection.width * intersection.height
          if role.contains("Text") { score *= 2.4 }
          if role.contains("Scroll") { score *= 1.8 }
          if textualHint { score *= 1.7 }
          // When VS Code's left sidebar is expanded, the editor surface is the
          // right-most large scroll/text region, not the explorer/sidebar.
          score += max(0, frame.minX - window.minX) * 220
          if frame.minX < window.minX + 150 { score *= 0.35 }
          if frame.width < 360 { score *= 0.35 }

          if score > bestScore {
            bestScore = score
            bestCandidate = (element, intersection)
          }
        }
      }

      for child in axChildren(of: element) {
        visit(child, depth: depth + 1)
      }
    }

    visit(focusedWindow, depth: 0)

    return bestCandidate
  }

  private func detectedEditorTextElement(in window: CGRect) -> AXUIElement? {
    detectedEditorCandidate(in: window)?.element
  }

  private func detectedEditorContentRect(in window: CGRect) -> CGRect? {
    guard var frame = detectedEditorCandidate(in: window)?.frame else { return nil }
    let gutterInset = CGFloat(Double(ProcessInfo.processInfo.environment["CHAOS_CAT_EDITOR_GUTTER_INSET"] ?? "72") ?? 72)
    let topInset = CGFloat(Double(ProcessInfo.processInfo.environment["CHAOS_CAT_DYNAMIC_EDITOR_TOP_INSET"] ?? "18") ?? 18)
    let bottomInset = CGFloat(Double(ProcessInfo.processInfo.environment["CHAOS_CAT_DYNAMIC_EDITOR_BOTTOM_INSET"] ?? "14") ?? 14)
    frame.origin.x += gutterInset
    frame.size.width = max(240, frame.width - gutterInset - 18)
    frame.origin.y += bottomInset
    frame.size.height = max(180, frame.height - topInset - bottomInset)
    return frame
  }

  private func pointForEditorAnchor(_ anchor: [String: Any]?) -> CGPoint? {
    guard let anchor else { return nil }
    if let x=anchor["screenX"] as? Double,let y=anchor["screenY"] as? Double {
      let primaryTop=NSScreen.screens.first?.frame.maxY ?? 0
      return CGPoint(x:x,y:primaryTop-y)
    }
    if let offset=anchor["offset"] as? Int,let rect=boundsForTextRange(offset:offset,length:1),rect.width>0,rect.height>0 {
      let top=NSScreen.screens.first?.frame.maxY ?? 0
      return CGPoint(x:rect.midX,y:top-rect.maxY)
    }
    let editorRect = editorContentRect()
    guard editorRect.width > 240, editorRect.height > 180 else { return nil }

    let visualColumn = CGFloat(anchor["visualColumn"] as? Int ?? anchor["character"] as? Int ?? 0)
    let line = CGFloat(anchor["line"] as? Int ?? 0)
    guard let viewport = currentViewport(for: anchor) else { return nil }
    let visibleStart = CGFloat(viewport.visibleStartLine)
    let visibleEnd = CGFloat(viewport.visibleEndLine)
    guard line >= visibleStart - 0.5, line <= visibleEnd + 0.5 else { return nil }

    let fontSize = CGFloat(anchor["fontSize"] as? Double ?? Double(viewport.fontSize))
    let lineHeight = CGFloat(anchor["lineHeight"] as? Double ?? Double(viewport.lineHeight))
    let charWidth = fontSize * 0.62
    let yPadding = CGFloat(Double(ProcessInfo.processInfo.environment["CHAOS_CAT_EDITOR_TEXT_TOP_PAD"] ?? "8") ?? 8)
    let x = min(editorRect.maxX - 36, max(editorRect.minX + 2, editorRect.minX + visualColumn * charWidth))
    let y = editorRect.maxY - yPadding - (line - visibleStart) * lineHeight - lineHeight / 2
    return CGPoint(x: x, y: y)
  }

  private func currentViewport(for anchor: [String: Any]) -> EditorViewport? {
    if let uri = anchor["uri"] as? String, let viewport = editorViewports[uri] {
      return viewport
    }

    let lineCount = anchor["lineCount"] as? Int ?? 0
    let line = anchor["line"] as? Int ?? 0
    let start = anchor["visibleStartLine"] as? Int ?? max(0, line - 20)
    let end = anchor["visibleEndLine"] as? Int ?? max(start, min(max(0, lineCount - 1), line + 20))
    return EditorViewport(
      uri: anchor["uri"] as? String ?? "",
      visibleStartLine: start,
      visibleEndLine: end,
      lineCount: lineCount,
      fontSize: CGFloat(anchor["fontSize"] as? Double ?? 14),
      lineHeight: CGFloat(anchor["lineHeight"] as? Double ?? 21)
    )
  }

  private func editorContentRect() -> CGRect {
    let window = frontmostWindowFrame()
    if let detected = detectedEditorContentRect(in: window) {
      return detected
    }
    // This intentionally uses the actual foreground window frame instead of AX
    // focused UI bounds. In VS Code the focused AX element can be the workbench
    // container or an off-left accessibility proxy, which makes desktop effects
    // drift into the activity/sidebar/menu area. These insets target the visible
    // editor text surface: right of line numbers/gutter and below menu/tab bars.
    let leftInset = CGFloat(Double(ProcessInfo.processInfo.environment["CHAOS_CAT_EDITOR_LEFT_INSET"] ?? "132") ?? 132)
    let topInset = CGFloat(Double(ProcessInfo.processInfo.environment["CHAOS_CAT_EDITOR_TOP_INSET"] ?? "148") ?? 148)
    let rightInset = CGFloat(Double(ProcessInfo.processInfo.environment["CHAOS_CAT_EDITOR_RIGHT_INSET"] ?? "28") ?? 28)
    let bottomInset = CGFloat(Double(ProcessInfo.processInfo.environment["CHAOS_CAT_EDITOR_BOTTOM_INSET"] ?? "66") ?? 66)
    return CGRect(
      x: window.minX + leftInset,
      y: window.minY + bottomInset,
      width: max(240, window.width - leftInset - rightInset),
      height: max(180, window.height - topInset - bottomInset)
    )
  }

  private func startPollingBridge() {
    let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
      self?.fetchBridgeEvents()
    }
    RunLoop.main.add(timer, forMode: .common)
    pollTimer = timer
    fetchBridgeEvents()
  }

  private func ensureBridgeRunning() {
    checkBridgeReachable { [weak self] reachable in
      guard let self else { return }
      if reachable { return }
      self.launchBridgeIfNeeded()
    }
  }

  private func checkBridgeReachable(completion: @escaping (Bool) -> Void) {
    var request = URLRequest(url: URL(string: bridgeBase + "/api/health")!)
    request.timeoutInterval = 0.6
    URLSession.shared.dataTask(with: request) { data, response, _ in
      let ok = (response as? HTTPURLResponse)?.statusCode == 200 || data != nil
      DispatchQueue.main.async {
        completion(ok)
      }
    }.resume()
  }

  private func launchBridgeIfNeeded() {
    guard bridgeProcess?.isRunning != true else { return }
    guard let bridgeRoot = bridgeRootURL(), let nodeURL = nodeExecutableURL() else {
      NSLog("Chaos Cat could not start its local bridge: Node.js was not found")
      return
    }

    let process = Process()
    process.currentDirectoryURL = bridgeRoot
    process.executableURL = nodeURL
    process.arguments = [bridgeRoot.appendingPathComponent("apps/bridge/server.mjs").path]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    process.terminationHandler = { [weak self] _ in
      DispatchQueue.main.async {
        self?.bridgeProcess = nil
      }
    }

    do {
      try process.run()
      bridgeProcess = process
    } catch {
      NSLog("Chaos Cat failed to launch bridge: \(error.localizedDescription)")
    }
  }

  private func bridgeRootURL() -> URL? {
    let fileManager = FileManager.default
    if let bundledRoot = Bundle.main.resourceURL,
       fileManager.fileExists(atPath: bundledRoot.appendingPathComponent("apps/bridge/server.mjs").path) {
      return bundledRoot
    }
    var url = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    for _ in 0..<6 {
      if fileManager.fileExists(atPath: url.appendingPathComponent("package.json").path),
         fileManager.fileExists(atPath: url.appendingPathComponent("apps/bridge/server.mjs").path) {
        return url
      }
      url.deleteLastPathComponent()
    }
    return nil
  }

  private func nodeExecutableURL() -> URL? {
    let fileManager = FileManager.default
    let candidates = [
      ProcessInfo.processInfo.environment["CHAOS_CAT_NODE"],
      Bundle.main.resourceURL?.appendingPathComponent("Runtime/node").path,
      "/opt/homebrew/bin/node",
      "/usr/local/bin/node",
      "/usr/bin/node"
    ].compactMap { $0 }.map { URL(fileURLWithPath: $0) }
    return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
  }

  private func fetchBridgeEvents() {
    guard !bridgeFetchPending else{return}
    bridgeFetchPending=true
    URLSession.shared.dataTask(with: bridgeURL.appending(queryItems: [URLQueryItem(name: "limit", value: "80")])) { [weak self] data, _, _ in
      guard let self else { return }
      DispatchQueue.main.async { self.bridgeFetchPending=false }
      guard let data else{return}
      guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let events = json["events"] as? [[String: Any]]
      else { return }

      DispatchQueue.main.async {
        for event in events {
          self.handleBridgeEvent(event)
        }
      }
    }.resume()
  }

  private func handleBridgeEvent(_ event: [String: Any]) {
    guard let id = event["id"] as? String, seenEventIDs.insert(id).inserted else { return }
    // The bridge retains 250 events. Bound deduplication memory while keeping
    // more than a full server history, so polling cannot replay old actions.
    seenEventOrder.append(id)
    if seenEventOrder.count > 512 { seenEventIDs.remove(seenEventOrder.removeFirst()) }
    if let createdAt = event["createdAt"] as? String,
       let date = fractionalDateFormatter.date(from: createdAt) ?? dateFormatter.date(from: createdAt),
       date < launchedAt { return }
    let source = event["source"] as? String ?? ""
    guard source != "macos-overlay" else { return }
    let type = event["type"] as? String ?? ""
    let payload = event["payload"] as? [String: Any] ?? [:]
    if type == "editor.visibleRangesChanged", let uri = payload["uri"] as? String {
      editorViewports[uri] = EditorViewport(uri: uri,
        visibleStartLine: payload["visibleStartLine"] as? Int ?? 0,
        visibleEndLine: payload["visibleEndLine"] as? Int ?? 0,
        lineCount: payload["lineCount"] as? Int ?? 1,
        fontSize: CGFloat(payload["fontSize"] as? Double ?? 14),
        lineHeight: CGFloat(payload["lineHeight"] as? Double ?? 21))
    }
    rules?.handle(type: type, payload: payload, source: source)
  }

  private func postEvent(type: String, payload: [String: Any]) {
    var request = URLRequest(url: bridgeURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "id": "\(Date().timeIntervalSince1970)-\(UUID().uuidString)",
      "type": type,
      "source": "macos-overlay",
      "payload": payload,
      "createdAt": ISO8601DateFormatter().string(from: Date())
    ])
    URLSession.shared.dataTask(with: request).resume()
  }
}

private extension URL {
  func appending(queryItems: [URLQueryItem]) -> URL {
    var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
    components?.queryItems = queryItems
    return components?.url ?? self
  }
}

private func desktopArtwork(_ name: String, size: NSSize) -> NSImage? {
  guard let url = Bundle.main.resourceURL?.appendingPathComponent("Assets/\(name)"),
        let image = NSImage(contentsOf: url) else { return nil }
  image.size = size
  image.isTemplate = false
  return image
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var pet: ChaosCatApp?
  private var statusItem: NSStatusItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    pet = ChaosCatApp()
    pet?.show()
    setupStatusItem()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationWillTerminate(_ notification:Notification) { pet?.shutdown() }

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let image = desktopArtwork("StatusIcon.png", size: NSSize(width: 22, height: 22)) {
      item.button?.image = image
      item.button?.imageScaling = .scaleProportionallyDown
      item.button?.title = ""
    } else {
      item.button?.title = "🐈"
    }
    item.button?.toolTip = "Chaos Cat"
    item.button?.setAccessibilityLabel("Chaos Cat 菜单")

    let menu = NSMenu()
    let clearItem = NSMenuItem(title: "清理", action: #selector(ChaosCatApp.clearEffects), keyEquivalent: "c")
    clearItem.target = pet
    if let image = desktopArtwork("CleanupPhoto.jpg", size: NSSize(width: 88, height: 88)) {
      // Use a native menu item: the whole photo remains clickable, with
      // standard hover highlighting, keyboard selection and Command-C.
      clearItem.title = ""
      clearItem.image = image
      clearItem.toolTip = "点击照片，一键清理所有屎和垃圾堆"
      clearItem.setAccessibilityLabel("一键清理")
      clearItem.setAccessibilityHelp("点击监狱鱼眼照片，清理所有屎和垃圾堆")
    }
    menu.addItem(clearItem)
    menu.addItem(.separator())

    let debugMenu = NSMenu()
    let debugItems: [(String, Selector)] = [
      ("拉屎", #selector(ChaosCatApp.poopChaos)),
      ("跳垃圾堆", #selector(ChaosCatApp.boxDive)),
      ("追虫", #selector(ChaosCatApp.bugChase)),
      ("休息", #selector(ChaosCatApp.calm))
    ]
    for (title, action) in debugItems {
      let actionItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
      actionItem.target = pet
      debugMenu.addItem(actionItem)
    }
    let debugRootItem = NSMenuItem(title: "调试动作", action: nil, keyEquivalent: "")
    menu.setSubmenu(debugMenu, for: debugRootItem)
    menu.addItem(debugRootItem)

    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "退出 Chaos Cat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    item.menu = menu

    statusItem = item
  }
}

let nsApp = NSApplication.shared
let delegate = AppDelegate()
nsApp.delegate = delegate
nsApp.run()
