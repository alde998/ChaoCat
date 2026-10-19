import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Compile with swiftc -module-cache-path /tmp/chao-module-cache.
// VideoToolbox decoding may require execution outside a restricted sandbox.
guard CommandLine.arguments.count == 3 else {
  fputs("usage: extract_native_video_frames <video.mp4> <frames-directory>\n", stderr)
  exit(2)
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
guard (try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty else {
  fputs("Output directory must be empty (avoid stale frames).\n", stderr)
  exit(2)
}
let asset = AVURLAsset(url: input)
guard let track = asset.tracks(withMediaType: .video).first else {
  fputs("No video track.\n", stderr)
  exit(1)
}
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
reader.add(output)
guard reader.startReading() else { throw reader.error! }
let context = CIContext()
var timestamps: [Double] = []
while let sample = output.copyNextSampleBuffer() {
  try autoreleasepool {
    guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
      throw NSError(domain: "FrameExport", code: 1)
    }
    let image = CIImage(cvPixelBuffer: buffer).transformed(by: track.preferredTransform)
    guard let cgImage = context.createCGImage(image, from: image.extent) else {
      throw NSError(domain: "FrameExport", code: 2)
    }
    let url = directory.appendingPathComponent(String(format: "bug_%05d.png", timestamps.count))
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
      throw NSError(domain: "FrameExport", code: 3)
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "FrameExport", code: 4)
    }
    timestamps.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
  }
}
guard reader.status == .completed, !timestamps.isEmpty else {
  throw reader.error ?? NSError(domain: "FrameExport", code: 5)
}
let metadata: [String: Any] = ["source": input.path, "fps": track.nominalFrameRate,
                               "frames": timestamps.count, "timestamps": timestamps]
try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
  .write(to: directory.appendingPathComponent("frames.json"))
print("Exported \(timestamps.count) full-resolution frames at \(track.nominalFrameRate) fps")
