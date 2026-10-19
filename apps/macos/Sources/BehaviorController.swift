import AppKit

private final class LocalPoopView: NSImageView {
  var clicked: (() -> Void)?
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(convert(point, from: superview)) ? self : nil
  }
  override func mouseDown(with event: NSEvent) { clicked?() }
}

private final class LocalPoopPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

// The native actor is the single clock for every editor. Editor adapters only
// own their text mutations; an acknowledgement supplies the actual location.
final class BehaviorController {
  enum Mode: String { case walk, rest, bug, rubbish, poop, bury, scared, dragged }
  private(set) var mode: Mode = .walk
  private let library: BehaviorLibrary
  let cat: BehaviorSprite
  let bug: BehaviorSprite
  private var facing: PetFacing = .right
  private var generation = 0
  private var cleanupVersion = 0
  private var editor: String?
  private var editorSource: String?
  private var editorURI: String?
  private var editorSeen = Date.distantPast
  private var requests: [String: ([String: Any]) -> Void] = [:]
  private var requestOwners: [String: String] = [:]
  private var bugTarget = CGPoint.zero
  private var bugWaypoint = CGPoint.zero
  private var bugInputUntil = Date.distantPast
  private var lastTypingBugCheck = Date.distantPast
  private var lastAmbientBugCheck = Date()
  private var lastTyping = Date.distantPast
  private var automaticBugPending = false
  private var bugStarted = Date.distantPast
  private var lastBugEnded = Date.distantPast
  private var bugFacing: PetFacing = .right
  private var bugEscaping = false
  private var pouncesUntilRoll = 1
  private var flutterTimer: Timer?
  private var heap: NSPanel?
  private var grabbedHeap: NSPanel?
  private var heapAnchor: [String: Any]?
  private var heapID: String?
  private var heapOwner: String?
  private var pendingRestAction: (() -> Void)?
  private var protectedSleep = false
  private var restExit = "sit-up"
  private var lickPausePending = false
  private var buryID: String?
  private var buryOwner: String?
  private var buryAnchor: [String:Any]?
  private var cleanupOwner: String?
  private var cleanupURI: String?
  private var lastMischief = Date()
  private var poopClickPending = false
  private var scatterTimer: Timer?
  private var scatterRemaining = 0
  private var scatterOwner: String?
  private var scatterURI: String?
  private var scaredHeading: CGPoint?
  private var dragGesture = PetDragGesture()
  private var dragOwner: String?
  private var dragURI: String?
  private var dragLifted = false
  private let testMode = ProcessInfo.processInfo.environment["CHAOS_CAT_TEST"] == "1"
  // Used only when no editor integration owns the action. Editor-backed poop
  // remains real `/shit/` text and is tracked by its document marker id.
  private var localDirt: [(id: String, point: CGPoint, panel: NSPanel, window: String, relative: CGPoint)] = []
  private let emit: (String, [String: Any]) -> Void
  private let resolve: ([String: Any]) -> CGPoint?
  private let editorRect: () -> CGRect
  private let workArea: () -> CGRect
  private let workIdentity: () -> String
  private let isEditorForeground: (String) -> Bool
  private let isEditorContext: () -> Bool
  private let bugChanceRoll: () -> Double
  private var statusTimer: Timer?
  private var lastWorkIdentity: String?

  init(library: BehaviorLibrary, screen: NSScreen,
       emit: @escaping (String,[String:Any])->Void,
       resolve: @escaping ([String:Any])->CGPoint?, editorRect: @escaping ()->CGRect,
       workArea: @escaping ()->CGRect = { NSScreen.main?.visibleFrame ?? .zero },
       workIdentity: @escaping ()->String = { "desktop" },
       isEditorForeground: @escaping (String)->Bool = { _ in true },
       isEditorContext: @escaping ()->Bool = { false },
       bugChanceRoll: @escaping ()->Double = { Double.random(in:0..<1) }) {
    self.library=library;self.emit=emit;self.resolve=resolve;self.editorRect=editorRect
    self.workArea=workArea;self.workIdentity=workIdentity;self.isEditorForeground=isEditorForeground
    self.isEditorContext=isEditorContext;self.bugChanceRoll=bugChanceRoll
    cat=BehaviorSprite(library:library);bug=BehaviorSprite(library:library)
    cat.foot=CGPoint(x:screen.visibleFrame.minX+180,y:screen.visibleFrame.minY+160)
    cat.view.setAccessibilityElement(true);cat.view.setAccessibilityLabel("小猫：点击或拖动可打断动作")
    bug.view.setAccessibilityElement(true);bug.view.setAccessibilityLabel("小虫：点击驱逐")
    cat.view.pressed={ [weak self] time in self?.pressed(at:time) }
    cat.view.dragged={ [weak self] delta,time in self?.dragged(delta:delta,at:time) }
    cat.view.released={ [weak self] moved in self?.released(moved:moved) }
    cat.view.preciseHitTest=true
    cat.view.hitRegion={ [weak self] point in
      guard let self else{return false}
      guard self.mode == .poop else{return true}
      let x=point.x/self.cat.view.bounds.width
      let y=point.y/self.cat.view.bounds.height
      let forwardX=self.facing == .right ? x:1-x
      return (0.40...0.78).contains(forwardX) && (0.27...0.87).contains(y)
    }
    bug.view.pressed={ [weak self] _ in self?.finishBug() }
    let timer=Timer(timeInterval:0.5,repeats:true){ [weak self] _ in self?.heartbeat() }
    RunLoop.main.add(timer,forMode:.common);statusTimer=timer
  }
  deinit { flutterTimer?.invalidate();scatterTimer?.invalidate();statusTimer?.invalidate() }
  func start() { walkNext() }
  private var activeEditor: String? {
    guard Date().timeIntervalSince(editorSeen)<4,
          let source=editorSource,isEditorForeground(source) else { return nil }
    return editor
  }
  private func clip(_ name:String,_ direction:PetFacing?=nil)->String { name+"-"+(direction ?? facing).rawValue }
  private func play(_ name:String,cycles:Int=1,to:CGPoint?=nil,rate:Double=1.0,duration:TimeInterval?=nil,blend:Bool=true,then:@escaping ()->Void = {}) {
    playMarked(name,cycles:cycles,to:to,rate:rate,duration:duration,blend:blend,marker:nil,then:then)
  }
  private func playMarked(_ name:String,cycles:Int=1,to:CGPoint?=nil,rate:Double=1.0,duration:TimeInterval?=nil,blend:Bool=true,marker:(()->Void)?,then:@escaping ()->Void = {}) {
    let g=generation
    cat.play(clip(name),cycles:cycles,to:to,rate:rate,duration:duration,blend:blend,marker:{[weak self] in
      guard let self,self.generation==g else{return};marker?()
    },then:{[weak self] in guard let self,self.generation==g else{return};then()})
  }
  private func begin(_ next:Mode) {
    if mode == .bug && next != .bug {lastBugEnded=Date()}
    automaticBugPending=false
    generation += 1;cat.stop();bug.stop();bug.hide();flutterTimer?.invalidate();flutterTimer=nil
    scatterTimer?.invalidate();scatterTimer=nil;scatterRemaining=0;scatterOwner=nil;scatterURI=nil
    poopClickPending=false
    scaredHeading=nil
    protectedSleep=false;pendingRestAction=nil
    lickPausePending=false
    if mode == .rubbish { releaseHeap() }
    if next != .dragged {grabbedHeap?.orderOut(nil);grabbedHeap=nil}
    buryID=nil;buryOwner=nil;buryAnchor=nil
    cleanupOwner=nil;cleanupURI=nil
    mode=next
    // While the cat is buried in the heap, most of its sprite is transparent
    // and alpha hit-testing leaves only a tiny tail-sized target. The heap
    // panel is the visible interaction surface for this state, so accept the
    // full cat panel until the drag begins and normal precise hit-testing is
    // restored by the dragged state.
    cat.view.preciseHitTest = next != .rubbish
    cat.panel.ignoresMouseEvents=next == .scared
  }
  private func clamp(_ point:CGPoint)->CGPoint {
    let r=workArea()
    guard r.width > 240,r.height > 180 else { return point }
    return CGPoint(x:min(r.maxX-72,max(r.minX+72,point.x)),
                   y:min(r.maxY-100,max(r.minY+28,point.y)))
  }
  private func randomPoint()->CGPoint {
    let r=workArea()
    guard r.width > 240,r.height > 180 else { return cat.foot }
    return clamp(CGPoint(x:CGFloat.random(in:r.minX...r.maxX),y:CGFloat.random(in:r.minY...r.maxY)))
  }
  private func distance(_ a:CGPoint,_ b:CGPoint)->CGFloat { hypot(a.x-b.x,a.y-b.y) }
  private func turn(to direction:PetFacing,running:Bool=false,then:@escaping ()->Void) {
    guard direction != facing else{then();return}
    facing=direction
    play((running ? "run-turn-":"turn-")+(Bool.random() ? "in":"out"),rate:running ? BehaviorPolicy.scaredTransitionRate : 1.0,then:then)
  }
  private func travel(to target:CGPoint,gait:String="walk",then:@escaping ()->Void) {
    let destination=clamp(target)
    let direction:PetFacing=destination.x<cat.foot.x ? .left:.right
    turn(to:direction,running:gait=="run") { [weak self] in
      guard let self,let c=self.library.clips[self.clip(gait)] else{return}
      let distance=self.distance(self.cat.foot,destination)
      let timing=BehaviorPolicy.travel(distance:distance,stride:c.stride,cycle:c.duration)
      let duration=gait == "run" ? BehaviorPolicy.scaredTravelDuration(distance:distance) : nil
      self.play(gait,cycles:timing.cycles,to:destination,rate:gait == "run" ? BehaviorPolicy.scaredRunRate : 1.0,duration:duration,then:then)
    }
  }
  private func walkNext() {
    mode = .walk
    if testMode {play("walk");return}
    let target=randomPoint()
    travel(to:target) { [weak self] in
      guard let self else{return}
      if Date().timeIntervalSince(self.lastMischief)>30,Int.random(in:0..<3)==0 {
        self.lastMischief=Date();Bool.random() ? self.poop():self.rubbish()
      } else { self.rest() }
    }
  }
  func rest(roll:Double = Double.random(in:0..<1)) {
    requestAction { [weak self] in
      guard let self else{return};self.begin(.rest)
      let choice=BehaviorPolicy.rest(roll:roll)
      self.restExit=choice == .sleep ? "sleep-up":"sit-up"
      self.protectedSleep=choice == .sleep
      self.play(choice == .sleep ? "sleep-down":"sit-down",blend:false) { [weak self] in
        guard let self else{return}
        switch choice {
        case .sit:
          self.playSeatedRest(remaining:Int.random(in:2...3))
        case .lick:
          self.playLick(remaining:Int.random(in:2...4))
        case .sleep:
          self.play("sleep",cycles:Int.random(in:3...5),blend:false) { [weak self] in self?.leaveRest() }
        }
      }
    }
  }
  private func playSeatedRest(remaining:Int) {
    // Each clip includes the forward and reverse tail motion. Keep moving
    // throughout rest, and finish on a complete cycle if another action arrives.
    play("sit",blend:false) { [weak self] in
      guard let self,self.mode == .rest else{return}
      if remaining <= 1 || self.pendingRestAction != nil {self.leaveRest();return}
      self.playSeatedRest(remaining:remaining-1)
    }
  }
  private func playLick(remaining:Int) {
    play("lick",blend:false) { [weak self] in
      guard let self,self.mode == .rest else{return}
      if remaining <= 1 || self.pendingRestAction != nil {self.leaveRest();return}
      self.lickPausePending=true
      // Keep a moving seated pose between lick cycles instead of leaving the
      // last lick frame on screen during the inter-cycle pause.
      self.play("sit",blend:false) { [weak self] in
        guard let self,self.mode == .rest,self.lickPausePending else{return}
        self.lickPausePending=false
        self.playLick(remaining:remaining-1)
      }
    }
  }
  private func leaveRest() {
    protectedSleep=false
    let action=pendingRestAction;pendingRestAction=nil
    play(restExit,blend:false) { [weak self] in
      guard let self else{return};self.mode = .walk
      if let action { action() } else { self.walkNext() }
    }
  }
  private func requestAction(_ action:@escaping ()->Void) {
    if mode == .rest {
      pendingRestAction=action
      // Finish breathing/sitting/licking at the current complete sequence.
      if lickPausePending {lickPausePending=false;leaveRest()}
      return
    }
    if mode == .poop {startPoopEscape();return}
    action()
  }
  private func request(_ operation:String,payload:[String:Any]=[:],owner:String?=nil,then:@escaping ([String:Any])->Void) {
    guard let target=owner ?? activeEditor else{then(["ok":false,"offline":true]);return}
    let id=UUID().uuidString;requests[id]=then;requestOwners[id]=target
    var body=payload;body["target"]=target;body["requestId"]=id;body["operation"]=operation
    body["issuedAt"]=Date().timeIntervalSince1970*1000
    emit("behavior.request",body)
    DispatchQueue.main.asyncAfter(deadline:.now()+3){ [weak self] in
      self?.requestOwners.removeValue(forKey:id)
      self?.requests.removeValue(forKey:id)?(["ok":false,"timeout":true])
    }
  }
  private func positionPayload(_ point:CGPoint)->[String:Any] {
    let r=editorRect()
    return ["xRatio":min(1,max(0,(point.x-r.minX)/max(1,r.width))),"yRatio":min(1,max(0,(r.maxY-point.y)/max(1,r.height)))]
  }
  func handle(type:String,payload:[String:Any],source:String) {
    // Old installed hosts cannot acknowledge the current request protocol.
    if source == "vscode-extension",payload["clientId"] as? String == nil { return }
    let owner=payload["clientId"] as? String ?? source
    if ["vscode-extension","obsidian-plugin"].contains(source),payload["active"] as? Bool == true {
      if editor != owner { editorURI=nil }
      editor=owner;editorSource=source;editorSeen=Date()
      if let uri=payload["uri"] as? String ?? (payload["anchor"] as? [String:Any])?["uri"] as? String { editorURI=uri }
    }
    if type=="behavior.response",let id=payload["requestId"] as? String {
      guard requestOwners[id]==owner else{return}
      requestOwners.removeValue(forKey:id);requests.removeValue(forKey:id)?(payload);return
    }
    if type=="editor.textChanged" {
      guard isEditorForeground(source) else { return }
      guard let anchor=payload["anchor"] as? [String:Any],let point=resolve(anchor) else{return}
      let now=Date();lastTyping=now
      bugFacing=payload["direction"] as? String == "left" ? .left:.right
      if mode == .bug {
        bugWaypoint=clampBug(CGPoint(x:point.x+200*bugFacing.sign,y:point.y+28))
        bugInputUntil=now.addingTimeInterval(0.8)
        flyBug();return
      }
      // The insect's visible body sits above its foot anchor. Keep its x
      // directly over the latest insertion point, including queued rest exits.
      let spawn=bugSpawnPoint(above:point)
      if automaticBugPending {bugTarget=spawn;return}
      guard (mode == .walk || mode == .rest),!automaticBugPending,
            now.timeIntervalSince(lastBugEnded)>=BehaviorPolicy.bugCooldown,
            now.timeIntervalSince(lastTypingBugCheck)>=BehaviorPolicy.typingBugInterval else{return}
      lastTypingBugCheck=now
      guard bugChanceRoll()<BehaviorPolicy.typingBugChance else{return}
      bugTarget=spawn
      queueAutomaticBug(fromTyping:true)
    } else if type=="behavior.anchors",let anchors=payload["anchors"] as? [[String:Any]],mode == .rubbish {
      if let id=heapID,let a=anchors.first(where:{$0["id"] as? String==id}),let p=rubbishPoint(a) {
        heapAnchor=a;placeHeap(p)
        if cat.clipName.hasPrefix("rubbish-tail") { cat.foot=p }
      } else if heapOwner==owner { begin(.walk);walkNext() }
    } else if type=="behavior.anchors",mode == .bury,owner==buryOwner,let id=buryID {
      let anchors=payload["anchors"] as? [[String:Any]] ?? []
      if let a=anchors.first(where:{$0["id"] as? String==id}),let p=resolve(a) {
        buryAnchor=a
        if cat.clipName.hasPrefix("bury-") {cat.foot=p}
      }
    } else if type=="pet.actionRequested" {
      if payload["debug"] as? Bool == true,let action=payload["action"] as? String {
        performDebugAction(action);return
      }
      switch payload["action"] as? String {
      case "poopChaos":poop()
      case "boxDive","rubbish":rubbish()
      case "bugChase":chase()
      case "clear":clearAll()
      case "bury":bury()
      case "scatter":clicked()
      case "calm":rest()
      default:break
      }
    }
  }
  // Manual menu/command actions take effect immediately, even during a
  // protected rest sequence. Opening the status menu must not lose its editor.
  func performDebugAction(_ action:String) {
    guard ["poopChaos","boxDive","rubbish","bugChase","calm","bury","clear"].contains(action) else{return}
    if action == "clear" {clearAll();return}
    begin(.walk);lastMischief=Date()
    if editor != nil {editorSeen=Date()}
    switch action {
    case "poopChaos":poop()
    case "boxDive","rubbish":rubbish()
    case "bugChase":chase()
    case "calm":rest()
    case "bury":bury()
    default:break
    }
  }
  func clearAll() {
    cleanupVersion += 1;begin(.walk);lastMischief=Date()
    dragLifted=false;dragOwner=nil;dragURI=nil
    localDirt.forEach{$0.panel.orderOut(nil)};localDirt.removeAll()
    // Broadcast to every connected editor, including inactive windows. The
    // cutoff also cancels insert requests that arrive after this cleanup.
    emit("cleanup.requested",["scope":"all","requestId":UUID().uuidString,"cutoff":Date().timeIntervalSince1970*1000])
    walkNext()
  }
  func chase() {
    bugTarget=clamp(CGPoint(x:cat.foot.x+170*facing.sign,y:cat.foot.y+70))
    requestAction { [weak self] in self?.startBug() }
  }
  private func startBug() {
    begin(.bug);bugStarted=Date();bugEscaping=false
    pouncesUntilRoll=Int.random(in:1...3)
    bug.foot=bugTarget;flyBug()
    chooseBugWaypoint()
    var lastTick=ProcessInfo.processInfo.systemUptime
    let clockSpeed=max(0.1,Double(ProcessInfo.processInfo.environment["CHAOS_CAT_TEST_SPEED"] ?? "1") ?? 1)
    let timer=Timer(timeInterval:1.0/30,repeats:true){ [weak self] _ in
      guard let self,self.mode == .bug else{return}
      let elapsed=Date().timeIntervalSince(self.bugStarted)
      if elapsed>=BehaviorPolicy.bugLifetime { self.finishBug();return }
      let now=ProcessInfo.processInfo.systemUptime
      let dt=min(0.05,now-lastTick)*clockSpeed;lastTick=now
      self.advanceBug(by:dt,elapsed:elapsed)
    }
    RunLoop.main.add(timer,forMode:.common);flutterTimer=timer
    if distance(cat.foot,chaseDestination())>BehaviorPolicy.catchRadius {
      chaseStep()
    } else {play("chase-enter") { [weak self] in self?.chaseStep() }}
  }
  private func bugSpawnPoint(above point:CGPoint)->CGPoint {
    clampBug(CGPoint(x:point.x,y:point.y+28))
  }
  private func clampBug(_ point:CGPoint)->CGPoint {
    let r=workArea()
    guard r.width>80,r.height>100 else{return point}
    return CGPoint(x:min(r.maxX-24,max(r.minX+24,point.x)),
                   y:min(r.maxY-44,max(r.minY+24,point.y)))
  }
  private func chooseBugWaypoint() {
    var target=clampBug(CGPoint(x:bugTarget.x+CGFloat.random(in:180...300)*bugFacing.sign,
                             y:bugTarget.y+CGFloat.random(in:-80...80)))
    if abs(target.x-bugTarget.x)<70 {
      bugFacing=bugFacing == .right ? .left:.right
      target=clampBug(CGPoint(x:bugTarget.x+220*bugFacing.sign,y:bugTarget.y+CGFloat.random(in:-80...80)))
    }
    bugWaypoint=target;flyBug()
  }
  private func advanceBug(by dt:Double,elapsed:Double) {
    var d=distance(bugTarget,bugWaypoint)
    if d<8 {chooseBugWaypoint();d=distance(bugTarget,bugWaypoint)}
    if Date()>bugInputUntil,abs(bugWaypoint.x-bugTarget.x)>8 {
      let direction:PetFacing=bugWaypoint.x<bugTarget.x ? .left:.right
      if direction != bugFacing {bugFacing=direction;flyBug()}
    }
    if d>0 {
      let step=min(d,CGFloat(dt)*(bugEscaping ? BehaviorPolicy.bugEscapeSpeed:BehaviorPolicy.bugFlightSpeed))
      bugTarget=clampBug(CGPoint(x:bugTarget.x+(bugWaypoint.x-bugTarget.x)*step/d,
                              y:bugTarget.y+(bugWaypoint.y-bugTarget.y)*step/d))
    }
    bug.foot=clampBug(CGPoint(x:bugTarget.x+sin(elapsed*6)*6,y:bugTarget.y+cos(elapsed*8)*8))
  }
  private func queueAutomaticBug(fromTyping:Bool) {
    automaticBugPending=true
    let window=workIdentity()
    requestAction { [weak self] in
      guard let self else{return}
      self.automaticBugPending=false
      let valid=fromTyping ? Date().timeIntervalSince(self.lastTyping)<3 && self.activeEditor != nil
        : self.activeEditor == nil && !self.isEditorContext()
      guard self.workIdentity()==window,valid else{self.walkNext();return}
      self.startBug()
    }
  }
  func checkAmbientBug(at now:Date = Date()) {
    guard now.timeIntervalSince(lastAmbientBugCheck)>=BehaviorPolicy.ambientBugInterval else{return}
    lastAmbientBugCheck=now
    guard activeEditor == nil,!isEditorContext(),!automaticBugPending,
          mode == .walk || mode == .rest,
          now.timeIntervalSince(lastBugEnded)>=BehaviorPolicy.bugCooldown,
          bugChanceRoll()<BehaviorPolicy.ambientBugChance else{return}
    bugTarget=randomPoint();bugFacing=Bool.random() ? .left:.right
    queueAutomaticBug(fromTyping:false)
  }
  private func flyBug(repeatCycle:Bool=false) {
    guard mode == .bug else{return}
    let phase=bugEscaping ? "bug-escape":"bug-fly"
    let name=clip(phase,bugFacing)
    if !repeatCycle && bug.panel.isVisible && bug.clipName.hasPrefix(phase) {
      if bug.clipName != name {bug.switchVariant(name)}
      return
    }
    bug.play(name,then:{[weak self] in self?.flyBug(repeatCycle:true)})
  }
  private func chaseDestination()->CGPoint {
    clamp(CGPoint(x:bugTarget.x-45*facing.sign,y:bugTarget.y-65))
  }
  private func chaseStep() {
    guard mode == .bug else{return}
    // Follow the fly's moving center without reacting to each wingbeat/bob.
    let dx=bugTarget.x-cat.foot.x
    let direction:PetFacing=abs(dx)<35 ? facing : dx<0 ? .left:.right
    turn(to:direction) { [weak self] in
      guard let self,self.mode == .bug else{return}
      let near=self.distance(self.cat.foot,self.chaseDestination())<=BehaviorPolicy.pounceApproachRadius+0.5
      self.bugEscaping=near;self.flyBug()
      if near {
        // Both clips begin together. Escape finishes just before the pounce lands.
        self.play("catch",to:self.chaseDestination()) { [weak self] in
          guard let self,self.mode == .bug else{return}
          self.pouncesUntilRoll -= 1
          if self.pouncesUntilRoll == 0 { self.rollAfterPounce() }
          else { self.shortChaseBetweenPounces() }
        }
      } else {
        self.approachBug()
      }
    }
  }
  private func approachBug() {
    // Keep one running playback across stride boundaries. The foot advances
    // every display tick and retargets without resetting the gait or blending
    // its first pose over the last pose of every cycle.
    let gait="chase-run"
    play(gait,cycles:Int.max,blend:false)
    let c=library.clips[clip(gait)]!
    let runSpeed=CGFloat(c.stride/c.duration)
    let g=generation
    let clockSpeed=max(0.1,Double(ProcessInfo.processInfo.environment["CHAOS_CAT_TEST_SPEED"] ?? "1") ?? 1)
    var lastTick=ProcessInfo.processInfo.systemUptime
    cat.onTick={ [weak self] _ in
      guard let self,self.mode == .bug,self.generation==g else{return}
      let now=ProcessInfo.processInfo.systemUptime
      let dt=min(0.05,now-lastTick)*clockSpeed;lastTick=now
      let target=self.chaseDestination(),d=self.distance(self.cat.foot,target)
      if d<=BehaviorPolicy.pounceApproachRadius+0.5 || (self.bugTarget.x-self.cat.foot.x)*self.facing.sign < -35 {
        self.cat.onTick=nil;self.chaseStep();return
      }
      let step=min(d-BehaviorPolicy.pounceApproachRadius,runSpeed*CGFloat(dt))
      self.cat.foot=self.clamp(CGPoint(x:self.cat.foot.x+(target.x-self.cat.foot.x)*step/d,
                                     y:self.cat.foot.y+(target.y-self.cat.foot.y)*step/d))
    }
  }
  private func shortChaseBetweenPounces() {
    guard mode == .bug else{return}
    let dx=bugTarget.x-cat.foot.x
    let direction:PetFacing=abs(dx)<35 ? facing : dx<0 ? .left:.right
    turn(to:direction) { [weak self] in
      guard let self,self.mode == .bug else{return}
      let target=self.chaseDestination(),d=self.distance(self.cat.foot,target)
      let step=min(60,d)
      let next=d>0 ? self.clamp(CGPoint(x:self.cat.foot.x+(target.x-self.cat.foot.x)*step/d,
                                      y:self.cat.foot.y+(target.y-self.cat.foot.y)*step/d)) : self.cat.foot
      // One short walking pursuit separates every pair of pounces. Distant
      // targets may require the sprint again, but never skip this small step.
      self.play("chase",to:next,rate:1.2,blend:false) { [weak self] in self?.chaseStep() }
    }
  }
  private func rollAfterPounce() {
    guard mode == .bug else{return}
    bugEscaping=true;flyBug()
    let landing=clamp(CGPoint(x:cat.foot.x+50*facing.sign,y:cat.foot.y))
    play("chase-roll",to:landing) { [weak self] in
      guard let self,self.mode == .bug else{return}
      let stride=CGFloat(self.library.clips[self.clip("chase-recover")]?.stride ?? 178)
      let destination=self.clamp(CGPoint(x:self.cat.foot.x+stride*self.facing.sign,y:self.cat.foot.y))
      self.play("chase-recover",to:destination,blend:false) { [weak self] in
        guard let self,self.mode == .bug else{return}
        self.pouncesUntilRoll=Int.random(in:1...3)
        self.shortChaseBetweenPounces()
      }
    }
  }
  private func finishBug() {
    guard mode == .bug else{return};lastBugEnded=Date();begin(.walk)
    play("chase-exit") { [weak self] in self?.walkNext() }
  }
  func rubbish() { requestAction { [weak self] in self?.startRubbish() } }
  private func startRubbish() {
    begin(.rubbish);let g=generation;let owner=activeEditor
    request("rubbish.create",payload:["random":true],owner:owner) { [weak self] response in
      guard let self else{return}
      if self.generation != g || (owner != nil && owner != self.activeEditor) {
        if let id=response["id"] as? String { self.request("marker.remove",payload:["id":id],owner:owner){_ in} }
        if self.generation == g { self.begin(.walk);self.walkNext() }
        return
      }
      var point=self.clamp(CGPoint(x:self.cat.foot.x+250*self.facing.sign,y:self.cat.foot.y))
      if response["ok"] as? Bool == true,let a=response["anchor"] as? [String:Any],let p=self.rubbishPoint(a) {
        self.heapID=response["id"] as? String;self.heapOwner=owner;self.heapAnchor=a;point=p
      } else if response["offline"] as? Bool != true { self.begin(.walk);self.walkNext();return }
      self.showHeap(point)
      // Approach with default walk until the 320-point discovery radius.
      let d=self.distance(self.cat.foot,point)
      if d>BehaviorPolicy.rubbishRadius {
        let fraction=(d-280)/d
        let approach=CGPoint(x:self.cat.foot.x+(point.x-self.cat.foot.x)*fraction,y:self.cat.foot.y+(point.y-self.cat.foot.y)*fraction)
        self.travel(to:approach){[weak self] in self?.dive()}
      } else { self.dive() }
    }
  }
  private func rubbishPoint(_ anchor:[String:Any])->CGPoint? {
    guard let point=resolve(anchor) else{return nil}
    let lineHeight=CGFloat(anchor["lineHeight"] as? Double ?? 21)
    return CGPoint(x:point.x,y:point.y+lineHeight+18)
  }
  private var heapScale:CGFloat { CGFloat(library.clips["rubbish-tail-right"]?.scale ?? 0.19036) }
  private func heapPoint()->CGPoint? {
    if let a=heapAnchor { return rubbishPoint(a) }
    return heap.map { panel in
      CGPoint(x:panel.frame.minX+800*heapScale,
              y:panel.frame.minY+(panel.contentView?.bounds.height ?? panel.frame.height)-900*heapScale)
    }
  }
  private func rubbishDirection(to point:CGPoint)->PetFacing {
    let preferred:PetFacing=point.x<cat.foot.x ? .left:.right
    let area=workArea(),minimum=BehaviorPolicy.rubbishTakeoffDistance+BehaviorPolicy.rubbishRunway
    let leftRoom=point.x-(area.minX+72),rightRoom=(area.maxX-72)-point.x
    if preferred == .right && leftRoom<minimum && rightRoom>leftRoom {return .left}
    if preferred == .left && rightRoom<minimum && leftRoom>rightRoom {return .right}
    return preferred
  }
  private func dive() {
    guard mode == .rubbish,let point=heapPoint() else{begin(.walk);walkNext();return}
    let direction=rubbishDirection(to:point)
    turn(to:direction){ [weak self] in
      guard let self,let point=self.heapPoint() else{return}
      let staging=self.clamp(BehaviorPolicy.rubbishStaging(heap:point,facing:direction))
      if (point.x-staging.x)*direction.sign < BehaviorPolicy.rubbishTakeoffDistance+50 {
        self.begin(.walk);self.walkNext();return
      }
      self.showHeap(point)
      let forward=(point.x-self.cat.foot.x)*direction.sign
      let tooClose=forward<BehaviorPolicy.rubbishTakeoffDistance+50
      if tooClose || self.distance(self.cat.foot,point)>BehaviorPolicy.rubbishRadius ||
          !BehaviorPolicy.canDive(distance:self.distance(self.cat.foot,point),facing:self.facing,required:direction) {
        self.travel(to:staging){[weak self] in self?.dive()};return
      }
      self.play("rubbish-discover") { [weak self] in
        guard let self,let current=self.heapPoint() else{return}
        let runEnd=self.clamp(BehaviorPolicy.rubbishTakeoff(heap:current,facing:self.facing))
        self.travel(to:runEnd,gait:"rubbish-run") { [weak self] in
          guard let self,let current=self.heapPoint() else{return}
          let updated=BehaviorPolicy.rubbishTakeoff(heap:current,facing:self.facing)
          if self.distance(self.cat.foot,updated)>18 {self.dive();return}
          self.play("rubbish-jump",to:current){[weak self] in self?.wagTail()}
        }
      }
    }
  }
  private func wagTail() {
    guard mode == .rubbish else{return}
    if let p=heapPoint(){cat.foot=p}
    play("rubbish-tail"){[weak self] in self?.wagTail()}
  }
  private func prop(image:NSImage?,point:CGPoint,size:CGSize,front:Bool)->NSPanel {
    let p=NSPanel(contentRect:CGRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.ignoresMouseEvents=false
    p.level=NSWindow.Level(rawValue:cat.panel.level.rawValue+(front ? 1:-1))
    p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
    let v=BehaviorSpriteView(frame:CGRect(origin:.zero,size:size))
    v.image=image
    v.imageRect=CGRect(origin:.zero,size:size)
    v.setAccessibilityElement(true);v.setAccessibilityLabel("垃圾堆：点击拖动小猫")
    v.pressed={ [weak self, weak p] time in
      guard let self,self.mode == .rubbish,self.heap === p else{return}
      self.grabbedHeap=p
      self.pressed(at:time,fromHeap:true)
    }
    v.dragged={ [weak self] delta,time in self?.dragged(delta:delta,at:time) }
    v.released={ [weak self] moved in self?.released(moved:moved) }
    p.contentView=v
    p.setFrameOrigin(CGPoint(x:point.x-size.width/2,y:point.y-(v.bounds.height-size.height*0.9)))
    p.orderFrontRegardless();return p
  }
  private func showHeap(_ point:CGPoint) {
    heap?.orderOut(nil)
    let name=facing == .left ? "rubbish-left.png":"rubbish.png"
    heap=prop(image:NSImage(contentsOf:library.directory.appendingPathComponent(name)),point:point,
              size:CGSize(width:1600*heapScale,height:1000*heapScale),front:true)
  }
  private func showLocalPoop(at point: CGPoint) {
    let id=UUID().uuidString
    let size=CGSize(width:56,height:44)
    let panel=LocalPoopPanel(contentRect:CGRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false;panel.ignoresMouseEvents=false
    // Keep the marker above the cat so a click on a pile at the cat's feet
    // reaches the marker view instead of the sprite panel underneath.
    panel.level=NSWindow.Level(rawValue:cat.panel.level.rawValue+1)
    panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
    let view=LocalPoopView(frame:CGRect(origin:.zero,size:size))
    view.setAccessibilityElement(true)
    view.setAccessibilityLabel("桌面屎：点击清除")
    view.image=NSImage(contentsOf:library.directory.appendingPathComponent("poop.png"))
    view.imageScaling = .scaleProportionallyUpOrDown
    view.clicked={ [weak self, weak panel] in
      panel?.orderOut(nil)
      self?.localDirt.removeAll{$0.id==id}
    }
    panel.contentView=view
    panel.setFrameOrigin(CGPoint(x:point.x-size.width/2,y:point.y-13));panel.orderFrontRegardless()
    let area=workArea()
    let relative=CGPoint(x:(point.x-area.minX)/max(1,area.width),y:(point.y-area.minY)/max(1,area.height))
    localDirt.append((id,point,panel,workIdentity(),relative))
  }
  private func placeHeap(_ point:CGPoint) { heap?.setFrameOrigin(CGPoint(x:point.x-144,y:point.y-18)) }
  private func releaseHeap() {
    if heap === grabbedHeap {
      (heap?.contentView as? BehaviorSpriteView)?.image=nil
    } else { heap?.orderOut(nil) }
    heap=nil;heapAnchor=nil
    if let id=heapID { request("marker.remove",payload:["id":id],owner:heapOwner){_ in} }
    heapID=nil;heapOwner=nil
  }
  func poop() { requestAction { [weak self] in
    guard let self else{return}
    let owner=self.activeEditor,uri=self.editorURI
    self.begin(.poop);self.poopRound(0,owner:owner,uri:uri)
  } }
  private func poopRound(_ round:Int,owner:String?,uri:String?) {
    guard mode == .poop else{return}
    if round>=BehaviorPolicy.poopRounds { begin(.walk);walkNext();return }
    let g=generation,cleanupAtStart=cleanupVersion
    var target=positionPayload(cat.foot);if let uri,owner != nil {target["anchor"]=["uri":uri]}
    request("target.pick",payload:target,owner:owner) { [weak self] response in
      guard let self,self.generation==g else{return}
      guard response["ok"] as? Bool == true || response["offline"] as? Bool == true else{self.begin(.walk);self.walkNext();return}
      let currentOwner=self.activeEditor
      let anchor=owner == currentOwner ? response["anchor"] as? [String:Any] : nil
      let point=anchor.flatMap(self.resolve).map(self.clamp) ?? self.clamp(self.cat.foot)
      let catPoint=self.clamp(CGPoint(x:point.x+60*self.facing.sign,y:point.y))
      self.travel(to:catPoint) { [weak self] in
        guard let self else{return}
        self.playMarked("poop",marker:{[weak self] in
          guard let self else{return}
          var data=self.positionPayload(point);if let anchor {data["anchor"]=anchor}
          // An active editor can still be outside the current desktop target.
          // In that case keep the marker native so it does not get inserted at
          // a misleading clamped editor coordinate.
          guard let owner,owner == self.activeEditor,self.editorRect().contains(point) else {
            self.showLocalPoop(at:point)
            return
          }
          self.request("poop.create",payload:data,owner:owner) { [weak self] r in
            guard let self else{return}
            if self.cleanupVersion != cleanupAtStart,
               let id=r["id"] as? String {
              self.request("marker.remove",payload:["id":id],owner:owner){_ in}
            }
          }
        }) { [weak self] in
          guard let self else{return}
          if round+1<BehaviorPolicy.poopRounds {
            let cycles=Int.random(in:2...4)
            let dir:PetFacing=Bool.random() ? .left:.right
            self.turn(to:dir) { [weak self] in
              guard let self else{return}
              let p=self.clamp(CGPoint(x:self.cat.foot.x+CGFloat(cycles)*68*self.facing.sign,y:self.cat.foot.y+CGFloat.random(in:-35...35)))
              self.play("walk",cycles:cycles,to:p){[weak self] in self?.poopRound(round+1,owner:owner,uri:uri)}
            }
          } else { self.poopRound(round+1,owner:owner,uri:uri) }
        }
      }
    }
  }
  func bury() { requestAction { [weak self] in
    guard let self else{return};self.startBury(owner:self.activeEditor,uri:self.editorURI)
  } }
  private func startBury(owner:String?,uri:String?) {
    begin(.bury);cleanupOwner=owner;cleanupURI=uri;buryNext()
  }
  private func buryNext() {
    let g=generation;let owner=cleanupOwner
    let payload:[String:Any]=cleanupURI.map{["anchor":["uri":$0]]} ?? [:]
    request("poop.list",payload:payload,owner:owner){[weak self] response in
      guard let self,self.generation==g else{return}
      let anchors=response["anchors"] as? [[String:Any]] ?? []
      let options=anchors.compactMap{a->([String:Any],CGPoint)? in self.resolve(a).map{(a,$0)}}
      if let (anchor,p)=options.min(by:{self.distance(self.cat.foot,$0.1)<self.distance(self.cat.foot,$1.1)}) {
        self.travel(to:p) { [weak self] in
          guard let self else{return}
          // Re-read the id after travelling; typing may have moved the marker.
          self.request("marker.locate",payload:["id":anchor["id"] ?? "","anchor":anchor],owner:owner){[weak self] r in
            guard let self,self.generation==g else{return}
            guard r["ok"] as? Bool == true,let a=r["anchor"] as? [String:Any],let current=self.resolve(a) else{self.buryNext();return}
            if self.distance(self.cat.foot,current)>24 {self.buryNext();return}
            self.cat.foot=current;self.buryID=anchor["id"] as? String;self.buryOwner=owner;self.buryAnchor=a
            self.play("bury-down") { [weak self] in
              self?.playMarked("bury",marker:{[weak self] in
                self?.request("marker.remove",payload:["id":anchor["id"] ?? ""],owner:owner){_ in}
              }){[weak self] in self?.play("bury-up"){[weak self] in self?.buryNext()}}
            }
          }
        }
      } else if let dirt=self.localDirt.first(where:{$0.window == self.workIdentity()}) {
        self.travel(to:dirt.point){[weak self] in
          self?.play("bury-down"){[weak self] in
            self?.playMarked("bury",marker:{[weak self] in
              dirt.panel.orderOut(nil);self?.localDirt.removeAll{$0.id==dirt.id}
            }){[weak self] in
              self?.play("bury-up"){[weak self] in self?.buryNext()}
            }
          }
        }
      } else { self.begin(.walk);self.walkNext() }
    }
  }
  private func scatterPoop(owner:String?,uri:String?) {
    guard mode == .scared else{return}
    scatterTimer?.invalidate()
    scatterOwner=owner;scatterURI=uri;scatterRemaining=BehaviorPolicy.scatteredPoopCount
    scheduleScatterTick()
  }
  private func scheduleScatterTick() {
    guard mode == .scared,scatterRemaining > 0 else{return}
    // The fixture accelerates the sprite clock, so scale the test timer too;
    // production keeps a visible 160 ms gap between individual markers.
    let clockSpeed=max(0.1,Double(ProcessInfo.processInfo.environment["CHAOS_CAT_TEST_SPEED"] ?? "1") ?? 1)
    let interval=BehaviorPolicy.scatterInterval/clockSpeed
    // Re-arm after each emission so a busy main loop cannot catch up with a
    // burst of missed repeating-timer ticks.
    let timer=Timer(timeInterval:interval,repeats:false){[weak self] _ in self?.scatterOne()}
    RunLoop.main.add(timer,forMode:.common);scatterTimer=timer
  }
  private func scatterOne() {
    scatterTimer=nil
    guard mode == .scared,scatterRemaining > 0 else {
      scatterTimer?.invalidate();scatterTimer=nil;return
    }
    // Pause during the stationary turn clips; drops belong to actual sprints.
    guard cat.clipName == clip("run") else {scheduleScatterTick();return}
    scatterRemaining -= 1
    if let owner=scatterOwner,owner == activeEditor,editorRect().contains(cat.foot) {
      var payload:[String:Any] = ["random":true]
      if let uri=scatterURI { payload["anchor"]=["uri":uri] }
      request("poop.create",payload:payload,owner:owner) { _ in }
    } else {
      showLocalPoop(at:clamp(cat.foot))
    }
    scheduleScatterTick()
  }
  private func startPoopEscape() {
    guard mode == .poop || (mode == .dragged && poopClickPending) else{return}
    let owner=poopClickPending ? dragOwner:activeEditor
    let uri=poopClickPending ? dragURI:editorURI
    begin(.scared)
    play("run-enter",rate:BehaviorPolicy.scaredTransitionRate){[weak self] in
      guard let self,self.mode == .scared else{return}
      // Start scattering only once the frightened run has begun. Each marker
      // is emitted on the run timer, so mouse-down and ordinary dragging add none.
      self.scatterPoop(owner:owner,uri:uri)
      self.scaredLap(0)
    }
  }
  // A command/event-level click has no mouse-up callback, so complete it as a
  // click directly. Physical mouse input goes through pressed/dragged/released
  // below and only reaches this method when no movement occurred.
  func clicked() {
    pressed()
    released(moved:false)
  }
  func pressed(at time:TimeInterval = ProcessInfo.processInfo.systemUptime,fromHeap:Bool=false) {
    guard mode != .scared else{return}
    let wasPoop=mode == .poop
    // Retain the original editor across a long drag and the cleanup walk.
    dragOwner=cleanupOwner ?? (Date().timeIntervalSince(editorSeen)<120 ? editor:nil)
    dragURI=cleanupURI ?? editorURI
    dragGesture.start(at:time);dragLifted=false
    // Freeze the old pose while distinguishing a click from a drag. Holding
    // the mouse must not allow the old poop animation to insert more markers.
    begin(.dragged)
    poopClickPending=wasPoop
    // The supplied interaction starts on mouse-down: show the lift immediately
    // and let subsequent motion only update the held position.
    dragLifted=true
    if fromHeap {
      play("drag",cycles:Int.max)
      return
    }
    play("drag-enter",rate:BehaviorPolicy.dragLiftRate) { [weak self] in
      guard let self,self.mode == .dragged else{return}
      self.play("drag",cycles:Int.max)
    }
  }
  private func finishHeapClick() {
    begin(.dragged)
    playDragLanding { [weak self] in
      guard let self else{return}
      self.begin(.walk);self.walkNext()
    }
  }
  private func playDragLanding(then:@escaping ()->Void) {
    play("drag-exit") { [weak self] in
      guard let self,self.mode == .dragged else{return}
      self.play("sit-up",then:then)
    }
  }
  private func dragged(delta:CGPoint,at time:TimeInterval) {
    guard mode == .dragged else{return}
    dragGesture.record(delta:delta,at:time)
    poopClickPending=false
    if abs(delta.x)>1 {
      let next=delta.x<0 ? PetFacing.left:PetFacing.right
      if next != facing {
        facing=next
        // The cat is already being held. A direction change only swaps the
        // suspended hold clip; replaying the lift makes one continuous drag
        // look like a sequence of fresh mouse-downs.
        play("drag",cycles:Int.max)
      }
    }
    if !dragLifted {
      dragLifted=true
      begin(.dragged)
      play("drag-enter",rate:BehaviorPolicy.dragLiftRate) { [weak self] in
        guard let self,self.mode == .dragged else{return}
        self.play("drag",cycles:Int.max)
      }
    }
    cat.foot=clamp(CGPoint(x:cat.foot.x+delta.x,y:cat.foot.y+delta.y))
  }
  private func released(moved:Bool) {
    guard mode == .dragged else{return}
    let fromHeap=grabbedHeap != nil
    grabbedHeap?.orderOut(nil);grabbedHeap=nil
    if fromHeap && !moved {
      finishHeapClick()
      return
    }
    if poopClickPending && !moved {
      startPoopEscape()
      return
    }
    poopClickPending=false
    let cleanup=moved && dragGesture.requestsBury
    let owner=dragOwner,uri=dragURI
    dragLifted=false
    // Invalidate the lift callback so releasing early cannot restart the hold.
    begin(.dragged)
    let finish:()->Void={ [weak self] in
      guard let self else{return}
      if cleanup {self.startBury(owner:owner,uri:uri)}
      else {self.begin(.walk);self.walkNext()}
    }
    playDragLanding(then:finish)
  }
  private func scaredLap(_ lap:Int) {
    guard mode == .scared else{return}
    if lap>=3 && scatterRemaining == 0 {play("run-exit",rate:BehaviorPolicy.scaredTransitionRate){[weak self] in
      guard let self else{return};self.begin(.walk)
      self.walkNext()
    };return}
    let frame=workArea()
    let bounds=CGRect(x:frame.minX+72,y:frame.minY+28,width:max(1,frame.width-144),height:max(1,frame.height-128))
    let target=BehaviorPolicy.scaredTarget(from:cat.foot,within:bounds,previous:scaredHeading)
    scaredHeading=CGPoint(x:target.x-cat.foot.x,y:target.y-cat.foot.y)
    travel(to:target,gait:"run"){[weak self] in self?.scaredLap(lap+1)}
  }
  private func heartbeat() {
    let currentWindow=workIdentity()
    let area=workArea()
    for index in localDirt.indices {
      let dirt=localDirt[index]
      if dirt.window == currentWindow {
        let point=CGPoint(x:area.minX+dirt.relative.x*area.width,y:area.minY+dirt.relative.y*area.height)
        localDirt[index].point=point
        dirt.panel.setFrameOrigin(CGPoint(x:point.x-dirt.panel.frame.width/2,y:point.y-18))
        if !dirt.panel.isVisible { dirt.panel.orderFrontRegardless() }
      } else if dirt.panel.isVisible { dirt.panel.orderOut(nil) }
    }
    if let previous=lastWorkIdentity,previous != currentWindow,mode != .dragged {
      lastAmbientBugCheck=Date()
      begin(.walk)
      walkNext()
    }
    lastWorkIdentity=currentWindow
    if !testMode {checkAmbientBug()}
    emit("behavior.state",["mode":mode.rawValue,"facing":facing.rawValue,"clip":cat.clipName,"x":cat.foot.x,"y":cat.foot.y,"rubbishRadius":BehaviorPolicy.rubbishRadius,"protocol":2,"build":"20261014.6","editorClient":activeEditor ?? ""])
  }
  func shutdown() { releaseHeap();grabbedHeap?.orderOut(nil);grabbedHeap=nil;emit("behavior.shutdown",[:]) }
}
