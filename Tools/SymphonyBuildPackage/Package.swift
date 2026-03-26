// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SymphonyBuildPackage",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(name: "SymphonyShared", targets: ["SymphonyShared"]),
    .library(name: "SymphonyBuildCore", targets: ["SymphonyBuildCore"]),
    .library(name: "SymphonyBuildCLI", targets: ["SymphonyBuildCLI"]),
    .executable(name: "symphony-build", targets: ["symphony-build"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
  ],
  targets: [
    .target(
      name: "SymphonyShared",
      path: "Sources/SymphonyShared"
    ),
    .target(
      name: "SymphonyBuildCore",
      dependencies: ["SymphonyShared"],
      path: "Sources/SymphonyBuildCore"
    ),
    .target(
      name: "SymphonyBuildCLI",
      dependencies: [
        "SymphonyBuildCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/SymphonyBuildCLI"
    ),
    .executableTarget(
      name: "symphony-build",
      dependencies: ["SymphonyBuildCLI"],
      path: "Sources/symphony-build"
    ),
    .testTarget(
      name: "SymphonyBuildCoreTests",
      dependencies: ["SymphonyBuildCore", "SymphonyShared"],
      path: "Tests/SymphonyBuildCoreTests"
    ),
    .testTarget(
      name: "SymphonyBuildCLITests",
      dependencies: ["SymphonyBuildCLI", "SymphonyBuildCore", "SymphonyShared"],
      path: "Tests/SymphonyBuildCLITests"
    ),
  ]
)
