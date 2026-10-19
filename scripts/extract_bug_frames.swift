import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 3 else {
  FileHandle.standardError.write(Data("usage: swift scripts/extract_bug_frames.swift <input.mp4> <output-dir> [fps] [max-size]\n".utf8))
  exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDir = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let fps = Double(CommandLine.arguments.dropFirst(3).first ?? "12") ?? 12
let maxSize = Int(CommandLine.arguments.dropFirst(4).first ?? "180") ?? 180

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let asset = AVURLAsset(url: input)
let duration = CMTimeGetSeconds(asset.duration)
guard duration.isFinite, duration > 0 else {
  FileHandle.standardError.write(Data("invalid video duration\n".utf8))
  exit(1)
}

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
generator.maximumSize = CGSize(width: maxSize, height: maxSize)

let frameCount = max(1, min(72, Int(duration * fps)))
for index in 0..<frameCount {
  let seconds = min(duration - 0.001, Double(index) / fps)
  let time = CMTime(seconds: seconds, preferredTimescale: 600)
  do {
    let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
    let filename = String(format: "bug_%03d.png", index)
    let url = outputDir.appendingPathComponent(filename)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
      throw NSError(domain: "ChaosCatFrameExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"])
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "ChaosCatFrameExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not write PNG"])
    }
  } catch {
    FileHandle.standardError.write(Data("frame \(index) failed: \(error)\n".utf8))
  }
}

print("exported \(frameCount) frames to \(outputDir.path)")
