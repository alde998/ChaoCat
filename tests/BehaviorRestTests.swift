import AppKit

@main struct BehaviorRestTests {
  static func main() throws {
    setenv("CHAOS_CAT_TEST","1",1)
    setenv("CHAOS_CAT_TEST_SPEED","20",1)
    NSApplication.shared.setActivationPolicy(.accessory)
    guard let screen=NSScreen.main else {
      print("Rest UI tests require a WindowServer session")
      exit(77)
    }
    let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
    let library=try BehaviorLibrary(directory:root.appendingPathComponent(ProcessInfo.processInfo.environment["CHAOS_CAT_BEHAVIOR_ASSETS"] ?? "apps/macos/Assets/Behavior"))
    let actor=BehaviorController(library:library,screen:screen,emit:{_,_ in},resolve:{_ in nil},editorRect:{.zero})
    defer {actor.shutdown();actor.cat.hide()}

    for (roll,entry,phase,exitClip,minimum,maximum) in [
      (0.3,"sit-down","sit","sit-up",2,3),
      (0.7,"sit-down","lick","sit-up",2,4),
      (0.95,"sleep-down","sleep","sleep-up",1,1)
    ] {
      actor.rest(roll:roll)
      precondition(actor.cat.clipName == entry+"-right")
      var clips=[actor.cat.clipName]
      var starts=[ProcessInfo.processInfo.systemUptime]
      actor.cat.onClipStart={name,_ in
        clips.append(name);starts.append(ProcessInfo.processInfo.systemUptime)
      }
      let deadline=Date().addingTimeInterval(6)
      while actor.mode == .rest && Date()<deadline {
        RunLoop.main.run(until:Date().addingTimeInterval(0.005))
        if actor.mode == .rest {
          precondition(actor.cat.view.image != nil,"Rest frame must decode")
          precondition(actor.cat.view.blend==1,"A disabled transition must never resurrect the preceding pose")
          precondition(actor.cat.view.previousImage == nil,"No old raised-paw pose in seated transitions")
        }
      }
      precondition(actor.mode == .walk,"Rest must finish without a static wait")
      precondition(clips[1]==phase+"-right","Each rest choice must enter its own phase directly")
      let indices=clips.indices.filter{clips[$0]==phase+"-right"}
      precondition((minimum...maximum).contains(indices.count))
      for index in indices {
        let played=starts[index+1]-starts[index]
        let cycle=library.clips[phase+"-right"]!.duration/20
        if phase == "sleep" {
          precondition(played>=cycle*3 && played<cycle*5+0.3,"Sleep must breathe for 3–5 cycles")
        } else {
          precondition(played>=cycle && played<cycle+0.3,"Seated cycles must not freeze between repetitions")
        }
      }
      if phase == "lick" {
        for pair in zip(indices,indices.dropFirst()) {
          precondition(pair.1==pair.0+2 && clips[pair.0+1]=="sit-right","Repeated licking pauses with moving tail")
        }
      }
      precondition(clips[clips.count-2]==exitClip+"-right")
      precondition(clips.last=="walk-right")
      print("PASS:",phase,clips.joined(separator:" → "))
    }
  }
}
