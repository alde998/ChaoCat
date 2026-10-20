import AppKit

@main struct BehaviorRubbishLayoutTests {
  static func main() throws {
    setenv("CHAOS_CAT_TEST","1",1);setenv("CHAOS_CAT_TEST_SPEED","12",1)
    NSApplication.shared.setActivationPolicy(.accessory)
    guard let screen=NSScreen.main else{exit(77)}
    let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
    let library=try BehaviorLibrary(directory:root.appendingPathComponent(ProcessInfo.processInfo.environment["CHAOS_CAT_BEHAVIOR_ASSETS"] ?? "apps/macos/Assets/Behavior"))
    let area=CGRect(x:0,y:0,width:2400,height:1200),heap=CGPoint(x:1200,y:400)
    for left in [false,true] {
      var actor:BehaviorController!
      actor=BehaviorController(library:library,screen:screen,emit:{type,payload in
        guard type=="behavior.request" else{return}
        let response:[String:Any]=["requestId":payload["requestId"]!,"clientId":"layout", "ok":true,
                                  "id":"heap","anchor":["id":"heap","lineHeight":0.0]]
        DispatchQueue.main.async {actor.handle(type:"behavior.response",payload:response,source:"vscode-extension")}
      },resolve:{_ in CGPoint(x:heap.x,y:heap.y-18)},editorRect:{area},movementArea:{_ in area})
      actor.handle(type:"client.hello",payload:["clientId":"layout","active":true],source:"vscode-extension")
      actor.cat.foot=CGPoint(x:heap.x+(left ? 260:-260),y:heap.y)
      actor.rubbish()
      var jumpOrigin:CGPoint?,jumpName=""
      actor.cat.onClipStart={name,point in
        if name.hasPrefix("rubbish-jump-") {jumpOrigin=point;jumpName=name}
      }
      let end=Date().addingTimeInterval(8)
      while !actor.cat.clipName.hasPrefix("rubbish-tail-"),Date()<end {
        RunLoop.main.run(until:Date().addingTimeInterval(0.005))
      }
      guard let origin=jumpOrigin else{preconditionFailure("Missing takeoff")}
      let jump=library.clips[jumpName]!,heapClip=library.clips["rubbish-tail-right"]!
      let sign:CGFloat=jumpName.hasSuffix("right") ? 1:-1
      let noseOffset=(1141-760)*jump.scale
      let visibleGap=(heap.x-origin.x)*sign-CGFloat(noseOffset+(800-348)*heapClip.scale)
      precondition(abs(visibleGap-18)<0.01,"Calibrated cat must still take off outside the heap")
      precondition(hypot(actor.cat.foot.x-heap.x,actor.cat.foot.y-heap.y)<1)
      precondition(actor.cat.clipName.hasPrefix("rubbish-tail-"),"Jump must finish aligned to the static heap")
      actor.pressed(fromHeap:true)
      precondition(actor.cat.clipName.hasPrefix("drag-") && !actor.cat.clipName.hasPrefix("drag-enter-"))
      actor.shutdown();actor.cat.hide()
      print("PASS:",left ? "left":"right","calibrated takeoff gap, heap landing and pickup")
    }
  }
}
