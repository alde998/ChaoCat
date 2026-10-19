import AppKit
import ImageIO

struct BehaviorClip: Decodable {
  let file: String
  let duration: Double
  let frames: Int
  let fps: Double
  let loop: Bool
  let stride: Double
  let width: Double
  let height: Double
  let footX: Double
  let footY: Double
  let scale: Double
  let markerTime: Double?
  let motionStart: Double?
  let frameDurations: [Double]?
  let mirrorX: Bool?
  func frame(at time: Double) -> Int {
    if let durations=frameDurations,durations.count==frames {
      var end=0.0
      for (index,duration) in durations.enumerated() {
        end += duration
        if time < end { return index }
      }
      return frames-1
    }
    return min(frames-1,Int(time*fps))
  }
}
final class BehaviorLibrary {
  let directory: URL
  let clips: [String: BehaviorClip]
  private var sources: [String: CGImageSource] = [:]
  private let cache = NSCache<NSString, NSImage>()
  init(directory: URL) throws {
    self.directory = directory
    clips = try JSONDecoder().decode([String: BehaviorClip].self, from: Data(contentsOf: directory.appendingPathComponent("catalog.json")))
    cache.totalCostLimit = 64 * 1024 * 1024
  }
  func image(_ name: String, frame: Int) -> NSImage? {
    guard let clip = clips[name] else { return nil }
    let index = min(max(0, frame), clip.frames - 1)
    let key = "\(clip.file):\(index):\(clip.mirrorX == true)" as NSString
    if let image = cache.object(forKey: key) { return image }
    // Display variants share one source and cache instead of decoding twice.
    if sources[clip.file] == nil { sources[clip.file] = CGImageSourceCreateWithURL(directory.appendingPathComponent(clip.file) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) }
    guard let source = sources[clip.file], CGImageSourceGetCount(source) > index,
          var cg = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
    if clip.mirrorX == true {
      // Integer pixel reflection at original resolution: no resampling or
      // palette changes. The returned image also drives precise hit testing.
      guard let context = CGContext(data: nil, width: cg.width, height: cg.height,
        bitsPerComponent: 8, bytesPerRow: cg.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
      context.interpolationQuality = .none
      context.translateBy(x: CGFloat(cg.width), y: 0)
      context.scaleBy(x: -1, y: 1)
      context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
      guard let mirrored = context.makeImage() else { return nil }
      cg = mirrored
    }
    let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
    return image
  }
}
final class BehaviorSpriteView: NSView {
  var image: NSImage? { didSet { if image !== oldValue { needsDisplay = true } } }
  var imageRect = CGRect.zero { didSet { needsDisplay = true } }
  var previousImage: NSImage?
  var previousImageRect = CGRect.zero
  var blend: CGFloat = 1 { didSet { if blend != oldValue { needsDisplay = true } } }
  var pressed: ((TimeInterval) -> Void)?
  var dragged: ((CGPoint, TimeInterval) -> Void)?
  var released: ((Bool) -> Void)?
  var preciseHitTest = false
  var hitRegion: ((CGPoint) -> Bool)?
  private var origin = CGPoint.zero
  private var didDrag = false
  private var trackingPress = false
  private var drawingRect: CGRect { imageRect.isEmpty ? bounds : imageRect }
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    if blend < 1 { previousImage?.draw(in: previousImageRect, from: .zero, operation: .sourceOver, fraction: 1-blend, respectFlipped: true, hints: nil) }
    image?.draw(in: drawingRect, from: .zero, operation: .sourceOver, fraction: blend, respectFlipped: true, hints: nil)
  }
  func acceptsPress(at point: CGPoint) -> Bool {
    guard bounds.contains(point) else { return false }
    guard preciseHitTest else { return true }
    let drawn=drawingRect
    guard hitRegion?(point) ?? true,
          let image,let cgImage=image.cgImage(forProposedRect:nil,context:nil,hints:nil),
          drawn.contains(point),drawn.width > 0,drawn.height > 0 else { return false }
    let x=min(cgImage.width-1,max(0,Int((point.x-drawn.minX)/drawn.width*CGFloat(cgImage.width))))
    let y=min(cgImage.height-1,max(0,Int((point.y-drawn.minY)/drawn.height*CGFloat(cgImage.height))))
    guard let pixel=cgImage.cropping(to:CGRect(x:x,y:y,width:1,height:1)) else { return false }
    var rgba=[UInt8](repeating:0,count:4)
    guard let context=CGContext(data:&rgba,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,
                                space:CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    context.draw(pixel,in:CGRect(x:0,y:0,width:1,height:1))
    return rgba[3] >= 64
  }
  override func mouseDown(with event: NSEvent) {
    trackingPress=acceptsPress(at:convert(event.locationInWindow,from:nil))
    guard trackingPress else { return }
    origin=NSEvent.mouseLocation;didDrag=false;pressed?(event.timestamp)
  }
  override func mouseDragged(with event: NSEvent) {
    guard trackingPress else { return }
    let now = NSEvent.mouseLocation
    if hypot(now.x-origin.x,now.y-origin.y)>3 { didDrag=true }
    if didDrag { dragged?(CGPoint(x: now.x-origin.x,y:now.y-origin.y),event.timestamp); origin=now }
  }
  override func mouseUp(with event: NSEvent) {
    guard trackingPress else { return }
    trackingPress=false;released?(didDrag)
  }
}
final class BehaviorSprite {
  let panel: NSPanel
  let view: BehaviorSpriteView
  let library: BehaviorLibrary
  var foot = CGPoint.zero { didSet { place() } }
  private(set) var clipName = ""
  private var clip: BehaviorClip?
  private var layout: BehaviorClip?
  private var playbackID = 0
  private let speed = max(0.1,Double(ProcessInfo.processInfo.environment["CHAOS_CAT_TEST_SPEED"] ?? "1") ?? 1)
  private var began: TimeInterval = 0
  private var cycles = 1
  private var markerFired = false
  private var completion: (() -> Void)?
  private var marker: (() -> Void)?
  private var motion: (CGPoint, CGPoint)?
  private var rate = 1.0
  private var blendsTransition = true
  private var playbackDuration: TimeInterval?
  private var timer: Timer?
  var onTick: ((Double) -> Void)?
  var onClipStart: ((String, CGPoint) -> Void)?
  init(library: BehaviorLibrary, interactive: Bool = true) {
    self.library=library
    view=BehaviorSpriteView(frame:NSRect(x:0,y:0,width:288,height:180))
    panel=NSPanel(contentRect:view.bounds,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false
    panel.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+2)
    panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
    panel.ignoresMouseEvents = !interactive;panel.contentView=view
    let timer=Timer(timeInterval:1.0/60,repeats:true){[weak self] _ in self?.tick()}
    RunLoop.main.add(timer,forMode:.common);self.timer=timer
  }
  deinit { timer?.invalidate() }
  func show() { panel.orderFrontRegardless() }
  func hide() { panel.orderOut(nil) }
  // Mirrored variants share a timeline. Turning the fly must not wait for
  // the loop boundary or restart its wingbeat on every input event.
  func switchVariant(_ name:String) {
    guard let current=clip,let next=library.clips[name],
          next.frames==current.frames,next.duration==current.duration,
          next.width==current.width,next.height==current.height else{return}
    clip=next;layout=next;clipName=name
    blendsTransition=false;view.previousImage=nil;view.blend=1
    tick()
  }
  func stop() { playbackID += 1;completion=nil;marker=nil;motion=nil;clip=nil;onTick=nil;onClipStart=nil;rate=1.0 }
  func play(_ name:String,cycles:Int=1,to:CGPoint?=nil,rate:Double=1.0,duration:TimeInterval?=nil,blend:Bool=true,marker:(()->Void)?=nil,then:(()->Void)?=nil) {
    guard let clip=library.clips[name] else { NSLog("Missing behavior clip: %@",name);then?();return }
    blendsTransition=blend
    view.previousImage=blend ? view.image : nil;view.blend=blend ? 0 : 1
    if let previous=layout {
      view.previousImageRect=CGRect(x:clip.footX*clip.scale-previous.footX*previous.scale,
                                    y:clip.footY*clip.scale-previous.footY*previous.scale,
                                    width:previous.width*previous.scale,height:previous.height*previous.scale)
    } else {view.previousImageRect=CGRect(x:0,y:0,width:clip.width*clip.scale,height:clip.height*clip.scale)}
    playbackID += 1;self.clip=clip;layout=clip;clipName=name;self.cycles=clip.loop ? max(1,cycles):1;self.rate=max(0.1,rate);began=ProcessInfo.processInfo.systemUptime;markerFired=false
    self.marker=marker;completion=then;motion=to.map{(foot,$0)};playbackDuration=duration
    onClipStart?(name,foot)
    panel.setContentSize(CGSize(width:clip.width*clip.scale,height:clip.height*clip.scale));view.frame=CGRect(origin:.zero,size:panel.contentView!.bounds.size)
    view.imageRect=CGRect(x:0,y:0,width:clip.width*clip.scale,height:clip.height*clip.scale)
    place();show();tick()
  }
  private func place() {
    guard let c=layout else { return }
    panel.setFrameOrigin(CGPoint(x:foot.x-c.footX*c.scale,y:foot.y-(view.bounds.height-c.footY*c.scale)))
  }
  private func tick() {
    guard let c=clip else{return}
    let currentID=playbackID
    let elapsed=(ProcessInfo.processInfo.systemUptime-began)*speed*rate;let total=playbackDuration ?? (c.duration*Double(cycles))
    if let (from,to)=motion {
      let start=c.motionStart ?? 0
      let p=min(1,max(0,(elapsed-start)/max(0.001,total-start)))
      foot=CGPoint(x:from.x+(to.x-from.x)*p,y:from.y+(to.y-from.y)*p)
    }
    let inCycle=elapsed.truncatingRemainder(dividingBy:c.duration)
    let frame=elapsed>=total && playbackDuration == nil ? c.frames-1 : c.frame(at:inCycle)
    view.blend=blendsTransition ? min(1,elapsed/0.08) : 1
    view.image=library.image(clipName,frame:frame)
    if !markerFired,let at=c.markerTime,elapsed>=at { markerFired=true;let action=marker;marker=nil;action?() }
    guard currentID==playbackID else{return}
    onTick?(min(1,elapsed/total))
    guard currentID==playbackID else{return}
    if elapsed>=total { let action=completion;completion=nil;marker=nil;motion=nil;clip=nil;onTick=nil;action?() }
  }
}
