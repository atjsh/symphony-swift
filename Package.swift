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
    .library(name: "SymphonyServerCore", targets: ["SymphonyServerCore"]),
    .library(name: "SymphonyServer", targets: ["SymphonyServer"]),
    .library(name: "SymphonyHarness", targets: ["SymphonyHarness"]),
    .library(name: "SymphonyHarnessCLI", targets: ["SymphonyHarnessCLI"]),
    .executable(name: "symphony-server", targets: ["SymphonyServerCLI"]),
    .executable(name: "harness", targets: ["harness"]),
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
      name: "SymphonyServerCore",
      dependencies: [
        "SymphonyShared",
        .product(name: "Yams", package: "Yams"),
      ],
      path: "Sources/SymphonyServerCore"
    ),
    .target(
      name: "SymphonyServer",
      dependencies: [
        "SymphonyShared",
        "SymphonyServerCore",
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
      ],
      path: "Sources/SymphonyServer"
    ),
    .target(
      name: "SymphonyHarness",
      dependencies: ["SymphonyShared"],
      path: "Sources/SymphonyHarness"
    ),
    .target(
      name: "SymphonyHarnessCLI",
      dependencies: [
        "SymphonyHarness",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/SymphonyHarnessCLI"
    ),
    .executableTarget(
      name: "harness",
      dependencies: ["SymphonyHarnessCLI"],
      path: "Sources/harness"
    ),
    .executableTarget(
      name: "SymphonyServerCLI",
      dependencies: ["SymphonyServer"],
      path: "Sources/SymphonyServerCLI"
    ),
    .testTarget(
      name: "SymphonyServerCoreTests",
      dependencies: ["SymphonyServerCore", "SymphonyShared"],
      path: "Tests/SymphonyServerCoreTests"
    ),
    .testTarget(
      name: "SymphonyServerTests",
      dependencies: [
        "SymphonyServer",
        "SymphonyServerCore",
        "SymphonyShared",
        .product(name: "HummingbirdTesting", package: "hummingbird"),
        .product(name: "HummingbirdWSTesting", package: "hummingbird-websocket"),
      ],
      path: "Tests/SymphonyServerTests"
    ),
    .testTarget(
      name: "SymphonyServerCLITests",
      dependencies: ["SymphonyServerCLI", "SymphonyServer", "SymphonyServerCore", "SymphonyShared"],
      path: "Tests/SymphonyServerCLITests"
    ),
    .testTarget(
      name: "SymphonySharedTests",
      dependencies: ["SymphonyShared"],
      path: "Tests/SymphonySharedTests"
    ),
    .testTarget(
      name: "SymphonyHarnessTests",
      dependencies: ["SymphonyHarness", "SymphonyShared"],
      path: "Tests/SymphonyHarnessTests"
    ),
    .testTarget(
      name: "SymphonyHarnessCLITests",
      dependencies: ["SymphonyHarnessCLI", "SymphonyHarness", "SymphonyShared"],
      path: "Tests/SymphonyHarnessCLITests"
    ),
  ]
)
