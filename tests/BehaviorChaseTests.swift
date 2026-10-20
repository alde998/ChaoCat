import AppKit

@main struct BehaviorChaseTests {
  static func spin(until condition:()->Bool, timeout:Double) {
    let deadline=Date().addingTimeInterval(timeout)
    while !condition() && Date()<deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.005)) }
    precondition(condition(),"Animation did not reach its next state")
  }
  static func main() throws {
    setenv("CHAOS_CAT_TEST","1",1)
    NSApplication.shared.setActivationPolicy(.accessory)
    guard let screen=NSScreen.main else { exit(77) }
    let directory=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(ProcessInfo.processInfo.environment["CHAOS_CAT_BEHAVIOR_ASSETS"] ?? "apps/macos/Assets/Behavior")
    let library=try BehaviorLibrary(directory:directory)
    for prefix in ["chase-run","chase","catch","chase-roll","chase-recover","bug-fly","bug-escape"] {
      for direction in ["left","right"] {
        let name=prefix+"-"+direction
        let clip=library.clips[name]!
        for frame in 0..<clip.frames {
          precondition(library.image(name,frame:frame) != nil,"Native GIF decode failed: \(name):\(frame)")
        }
      }
    }
    print("PASS: all pounce / roll / recovery frames decode natively in both directions")
    let lift=BehaviorController(library:library,screen:screen,emit:{_,_ in},resolve:{_ in nil},editorRect:{.zero})
    let start=Date()
    lift.pressed()
    precondition(lift.cat.clipName=="drag-enter-right")
    spin(until:{lift.cat.clipName=="drag-right"},timeout:1.0)
    let elapsed=Date().timeIntervalSince(start)
    precondition(elapsed>=0.58 && elapsed<0.85,"Lift must finish in approximately 0.6 s, not 0.96 s")
    lift.shutdown();lift.cat.hide()
    print("PASS: real-time lift to held pose:",elapsed)

    setenv("CHAOS_CAT_TEST_SPEED","8",1)
    let actor=BehaviorController(library:library,screen:screen,emit:{_,_ in},resolve:{a in
      guard let x=a["x"] as? Double,let y=a["y"] as? Double else{return nil}
      return CGPoint(x:x,y:y)
    },editorRect:{.zero},movementArea:{_ in CGRect(x:0,y:0,width:2400,height:1200)},bugChanceRoll:{0})
    defer {actor.shutdown();actor.cat.hide()}
    actor.cat.foot=CGPoint(x:200,y:400)
    func input(_ direction:String,x:Double) {
      actor.handle(type:"editor.textChanged",payload:["active":true,"direction":direction,
        "anchor":["x":x,"y":400.0]],source:"obsidian-plugin")
    }
    input("right",x:1600)
    precondition(actor.bug.clipName=="bug-fly-right")
    let flyFoot=actor.bug.foot
    var flyStarts=0
    actor.bug.onClipStart={_,_ in flyStarts += 1}
    input("left",x:1550)
    precondition(actor.bug.clipName=="bug-fly-left","Input must change the displayed direction immediately")
    precondition(actor.bug.foot==flyFoot,"Changing direction must not teleport the fly")
    input("right",x:1600)
    precondition(actor.bug.clipName=="bug-fly-right" && flyStarts==0,"Facing changes preserve wingbeat timing")
    spin(until:{actor.cat.clipName=="chase-run-right"},timeout:2)
    var gaitStarts=0
    actor.cat.onClipStart={name,_ in if name.hasPrefix("chase-run-"){gaitStarts += 1}}
    let from=actor.cat.foot,started=Date()
    var previous=from
    var previousTime=Date()
    let run=library.clips["chase-run-right"]!
    let expectedSpeed=run.stride/run.duration*8
    while Date().timeIntervalSince(started)<0.32 {
      RunLoop.main.run(until:Date().addingTimeInterval(0.005))
      let now=actor.cat.foot
      let measuredAt=Date(),dt=measuredAt.timeIntervalSince(previousTime)
      precondition(now.x>=previous.x && now.x-previous.x<CGFloat(expectedSpeed*(dt+0.035)),"Approach must advance without backwards hops or teleports: \(now.x-previous.x) in \(dt)s")
      previous=now;previousTime=measuredAt
    }
    let travelled=actor.cat.foot.x-from.x
    let expected=expectedSpeed*Date().timeIntervalSince(started)
    precondition(travelled>CGFloat(expected*0.65) && travelled<CGFloat(expected*1.15),"Desktop motion must match the rubbish-run stride speed")
    precondition(gaitStarts==0,"Three gait cycles must not restart playback or crossfade at each stride")
    print("PASS: immediate input-facing changes; continuous multi-cycle approach",travelled)
    let bugFrom=actor.bug.foot
    RunLoop.main.run(until:Date().addingTimeInterval(0.3))
    precondition(hypot(actor.bug.foot.x-bugFrom.x,actor.bug.foot.y-bugFrom.y)>65,"Insect must travel autonomously after typing stops")

    for direction in [PetFacing.right,PetFacing.left] {
      actor.pressed()
      actor.cat.view.dragged?(CGPoint(x:8*direction.sign,y:0),ProcessInfo.processInfo.systemUptime)
      actor.cat.foot=CGPoint(x:1200,y:400)
      actor.chase()
      var pounces=0,rolls=0,recoveries=0
      var previous=""
      var recoveryStart:CGPoint?
      var recoveryTime=Date.distantPast
      var recoverySign:CGFloat=1
      var hasPounced=false,shortChaseSincePounce=false
      actor.cat.onClipStart={name,_ in
        if name=="chase-left" || name=="chase-right" {shortChaseSincePounce=true}
        if let start=recoveryStart {
          let stride=CGFloat(library.clips[previous]!.stride)
          let expectedX=min(2328,max(72,start.x+stride*recoverySign))
          precondition(abs(actor.cat.foot.x-expectedX)<0.5,"Recovery trot must advance by its authored stride, shortened only at the window edge")
          recoveryStart=nil
        }
        if name.hasPrefix("catch-") {
          precondition(!hasPounced || shortChaseSincePounce,"Every two pounces must include a short non-sprinting chase, even across a roll")
          pounces += 1;hasPounced=true;shortChaseSincePounce=false
        }
        if name.hasPrefix("chase-roll-") {
          precondition((1...3).contains(pounces),"Roll must follow 1–3 single pounces")
          pounces=0;rolls += 1
        }
        if name.hasPrefix("chase-recover-") {
          precondition(previous.hasPrefix("chase-roll-") && previous.hasSuffix(name.hasSuffix("right") ? "right":"left"))
          recoveries += 1
          recoveryStart=actor.cat.foot;recoveryTime=Date()
          recoverySign=name.hasSuffix("right") ? 1:-1
        }
        previous=name
      }
      spin(until:{
        if let start=recoveryStart,Date().timeIntervalSince(recoveryTime)<0.1 {
          precondition(actor.cat.foot==start,"The shake / seated phase must not slide before the first step")
        }
        return rolls>=3
      },timeout:9)
      precondition(recoveries==2,"Every completed roll must recover before another pounce")
      // Interrupt mid-roll: its delayed completion must never restart chasing.
      actor.pressed()
      spin(until:{actor.cat.clipName.hasPrefix("drag-") && !actor.cat.clipName.hasPrefix("drag-enter-")},timeout:1)
      RunLoop.main.run(until:Date().addingTimeInterval(0.6))
      precondition(actor.mode == .dragged && actor.cat.clipName.hasPrefix("drag-") && !actor.cat.clipName.hasPrefix("drag-enter-"))
      print("PASS:",direction,"three roll rounds, each after 1–3 pounces; drag cancels the sequence")
    }
  }
}
