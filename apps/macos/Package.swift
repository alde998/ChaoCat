// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ChaosCatMac",
  platforms: [
    .macOS(.v13)
  ],
  targets: [
    .executableTarget(
      name: "ChaosCatMac",
      path: "Sources",
      swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
    )
  ]
)
