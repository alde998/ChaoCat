import AppKit

@main struct BehaviorOverlayTests {
  static func wait(_ label: String, until condition: () -> Bool) {
    let deadline=Date().addingTimeInterval(8)
    while !condition(),Date()<deadline {
      RunLoop.main.run(until:Date().addingTimeInterval(0.01))
    }
    precondition(condition(),"Timed out: \(label)")
  }

  static func main() throws {
    setenv("CHAOS_CAT_TEST","1",1)
    setenv("CHAOS_CAT_TEST_SPEED","40",1)
    NSApplication.shared.setActivationPolicy(.accessory)
    let screen=NSScreen.main!
    let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
    let library=try BehaviorLibrary(directory:root.appendingPathComponent(ProcessInfo.processInfo.environment["CHAOS_CAT_BEHAVIOR_ASSETS"] ?? "apps/macos/Assets/Behavior"))
    let hitView=BehaviorSpriteView(frame:CGRect(x:0,y:0,width:288,height:180))
    hitView.image=library.image("poop-right",frame:60)
    hitView.preciseHitTest=true
    precondition(hitView.acceptsPress(at:CGPoint(x:150,y:120)),"Current seated cat's chest should accept a click")
    precondition(!hitView.acceptsPress(at:CGPoint(x:10,y:10)),"Transparent canvas should not accept a click")
    hitView.image=library.image("poop-left",frame:60)
    precondition(hitView.acceptsPress(at:CGPoint(x:138,y:120)),"Mirrored chest must retain its matching clickable location")
    precondition(!hitView.acceptsPress(at:CGPoint(x:278,y:10)),"Mirrored transparent canvas should not accept a click")
    hitView.image=library.image("poop-right",frame:60)
    hitView.hitRegion={point in point.x/288 >= 0.40}
    precondition(!hitView.acceptsPress(at:CGPoint(x:90,y:140)),"Baked poop should not scare the cat")
    hitView.hitRegion=nil
    for name in ["walk-right","sit-down-right","sleep-right","bury-right","rubbish-jump-right"] {
      hitView.image=library.image(name,frame:0)
      precondition(!hitView.acceptsPress(at:CGPoint(x:10,y:10)),"\(name) transparent canvas should not accept a click")
      precondition((0..<18).contains { row in
        (0..<28).contains { column in hitView.acceptsPress(at:CGPoint(x:CGFloat(column*10+4),y:CGFloat(row*10+4))) }
      },"\(name) visible cat should accept a click")
    }
    var foreground="window-a"
    var editorForeground=false
    var requests:[String]=[]
    let firstArea=CGRect(x:screen.visibleFrame.midX,y:screen.visibleFrame.minY,
                         width:screen.visibleFrame.width/2,height:screen.visibleFrame.height)
    let secondArea=CGRect(x:screen.visibleFrame.minX,y:screen.visibleFrame.minY,
                          width:screen.visibleFrame.width/2,height:screen.visibleFrame.height)
    let actor=BehaviorController(
      library:library,screen:screen,emit:{type,payload in
        if type == "behavior.request",let operation=payload["operation"] as? String { requests.append(operation) }
      },resolve:{_ in nil},
      editorRect:{firstArea},workArea:{foreground == "window-a" ? firstArea : secondArea},
      workIdentity:{foreground},isEditorForeground:{_ in editorForeground})
    precondition(actor.cat.view.preciseHitTest,"Every cat state should use sprite transparency for hit testing")
    actor.handle(type:"client.hello",payload:["clientId":"vscode-extension:test","active":true],source:"vscode-extension")
    actor.poop()

    func marker() -> NSPanel? {
      NSApplication.shared.windows.compactMap{$0 as? NSPanel}
        .first{$0.contentView?.accessibilityLabel() == "桌面屎：点击清除"}
    }
    wait("floating marker appears"){marker()?.isVisible == true}
    let panel=marker()!
    let view=panel.contentView!
    precondition(panel.canBecomeKey && !panel.ignoresMouseEvents)
    precondition(firstArea.contains(CGPoint(x:panel.frame.midX,y:panel.frame.midY)))
    precondition(requests.isEmpty,"Background editor must not receive poop requests")
    foreground="window-b"
    wait("marker hides behind another foreground window"){!panel.isVisible}
    foreground="window-a"
    wait("marker returns to its owning window"){panel.isVisible}

    let point=NSPoint(x:view.bounds.midX,y:view.bounds.midY)
    let event=NSEvent.mouseEvent(
      with:.leftMouseDown,location:point,modifierFlags:[],
      timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,
      context:nil,eventNumber:1,clickCount:1,pressure:1)!
    precondition(view.acceptsFirstMouse(for:event))
    panel.sendEvent(event)
    precondition(!panel.isVisible,"Click must remove the native marker")
    actor.clearAll()
    editorForeground=true
    actor.handle(type:"client.hello",payload:["clientId":"vscode-extension:test","active":true],source:"vscode-extension")
    actor.poop()
    wait("foreground editor receives target request"){requests.contains("target.pick")}
    actor.cat.hide()
    print("PASS: floating poop click, foreground window bounds, and background editor gating")
  }
}
