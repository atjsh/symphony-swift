// swift-tools-version: 6.2
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .standardizedFileURL
let goEnryIncludeRoot = packageRoot
  .appendingPathComponent(".build/vendor/go-enry/include", isDirectory: true)
  .path
let goEnryLibraryRoot = packageRoot
  .appendingPathComponent(".build/vendor/go-enry/lib", isDirectory: true)
  .path

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
    .library(name: "SymphonyValidationGallery", targets: ["SymphonyValidationGallery"]),
    .library(name: "SymphonyXcodeValidationServerCore", targets: ["SymphonyXcodeValidationServerCore"]),
    .executable(name: "symphony-server", targets: ["SymphonyServerCLI"]),
    .executable(name: "harness", targets: ["harness"]),
    .executable(name: "xcode-validation-server", targets: ["SymphonyXcodeValidationServerRunner"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.21.0"),
    .package(
      url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.6.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
    .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.63.2"),
  ],
  targets: [
    .target(
      name: "SymphonyShared",
      path: "Sources/SymphonyShared",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .target(
      name: "SymphonyServerCore",
      dependencies: [
        "SymphonyShared",
        .product(name: "Yams", package: "Yams"),
      ],
      path: "Sources/SymphonyServerCore",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .target(
      name: "CGoEnryBridge",
      path: "Sources/CGoEnryBridge",
      publicHeadersPath: "include",
      cSettings: [
        .unsafeFlags(["-I", goEnryIncludeRoot])
      ],
      linkerSettings: [
        .unsafeFlags(["-L", goEnryLibraryRoot, "-lenry"])
      ]
    ),
    .target(
      name: "GoEnryBridge",
      dependencies: ["CGoEnryBridge"],
      path: "Sources/GoEnryBridge"
    ),
    .target(
      name: "SymphonyServer",
      dependencies: [
        "SymphonyShared",
        "SymphonyServerCore",
        "GoEnryBridge",
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
      ],
      path: "Sources/SymphonyServer",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .target(
      name: "SymphonyHarness",
      dependencies: ["SymphonyShared"],
      path: "Sources/SymphonyHarness",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .target(
      name: "SymphonyHarnessCLI",
      dependencies: [
        "SymphonyHarness",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/SymphonyHarnessCLI",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .target(
      name: "SymphonyXcodeValidation",
      path: "Sources/SymphonyXcodeValidation",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .target(
      name: "SymphonyXcodeValidationServerCore",
      dependencies: ["SymphonyXcodeValidation"],
      path: "Sources/SymphonyXcodeValidationServerCore",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .target(
      name: "SymphonyXcodeValidationServer",
      dependencies: [
        "SymphonyXcodeValidation",
        "SymphonyXcodeValidationServerCore",
        .product(name: "Hummingbird", package: "hummingbird"),
      ],
      path: "Sources/SymphonyXcodeValidationServer",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .target(
      name: "SymphonyXcodeValidationServerCLI",
      dependencies: [
        "SymphonyXcodeValidationServer",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/SymphonyXcodeValidationServerCLI",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .target(
      name: "SymphonyValidationGallery",
      dependencies: ["SymphonyXcodeValidation"],
      path: "Sources/SymphonyValidationGallery",
      resources: [
        .copy("Resources/XcodeValidationGalleryFixture")
      ],
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .target(
      name: "SymphonyXcodeValidationCLI",
      dependencies: [
        "SymphonyXcodeValidation",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/SymphonyXcodeValidationCLI",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .executableTarget(
      name: "harness",
      dependencies: ["SymphonyHarnessCLI"],
      path: "Sources/harness"
    ),
    .executableTarget(
      name: "SymphonyXcodeValidationRunner",
      dependencies: ["SymphonyXcodeValidationCLI"],
      path: "Sources/SymphonyXcodeValidationRunner"
    ),
    .executableTarget(
      name: "SymphonyXcodeValidationServerRunner",
      dependencies: ["SymphonyXcodeValidationServerCLI"],
      path: "Sources/SymphonyXcodeValidationServerRunner"
    ),
    .executableTarget(
      name: "SymphonyServerCLI",
      dependencies: ["SymphonyServer"],
      path: "Sources/SymphonyServerCLI"
    ),
    .testTarget(
      name: "SymphonyServerCoreTests",
      dependencies: ["SymphonyServerCore", "SymphonyShared"],
      path: "Tests/SymphonyServerCoreTests",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
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
      path: "Tests/SymphonyServerTests",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .testTarget(
      name: "SymphonyServerCLITests",
      dependencies: ["SymphonyServerCLI", "SymphonyServer", "SymphonyServerCore", "SymphonyShared"],
      path: "Tests/SymphonyServerCLITests"
    ),
    .testTarget(
      name: "SymphonySharedTests",
      dependencies: ["SymphonyShared"],
      path: "Tests/SymphonySharedTests",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .testTarget(
      name: "SymphonyHarnessTests",
      dependencies: ["SymphonyHarness", "SymphonyShared"],
      path: "Tests/SymphonyHarnessTests",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .testTarget(
      name: "SymphonyHarnessCLITests",
      dependencies: ["SymphonyHarnessCLI", "SymphonyHarness", "SymphonyShared"],
      path: "Tests/SymphonyHarnessCLITests",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .testTarget(
      name: "SymphonyXcodeValidationTests",
      dependencies: ["SymphonyXcodeValidation", "SymphonyXcodeValidationCLI", "SymphonyShared"],
      path: "Tests/SymphonyXcodeValidationTests",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .testTarget(
      name: "SymphonyValidationGalleryTests",
      dependencies: ["SymphonyValidationGallery", "SymphonyXcodeValidation", "SymphonyShared"],
      path: "Tests/SymphonyValidationGalleryTests",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
    .testTarget(
      name: "SymphonyXcodeValidationServerCoreTests",
      dependencies: ["SymphonyXcodeValidationServerCore"],
      path: "Tests/SymphonyXcodeValidationServerCoreTests",
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "swiftlintplugins")]
    ),
  ]
)
