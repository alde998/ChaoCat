import AppKit

// Exercise the real view callbacks, sprite clock and behavior controller.
// The editor responses below are a fixture; real VS Code has a separate host test.
@main struct BehaviorDragTests {
  static func wait(_ label:String,seconds:Double=6,until condition:()->Bool) {
    let end=Date().addingTimeInterval(seconds)
    while !condition(),Date()<end {RunLoop.main.run(until:Date().addingTimeInterval(0.005))}
    precondition(condition(),"Timed out: \(label)")
  }
  static func pump(_ seconds:Double) {RunLoop.main.run(until:Date().addingTimeInterval(seconds))}
  static func main() throws {
    setenv("CHAOS_CAT_TEST","1",1);setenv("CHAOS_CAT_TEST_SPEED","40",1)
    let app=NSApplication.shared;app.setActivationPolicy(.accessory)
    let screen=NSScreen.main!
    let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
    let library=try BehaviorLibrary(directory:root.appendingPathComponent(ProcessInfo.processInfo.environment["CHAOS_CAT_BEHAVIOR_ASSETS"] ?? "apps/macos/Assets/Behavior"))
    let owner="vscode-extension:drag-test",uri="untitled:drag-fixture"
    let point=CGPoint(x:screen.visibleFrame.minX+380,y:screen.visibleFrame.minY+180)
    var poops:Set<String>=[],heap:String?,removals:[String]=[],requests:[String]=[],checks:[String]=[]
    var scatteredPoops=0
    var scatterTimes:[TimeInterval]=[]
    var actor:BehaviorController!
    func anchor(_ id:String)->[String:Any] { ["id":id,"uri":uri] }
    actor=BehaviorController(library:library,screen:screen,emit:{type,p in
      if type=="cleanup.requested" {poops.removeAll();heap=nil;return}
      guard type=="behavior.request" else{return}
      let op=p["operation"] as! String;requests.append(op)
      precondition(p["target"] as? String==owner,"Cleanup must retain the editor selected before dragging")
      var result:[String:Any]=["ok":true]
      switch op {
      case "poop.list":
        precondition((p["anchor"] as? [String:Any])?["uri"] as? String==uri)
        result["anchors"]=poops.sorted().map(anchor)
      case "marker.locate": result["anchor"]=anchor(p["id"] as! String)
      case "marker.remove":
        let id=p["id"] as! String
        if poops.contains(id) {
          precondition(["bury-left","bury-right"].contains(actor.cat.clipName),"Delete only on the burial disappearance frame")
          poops.remove(id);removals.append(id)
        } else {precondition(heap==id);heap=nil}
      case "target.pick": result["anchor"]=anchor("poop-target")
      case "poop.create":
        if p["random"] as? Bool == true {
          precondition(actor.mode == .scared)
          precondition(["run-left","run-right"].contains(actor.cat.clipName),"Scatter only while moving, not during stationary transitions")
          scatterTimes.append(ProcessInfo.processInfo.systemUptime)
        }
        scatteredPoops += 1
        let id="scattered-\(scatteredPoops)";poops.insert(id);result["id"]=id
      case "rubbish.create": heap="heap";result["id"]="heap";result["anchor"]=anchor("heap")
      default:preconditionFailure("Unexpected operation \(op)")
      }
      result["requestId"]=p["requestId"];result["clientId"]=owner
      let response=result
      DispatchQueue.main.async {actor.handle(type:"behavior.response",payload:response,source:"vscode-extension")}
    },resolve:{_ in point},editorRect:{screen.visibleFrame})
    func focus() {actor.handle(type:"editor.visibleRangesChanged",payload:["clientId":owner,"active":true,"uri":uri],source:"vscode-extension")}
    func press(_ time:Double) {actor.cat.view.pressed?(time)}
    func drag(_ dx:CGFloat,_ time:Double) {actor.cat.view.dragged?(CGPoint(x:dx,y:0),time)}
    func release() {actor.cat.view.released?(true)}
    func fast(_ t:Double) {press(t);drag(100,t+0.05);drag(-100,t+0.10)}
    actor.start();focus()

    press(0)
    precondition(actor.cat.clipName=="drag-enter-right","mouse-down starts lift animation")
    drag(30,0.5)
    precondition(actor.cat.clipName=="drag-enter-right")
    wait("lift changes to suspended hold"){actor.cat.clipName=="drag-right"}
    drag(-10,1.2)
    precondition(actor.cat.clipName=="drag-left","direction reversal switches hold without replaying lift")
    drag(10,1.3)
    precondition(actor.cat.clipName=="drag-right","direction reversal switches hold back without replaying lift")
    release();precondition(actor.cat.clipName=="drag-exit-right")
    wait("gentle drag stands up after landing"){actor.cat.clipName=="sit-up-right"}
    let landingClip=library.clips["drag-exit-right"]!,standingClip=library.clips["sit-up-right"]!
    let previousFrame=actor.cat.view.previousImageRect
    precondition(abs(previousFrame.width-landingClip.width*landingClip.scale)<0.01 &&
                 abs(previousFrame.minX-(standingClip.footX*standingClip.scale-landingClip.footX*landingClip.scale))<0.01,
                 "Landing frame must retain its fixed size and foot alignment during the stand-up blend")
    wait("gentle drag returns to walk"){actor.mode == .walk}
    precondition(requests.isEmpty)
    checks.append("gentle drag: lift → hold → land → stand → walk; no cleanup request")

    press(2);actor.cat.view.released?(false)
    precondition(actor.cat.clipName=="drag-exit-right","A stationary release must still land")
    wait("stationary release stands up"){actor.cat.clipName=="sit-up-right"}
    wait("stationary release resumes walking"){actor.mode == .walk}
    checks.append("stationary release: land → stand → walk")

    focus();poops=["first","second"];fast(10)
    pump(4.1) // More than the native editor focus timeout.
    actor.handle(type:"client.hello",payload:["clientId":"vscode-extension:another-window","active":true,"uri":"untitled:other"],source:"vscode-extension")
    release()
    wait("fast drag buries both original markers"){poops.isEmpty && actor.mode == .walk}
    precondition(Set(removals)==["first","second"])
    checks.append("fast drag after focus timeout retains original document; two markers removed on bury frames")

    focus();poops=["kept"];let previous=requests.count
    fast(20);release() // Release during lift, then regrab during return.
    press(21);drag(-20,21.5)
    wait("regrab uses mirrored hold"){actor.cat.clipName=="drag-left"}
    precondition(requests.count==previous && poops.contains("kept"))
    release();wait("second gentle drag exits"){actor.mode == .walk}
    precondition(requests.count==previous)
    checks.append("regrab cancels pending fast-drag cleanup and stale animation callbacks")

    focus();actor.poop();precondition(actor.mode == .poop)
    let beforeDragScatter=scatteredPoops
    fast(30);release()
    wait("fast drag exits poop without scattering"){actor.mode == .walk}
    precondition(scatteredPoops == beforeDragScatter)
    checks.append("fast drag exits poop without creating new document markers")

    focus();actor.poop();precondition(actor.mode == .poop)
    press(31);actor.cat.view.released?(false)
    precondition(scatteredPoops==beforeDragScatter,"Entry must not synchronously scatter")
    precondition(actor.cat.panel.ignoresMouseEvents,"Frantic run cannot be caught by clicking")
    press(31.01);drag(100,31.02);release()
    precondition(actor.mode == .scared,"Pointer input cannot interrupt frightened run")
    wait("a click starts frightened run"){actor.mode == .scared}
    wait("click scatters real markers",seconds:12){scatteredPoops >= beforeDragScatter + BehaviorPolicy.scatteredPoopCount}
    precondition(scatteredPoops >= beforeDragScatter + BehaviorPolicy.scatteredPoopCount)
    precondition(scatterTimes.count==BehaviorPolicy.scatteredPoopCount)
    precondition(zip(scatterTimes,scatterTimes.dropFirst()).allSatisfy{$1-$0>0.001},"Scatter requests must be separated in time")
    actor.clearAll();pump(0.2)
    precondition(!actor.cat.panel.ignoresMouseEvents)
    checks.append("click starts uncatchable frightened run; markers arrive separately after entry")

    focus();actor.poop();actor.clicked()
    wait("first timed scatter"){scatteredPoops>beforeDragScatter+BehaviorPolicy.scatteredPoopCount}
    actor.clearAll();let countAfterClear=scatteredPoops;pump(0.3)
    precondition(scatteredPoops==countAfterClear && poops.isEmpty,"Clear must cancel future scatter ticks")
    checks.append("clear during frightened run cancels remaining scatter and restores pointer input")

    focus();actor.rubbish();wait("heap exists"){heap != nil}
    precondition(!actor.cat.view.preciseHitTest,"Heap state must expose a broad drag target while the cat is buried")
    let before=removals.count;fast(40);release()
    wait("fast drag releases heap and finishes empty cleanup"){heap==nil && actor.mode == .walk}
    precondition(actor.cat.view.preciseHitTest,"Precise cat hit-testing returns after leaving the heap")
    precondition(removals.count==before)
    checks.append("rubbish gap released on drag; no poop targets returns to walk")

    for offset:CGFloat in [0,60] {
      actor.cat.foot=CGPoint(x:point.x+offset,y:point.y)
      focus();actor.rubbish()
      var jumpStart:CGPoint?,jumpFacing:PetFacing?
      actor.cat.onClipStart={name,foot in
        if jumpStart == nil && name.hasPrefix("rubbish-jump") {
          jumpStart=foot
          jumpFacing=name.hasSuffix("left") ? .left:.right
        }
      }
      wait("nearby heap reaches tail after a real jump",seconds:12){actor.cat.clipName.hasPrefix("rubbish-tail")}
      guard let jumpStart,let jumpFacing else{preconditionFailure("Jump was skipped")}
      let gap=(point.x-jumpStart.x)*jumpFacing.sign
      precondition(abs(gap-BehaviorPolicy.rubbishTakeoffDistance)<2,
                   "The jump must start outside the heap, not at its center")
      actor.clearAll()
    }
    checks.append("nearby heaps stage on both sides; jump begins at the calibrated takeoff point")

    func heapPanel()->NSPanel? {
      NSApplication.shared.windows.compactMap{$0 as? NSPanel}.first {
        $0.isVisible && $0.contentView?.accessibilityLabel()=="垃圾堆：点击拖动小猫"
      }
    }
    focus();actor.rubbish()
    wait("clickable heap reaches tail"){actor.cat.clipName.hasPrefix("rubbish-tail") && heapPanel() != nil}
    let pile=heapPanel()!
    precondition(!pile.ignoresMouseEvents,"Visible heap must receive mouse input")
    let pileView=pile.contentView as! BehaviorSpriteView
    let heapScale=CGFloat(library.clips["rubbish-tail-right"]!.scale)
    let heapFoot=CGPoint(x:pile.frame.minX+800*heapScale,
                         y:pile.frame.minY+pileView.bounds.height-900*heapScale)
    precondition(abs(pileView.imageRect.width-1600*heapScale)<0.01 &&
                 hypot(heapFoot.x-actor.cat.foot.x,heapFoot.y-actor.cat.foot.y)<2,
                 "Static heap and animated tail must share their display scale and foot anchor")
    let center=CGPoint(x:pile.contentView!.bounds.midX,y:pile.contentView!.bounds.midY)
    func heapEvent(_ type:NSEvent.EventType,_ number:Int)->NSEvent {
      NSEvent.mouseEvent(with:type,location:center,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                        windowNumber:pile.windowNumber,context:nil,eventNumber:number,clickCount:1,pressure:1)!
    }
    pile.sendEvent(heapEvent(.leftMouseDown,1))
    precondition(actor.cat.clipName.hasPrefix("drag-") && !actor.cat.clipName.hasPrefix("drag-enter"),
                 "Heap click must begin the suspended hold without replaying the lift")
    precondition(pile.isVisible,"Keep the input panel until mouse-up so drag events are not lost")
    pile.sendEvent(heapEvent(.leftMouseUp,2))
    precondition(actor.cat.clipName.hasPrefix("drag-exit"),"Heap release must play the landing")
    wait("heap click stands up after landing"){actor.cat.clipName.hasPrefix("sit-up")}
    wait("heap click completes landing"){actor.mode == .walk && heap == nil}
    checks.append("heap click starts suspended hold directly, then lands and stands up on release")

    actor.rest(roll:0.7)
    wait("first lick starts"){actor.cat.clipName.hasPrefix("lick-")}
    var secondLick:TimeInterval?
    var lickTransition:[String]=[]
    actor.cat.onClipStart={name,_ in
      lickTransition.append(name)
      if name.hasPrefix("lick-") && secondLick == nil {secondLick=ProcessInfo.processInfo.systemUptime}
    }
    wait("second lick starts after a complete seated animation",seconds:2){secondLick != nil}
    precondition(lickTransition.count==2 && lickTransition[0].hasPrefix("sit-") && lickTransition[1].hasPrefix("lick-"),
                 "Lick repetitions must play the moving seated animation between cycles, without a static timer")
    actor.clearAll()
    checks.append("lick cycles retain their authored speed with animated sitting between repetitions")

    actor.shutdown();actor.cat.hide()
    // Check the production-rate sprite clock: motion reaches 900 pt in half
    // a second while GIF frames still advance by their authored timestamps.
    setenv("CHAOS_CAT_TEST_SPEED","1",1)
    let runner=BehaviorSprite(library:library,interactive:false)
    let start=CGPoint(x:screen.visibleFrame.minX+120,y:screen.visibleFrame.minY+100)
    runner.foot=start
    var finished=false,samples=0
    let duration=BehaviorPolicy.scaredTravelDuration(distance:900)
    let began=ProcessInfo.processInfo.systemUptime
    runner.play("run-right",to:CGPoint(x:start.x+900,y:start.y),duration:duration,then:{finished=true})
    runner.onTick={progress in
      samples += 1
      precondition(abs(runner.foot.x-start.x-900*progress)<0.01)
      let frame=library.clips["run-right"]!.frame(at:progress*duration)
      precondition(runner.view.image === library.image("run-right",frame:frame),"Fast movement must preserve GIF frame cadence")
    }
    wait("independent motion clock",seconds:2){finished}
    precondition(samples>2 && ProcessInfo.processInfo.systemUptime-began<1)
    runner.hide()
    checks.append("900 pt sprint completes in 0.5 seconds with unchanged authored GIF timestamps")
    let report:[String:Any]=["passed":true,"checks":checks,"operations":requests,"removed":removals]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("docs/drag-behavior-validation.json"))
    print("PASS: \(checks.count) drag/controller regressions; actual animation clock and marker removal timing")
  }
}
