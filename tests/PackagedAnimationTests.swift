import AppKit
import ImageIO

@main struct PackagedAnimationTests {
  static func pixels(_ image: NSImage) -> Data {
    let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let context = CGContext(data: nil, width: cg.width, height: cg.height,
      bitsPerComponent: 8, bytesPerRow: cg.width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .none
    context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    return Data(bytes: context.data!, count: cg.width * cg.height * 4)
  }

  static func main() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let original = try BehaviorLibrary(directory: root.appendingPathComponent("apps/macos/Assets/Behavior"))
    let packaged = try BehaviorLibrary(directory: root.appendingPathComponent("apps/macos/ChaosCat.app/Contents/Resources/Assets/Behavior"))
    precondition(Set(original.clips.keys) == Set(packaged.clips.keys))
    var frames = 0
    for name in original.clips.keys.sorted() {
      let a = original.clips[name]!, b = packaged.clips[name]!
      precondition(a.frames == b.frames && a.duration == b.duration && a.fps == b.fps && a.loop == b.loop)
      precondition(a.width == b.width && a.height == b.height && a.footX == b.footX && a.footY == b.footY && a.scale == b.scale)
      precondition(a.stride == b.stride && a.markerTime == b.markerTime && a.motionStart == b.motionStart && a.frameDurations == b.frameDurations)
      for index in 0..<a.frames {
        autoreleasepool {
          guard let before = original.image(name, frame: index), let after = packaged.image(name, frame: index) else {
            preconditionFailure("Missing native frame: \(name) \(index)")
          }
          precondition(pixels(before) == pixels(after), "Native pixel mismatch: \(name) \(index)")
        }
        frames += 1
      }
      print("PASS native pixels:", name, a.frames)
    }
    let sprint = packaged.image("rubbish-run-right", frame: 0)
    precondition(sprint === packaged.image("chase-run-right", frame: 0), "Display variants should share decoded frames")
    let report: [String: Any] = ["passed": true, "clips": original.clips.count, "nativeFramesCompared": frames,
      "checks": ["Every native RGBA pixel identical", "Timing, looping, anchors, scales and markers identical", "Display variants share decoded cache"]]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: root.appendingPathComponent("exports/package-optimization/native-animation-validation.json"))
    print("PASS: \(frames) native frames across \(original.clips.count) clips, lossless package")
  }
}
