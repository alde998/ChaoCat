import AppKit
import AVFoundation
import Foundation

guard CommandLine.arguments.count == 4,
      let fps = Double(CommandLine.arguments[3]), fps > 0 else {
  fputs("usage: swift extract_drag_video.swift INPUT OUTPUT_DIR FPS\n", stderr)
  exit(2)
}

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let asset = AVURLAsset(url: source)
let duration = CMTimeGetSeconds(asset.duration)
guard duration.isFinite, duration > 0,
      let track = asset.tracks(withMediaType: .video).first else {
  fputs("No readable video track\n", stderr)
  exit(1)
}
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

print("duration=\(duration) sourceFps=\(track.nominalFrameRate) size=\(track.naturalSize)")
for index in 0..<Int(ceil(duration * fps)) {
  let time = min(duration - 0.001, Double(index) / fps)
  let image = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 60000), actualTime: nil)
  guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    throw NSError(domain: "DragVideo", code: 1)
  }
  try data.write(to: output.appendingPathComponent(String(format: "frame_%05d.png", index)))
}
print("frames=\(Int(ceil(duration * fps)))")
