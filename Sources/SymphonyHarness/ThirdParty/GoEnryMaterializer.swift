import Foundation

enum GoEnryHostPlatform: Equatable, Sendable {
  case macOS
  case linux
  case windows

  var goOS: String {
    switch self {
    case .macOS:
      return "darwin"
    case .linux:
      return "linux"
    case .windows:
      return "windows"
    }
  }

  static func detect() throws -> Self {
    #if os(macOS)
      return .macOS
    #elseif os(Linux)
      return .linux
    #elseif os(Windows)
      return .windows
    #else
      throw SymphonyHarnessError(
        code: "unsupported_go_enry_host_platform",
        message: "go-enry materialization is not supported on this host platform."
      )
    #endif
  }
}

enum GoEnryHostArchitecture: String, Equatable, Sendable {
  case arm64
  case amd64

  var goArch: String { rawValue }

  var macOSCCCommand: String {
    switch self {
    case .arm64:
      return "clang -arch arm64"
    case .amd64:
      return "clang -arch x86_64"
    }
  }

  static func detect() throws -> Self {
    #if arch(arm64)
      return .arm64
    #elseif arch(x86_64)
      return .amd64
    #else
      throw SymphonyHarnessError(
        code: "unsupported_go_enry_host_architecture",
        message: "go-enry materialization is not supported on this host architecture."
      )
    #endif
  }
}

enum GoEnryArchiveStrategy: Equatable, Sendable {
  case universalMacOS
  case singleHostVariant
}

struct GoEnryBuildVariant: Equatable, Sendable {
  let goOS: String
  let goArch: String
  let ccCommand: String?

  var triple: String { "\(goOS)-\(goArch)" }
}

struct GoEnryBuildPlan: Equatable, Sendable {
  let variants: [GoEnryBuildVariant]
  let archiveStrategy: GoEnryArchiveStrategy

  static func make(
    hostPlatform: GoEnryHostPlatform,
    hostArchitecture: GoEnryHostArchitecture
  ) -> Self {
    switch hostPlatform {
    case .macOS:
      let secondaryArchitecture: GoEnryHostArchitecture =
        hostArchitecture == .arm64 ? .amd64 : .arm64
      return Self(
        variants: [
          makeVariant(platform: hostPlatform, architecture: hostArchitecture),
          makeVariant(platform: hostPlatform, architecture: secondaryArchitecture),
        ],
        archiveStrategy: .universalMacOS
      )
    case .linux, .windows:
      return Self(
        variants: [makeVariant(platform: hostPlatform, architecture: hostArchitecture)],
        archiveStrategy: .singleHostVariant
      )
    }
  }

  private static func makeVariant(
    platform: GoEnryHostPlatform,
    architecture: GoEnryHostArchitecture
  ) -> GoEnryBuildVariant {
    GoEnryBuildVariant(
      goOS: platform.goOS,
      goArch: architecture.goArch,
      ccCommand: platform == .macOS ? architecture.macOSCCCommand : nil
    )
  }
}

struct GoEnryMaterialization: Sendable {
  let archivePath: URL
  let headerPath: URL
  let invocation: String
}

protocol GoEnryMaterializing {
  func materialize(workspace: WorkspaceContext) throws -> GoEnryMaterialization
}

struct GoEnryMaterializer: GoEnryMaterializing {
  private let processRunner: ProcessRunning
  private let fileManager: FileManager
  private let hostPlatform: GoEnryHostPlatform?
  private let hostArchitecture: GoEnryHostArchitecture?

  init(
    processRunner: ProcessRunning = SystemProcessRunner(),
    fileManager: FileManager = .default,
    hostPlatform: GoEnryHostPlatform? = nil,
    hostArchitecture: GoEnryHostArchitecture? = nil
  ) {
    self.processRunner = processRunner
    self.fileManager = fileManager
    self.hostPlatform = hostPlatform
    self.hostArchitecture = hostArchitecture
  }

  func materialize(workspace: WorkspaceContext) throws -> GoEnryMaterialization {
    let sourceRoot = workspace.projectRoot.appendingPathComponent("ThirdParty/go-enry", isDirectory: true)
    let sharedRoot = sourceRoot.appendingPathComponent("shared", isDirectory: true)
    let sharedEntryPoint = sharedRoot.appendingPathComponent("enry.go", isDirectory: false)
    guard
      fileManager.fileExists(atPath: sharedRoot.path),
      fileManager.fileExists(atPath: sharedEntryPoint.path)
    else {
      throw SymphonyHarnessError(
        code: "missing_go_enry_submodule",
        message:
          "The go-enry submodule is missing or not initialized at \(sourceRoot.path). Run `git submodule update --init --recursive ThirdParty/go-enry`."
      )
    }

    let artifactRoot = workspace.projectRoot.appendingPathComponent(
      ".build/vendor/go-enry",
      isDirectory: true
    )
    let libRoot = artifactRoot.appendingPathComponent("lib", isDirectory: true)
    let includeRoot = artifactRoot.appendingPathComponent("include", isDirectory: true)
    try fileManager.ensureDirectory(libRoot)
    try fileManager.ensureDirectory(includeRoot)

    let archivePath = libRoot.appendingPathComponent("libenry.a", isDirectory: false)
    let generatedHeaderPath = libRoot.appendingPathComponent("libenry.h", isDirectory: false)
    let installedHeaderPath = includeRoot.appendingPathComponent("enry.h", isDirectory: false)
    try removeIfPresent(archivePath)
    try removeIfPresent(generatedHeaderPath)
    try removeIfPresent(installedHeaderPath)

    let resolvedHostPlatform = try hostPlatform ?? GoEnryHostPlatform.detect()
    let resolvedHostArchitecture = try hostArchitecture ?? GoEnryHostArchitecture.detect()
    let buildPlan = GoEnryBuildPlan.make(
      hostPlatform: resolvedHostPlatform,
      hostArchitecture: resolvedHostArchitecture
    )

    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(
      "symphony-go-enry-\(UUID().uuidString)",
      isDirectory: true
    )
    try fileManager.ensureDirectory(temporaryRoot)
    defer {
      try? fileManager.removeItem(at: temporaryRoot)
    }

    let builtArtifacts = try buildPlan.variants.map { variant in
      let outputArchive = temporaryRoot.appendingPathComponent(
        "libenry-\(variant.triple).a",
        isDirectory: false
      )
      try buildArchive(variant: variant, outputArchive: outputArchive, sourceRoot: sourceRoot)
      return (
        variant: variant,
        archive: outputArchive,
        header: outputArchive.deletingPathExtension().appendingPathExtension("h")
      )
    }

    switch buildPlan.archiveStrategy {
    case .universalMacOS:
      let result = try processRunner.run(
        command: "/usr/bin/env",
        arguments: [
          "lipo",
          "-create",
        ] + builtArtifacts.map { $0.archive.path } + ["-output", archivePath.path],
        environment: [:],
        currentDirectory: sourceRoot
      )
      guard result.exitStatus == 0 else {
        throw SymphonyHarnessError(
          code: "go_enry_lipo_failed",
          message:
            result.combinedOutput.isEmpty
              ? "Failed to create a universal go-enry archive."
              : result.combinedOutput
        )
      }
    case .singleHostVariant:
      precondition(!builtArtifacts.isEmpty)
      try fileManager.moveItem(at: builtArtifacts[0].archive, to: archivePath)
    }

    guard fileManager.fileExists(atPath: archivePath.path) else {
      throw SymphonyHarnessError(
        code: "missing_go_enry_archive",
        message: "The go-enry build completed without producing \(archivePath.path)."
      )
    }

    precondition(!builtArtifacts.isEmpty)
    let headerArtifact = builtArtifacts[0]

    guard fileManager.fileExists(atPath: headerArtifact.header.path) else {
      throw SymphonyHarnessError(
        code: "missing_go_enry_header",
        message: "The go-enry build completed without producing \(headerArtifact.header.path)."
      )
    }

    try fileManager.moveItem(at: headerArtifact.header, to: installedHeaderPath)

    let invocation: String
    switch buildPlan.archiveStrategy {
    case .universalMacOS:
      invocation = (
        builtArtifacts.map { artifact in
          buildInvocation(variant: artifact.variant, outputArchive: artifact.archive)
        }
        + [
          ShellQuoting.render(
            command: "lipo",
            arguments: ["-create"] + builtArtifacts.map { $0.archive.path } + [
              "-output", archivePath.path,
            ]
          )
        ]
      ).joined(separator: "\n")
    case .singleHostVariant:
      invocation = builtArtifacts.map { artifact in
        buildInvocation(variant: artifact.variant, outputArchive: artifact.archive)
      }.joined(separator: "\n")
    }

    return GoEnryMaterialization(
      archivePath: archivePath,
      headerPath: installedHeaderPath,
      invocation: invocation
    )
  }

  private func removeIfPresent(_ url: URL) throws {
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  private func buildArchive(
    variant: GoEnryBuildVariant,
    outputArchive: URL,
    sourceRoot: URL
  ) throws {
    var environment = [
      "CGO_ENABLED": "1",
      "GOOS": variant.goOS,
      "GOARCH": variant.goArch,
    ]
    if let ccCommand = variant.ccCommand {
      environment["CC"] = ccCommand
    }

    let result = try processRunner.run(
      command: "go",
      arguments: ["build", "-buildmode=c-archive", "-o", outputArchive.path, "./shared"],
      environment: environment,
      currentDirectory: sourceRoot
    )

    guard result.exitStatus == 0 else {
      throw SymphonyHarnessError(
        code: "go_enry_build_failed",
        message:
          result.combinedOutput.isEmpty
            ? "Failed to build the go-enry C archive for \(variant.triple)."
            : result.combinedOutput
      )
    }
  }

  private func buildInvocation(variant: GoEnryBuildVariant, outputArchive: URL) -> String {
    var environment = [
      "CGO_ENABLED=1",
      "GOOS=\(variant.goOS)",
      "GOARCH=\(variant.goArch)",
    ]
    if let ccCommand = variant.ccCommand {
      environment.append("CC=\(ShellQuoting.quote(ccCommand))")
    }
    return environment.joined(separator: " ") + " "
      + ShellQuoting.render(
        command: "go",
        arguments: ["build", "-buildmode=c-archive", "-o", outputArchive.path, "./shared"]
      )
  }
}
