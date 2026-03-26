// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "symphony-swift",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
  ],
  products: [
    .library(name: "SymphonyShared", targets: ["SymphonyShared"]),
    .library(name: "SymphonyRuntime", targets: ["SymphonyRuntime"]),
    .library(name: "SymphonyClientUI", targets: ["SymphonyClientUI"]),
    .library(name: "SymphonyBuildCore", targets: ["SymphonyBuildCore"]),
    .library(name: "SymphonyBuildCLI", targets: ["SymphonyBuildCLI"]),
    .executable(name: "SymphonyServer", targets: ["SymphonyServer"]),
    .executable(name: "symphony-build", targets: ["symphony-build"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.21.0"),
    .package(
      url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.6.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
  ],
  targets: [
    .target(
      name: "SymphonyShared",
      path: "Sources/SymphonyShared"
    ),
    .target(
      name: "SymphonyRuntime",
      dependencies: [
        "SymphonyShared",
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
        .product(name: "Yams", package: "Yams"),
      ],
      path: "Sources/SymphonyRuntime"
    ),
    .target(
      name: "SymphonyClientUI",
      dependencies: ["SymphonyShared"],
      path: "Sources/SymphonyClientUI"
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
      name: "SymphonyServer",
      dependencies: ["SymphonyRuntime"],
      path: "Sources/SymphonyServer"
    ),
    .executableTarget(
      name: "symphony-build",
      dependencies: ["SymphonyBuildCLI"],
      path: "Sources/symphony-build"
    ),
    .testTarget(
      name: "SymphonyServerTests",
      dependencies: [
        "SymphonyRuntime",
        "SymphonyServer",
        .product(name: "HummingbirdTesting", package: "hummingbird"),
        .product(name: "HummingbirdWSTesting", package: "hummingbird-websocket"),
      ],
      path: "Tests/SymphonyServerTests"
    ),
    .testTarget(
      name: "SymphonySharedTests",
      dependencies: ["SymphonyShared"],
      path: "Tests/SymphonySharedTests"
    ),
    .testTarget(
      name: "SymphonyClientUITests",
      dependencies: ["SymphonyClientUI", "SymphonyShared"],
      path: "Tests/SymphonyClientUITests"
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
