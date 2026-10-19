import AppKit

@main struct BehaviorMenuTests {
  static func pump(_ seconds:Double) {RunLoop.main.run(until:Date().addingTimeInterval(seconds))}
  static func wait(_ label:String,until condition:()->Bool) {
    let end=Date().addingTimeInterval(10)
    while !condition(),Date()<end {pump(0.005)}
    precondition(condition(),"Timed out: \(label)")
  }
  static func main() throws {
    setenv("CHAOS_CAT_TEST","1",1);setenv("CHAOS_CAT_TEST_SPEED","40",1)
    NSApplication.shared.setActivationPolicy(.accessory)
    let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
    let library=try BehaviorLibrary(directory:root.appendingPathComponent(ProcessInfo.processInfo.environment["CHAOS_CAT_BEHAVIOR_ASSETS"] ?? "apps/macos/Assets/Behavior"))
    let screen=NSScreen.main!,owner="vscode-extension:menu-test",uri="untitled:menu"
    var actor:BehaviorController!,poops:Set<String>=[],heap:String?,ops:[String]=[],cleanups=0,insertions=0
    var holdReply=false,lateReply:[String:Any]?
    let point=CGPoint(x:screen.visibleFrame.minX+350,y:screen.visibleFrame.minY+180)
    actor=BehaviorController(library:library,screen:screen,emit:{type,p in
      if type=="cleanup.requested" {cleanups+=1;poops.removeAll();return}
      guard type=="behavior.request" else{return}
      let op=p["operation"] as! String;ops.append(op)
      precondition(p["target"] as? String==owner,"Status menu must retain the last editor")
      var response:[String:Any]=["ok":true,"requestId":p["requestId"]!,"clientId":owner]
      switch op {
      case "target.pick":
        precondition((p["anchor"] as? [String:Any])?["uri"] as? String==uri)
        response["anchor"]=["uri":uri,"targetId":"target"]
      case "poop.create":
        insertions+=1;let id="poop-\(insertions)";poops.insert(id);response["id"]=id
        if holdReply {lateReply=response;return}
      case "rubbish.create":heap="heap";response["id"]="heap";response["anchor"]=["uri":uri,"id":"heap"]
      case "marker.remove":
        let id=p["id"] as! String
        if heap==id {heap=nil};poops.remove(id)
      default:preconditionFailure("Unexpected operation: \(op)")
      }
      let reply=response
      DispatchQueue.main.async {actor.handle(type:"behavior.response",payload:reply,source:"vscode-extension")}
    },resolve:{_ in point},editorRect:{screen.visibleFrame})
    actor.start()
    actor.handle(type:"client.hello",payload:["clientId":owner,"active":true,"uri":uri],source:"vscode-extension")
    pump(4.1) // A menu may stay open longer than the editor focus timeout.
    actor.rest();precondition(actor.mode == .rest)
    actor.performDebugAction("poopChaos");precondition(actor.mode == .poop)
    wait("three debug poop rounds retain original editor"){insertions==3 && actor.mode == .walk}
    precondition(poops.count==3)
    actor.performDebugAction("poopChaos");precondition(actor.mode == .poop)
    actor.performDebugAction("bugChase");precondition(actor.mode == .bug)
    actor.performDebugAction("rubbish");precondition(actor.mode == .rubbish)
    wait("debug rubbish creates real gap"){heap != nil}
    actor.performDebugAction("calm");precondition(actor.mode == .rest)
    wait("debug switch restores rubbish gap"){heap == nil}
    actor.clearAll();precondition(actor.mode == .walk && poops.isEmpty && cleanups==1)
    pump(0.3);precondition(actor.mode == .walk && insertions==3)

    holdReply=true;actor.performDebugAction("poopChaos")
    wait("pending insertion reply"){lateReply != nil}
    actor.clearAll();precondition(poops.isEmpty && actor.mode == .walk)
    actor.handle(type:"behavior.response",payload:lateReply!,source:"vscode-extension")
    pump(0.5);precondition(poops.isEmpty && insertions==4 && actor.mode == .walk)
    precondition(!ops.contains("poop.list"),"Immediate cleanup must not wait for burial")
    actor.shutdown();actor.cat.hide()
    let checks=["all four menu actions immediately replace the current state","menu focus timeout retains the editor for all three poop rounds","switching out of rubbish restores its gap","clear cancels rest/poop and removes every marker immediately","late insertion reply cannot recreate dirt after clear"]
    let report:[String:Any]=["passed":true,"checks":checks,"operations":ops,"cleanupBroadcasts":cleanups]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("docs/menu-behavior-validation.json"))
    print("PASS: menu dispatch and immediate cleanup regressions")
  }
}
