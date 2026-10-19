import AppKit

@main struct BehaviorBugTriggerTests {
  static func main() throws {
    setenv("CHAOS_CAT_TEST","1",1)
    NSApplication.shared.setActivationPolicy(.accessory)
    guard let screen=NSScreen.main else{exit(77)}
    let directory=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(ProcessInfo.processInfo.environment["CHAOS_CAT_BEHAVIOR_ASSETS"] ?? "apps/macos/Assets/Behavior")
    let library=try BehaviorLibrary(directory:directory)
    var editing=true,roll=0.5,rolls=0
    func actor()->BehaviorController {
      BehaviorController(library:library,screen:screen,emit:{_,_ in},resolve:{_ in CGPoint(x:700,y:400)},editorRect:{.zero},
                         isEditorForeground:{_ in editing},isEditorContext:{editing},
                         bugChanceRoll:{rolls += 1;return roll})
    }
    let a=actor()
    defer {a.pressed();a.shutdown();a.cat.hide()}
    let future=Date().addingTimeInterval(9)
    roll=0
    a.checkAmbientBug(at:future)
    precondition(a.mode == .walk && rolls==0,"Idle editor cannot trigger ambient chase, even on a winning roll")
    let input:[String:Any] = ["active":true,"direction":"right","anchor":["x":700.0,"y":400.0]]
    roll=0.5
    a.handle(type:"editor.textChanged",payload:input,source:"obsidian-plugin")
    precondition(a.mode == .walk && rolls==1,"Typing must be probabilistic")
    roll=0
    for _ in 0..<20 {a.handle(type:"editor.textChanged",payload:input,source:"obsidian-plugin")}
    precondition(a.mode == .walk && rolls==1,"Rapid typing gets only one probability check per interval")

    let b=actor()
    defer {b.pressed();b.shutdown();b.cat.hide()}
    roll=0.1
    b.handle(type:"editor.textChanged",payload:input,source:"obsidian-plugin")
    precondition(b.mode == .bug,"Typing probability should accept a 10% roll")
    precondition(b.bug.foot==CGPoint(x:700,y:428),"Spawn directly above insertion point, with no facing-dependent x offset")
    b.bug.view.pressed?(0)
    roll=0
    b.handle(type:"editor.textChanged",payload:input,source:"obsidian-plugin")
    precondition(b.mode != .bug,"Click dismissal applies the shared cooldown")

    editing=false
    let c=actor()
    defer {c.pressed();c.shutdown();c.cat.hide()}
    roll=0.1
    c.checkAmbientBug(at:future)
    precondition(c.mode == .walk,"Non-editor probability is lower than typing probability")
    roll=0
    c.checkAmbientBug(at:future.addingTimeInterval(1))
    precondition(c.mode == .walk,"Ambient attempts are throttled")
    c.checkAmbientBug(at:future.addingTimeInterval(9))
    precondition(c.mode == .bug,"Other foreground apps can spawn an insect without text input")
    let origin=c.bug.foot
    RunLoop.main.run(until:Date().addingTimeInterval(1.2))
    precondition(hypot(c.bug.foot.x-origin.x,c.bug.foot.y-origin.y)>35,"Ambient insects fly across the application without any input")
    precondition(c.cat.clipName != "chase-left" && c.cat.clipName != "chase-right")
    print("PASS: editor idle exclusion, typing probability/throttle, lower ambient probability/throttle, cooldown and autonomous flight")
  }
}
