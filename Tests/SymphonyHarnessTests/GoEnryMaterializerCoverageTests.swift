import Foundation
import Testing

@testable import SymphonyHarness

// MARK: - Lipo Failure

@Test func goEnryMaterializerThrowsOnLipoFailure() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let sharedRoot = repoRoot.appendingPathComponent("ThirdParty/go-enry/shared", isDirectory: true)
    try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
    try "package main\nimport \"C\"\nfunc main() {}\n".write(
      to: sharedRoot.appendingPathComponent("enry.go"),
      atomically: true,
      encoding: .utf8
    )

    let runner = FailingLipoProcessRunner()
    let materializer = GoEnryMaterializer(
      processRunner: runner,
      fileManager: .default,
      hostPlatform: .macOS,
      hostArchitecture: .arm64
    )

    do {
      _ = try materializer.materialize(
        workspace: WorkspaceContext(
          projectRoot: repoRoot,
          buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
          xcodeWorkspacePath: nil,
          xcodeProjectPath: nil
        )
      )
      Issue.record("Expected lipo failure to throw.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "go_enry_lipo_failed")
    }
  }
}

// MARK: - Go Build Failure

@Test func goEnryMaterializerThrowsOnGoBuildFailure() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let sharedRoot = repoRoot.appendingPathComponent("ThirdParty/go-enry/shared", isDirectory: true)
    try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
    try "package main\nimport \"C\"\nfunc main() {}\n".write(
      to: sharedRoot.appendingPathComponent("enry.go"),
      atomically: true,
      encoding: .utf8
    )

    let runner = FailingGoBuildProcessRunner()
    let materializer = GoEnryMaterializer(
      processRunner: runner,
      fileManager: .default,
      hostPlatform: .linux,
      hostArchitecture: .arm64
    )

    do {
      _ = try materializer.materialize(
        workspace: WorkspaceContext(
          projectRoot: repoRoot,
          buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
          xcodeWorkspacePath: nil,
          xcodeProjectPath: nil
        )
      )
      Issue.record("Expected go build failure to throw.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "go_enry_build_failed")
    }
  }
}

// MARK: - removeIfPresent exercises deletion path

@Test func goEnryMaterializerRemovesExistingArtifactsBeforeBuilding() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let sharedRoot = repoRoot.appendingPathComponent("ThirdParty/go-enry/shared", isDirectory: true)
    try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
    try "package main\nimport \"C\"\nfunc main() {}\n".write(
      to: sharedRoot.appendingPathComponent("enry.go"),
      atomically: true,
      encoding: .utf8
    )

    let libRoot = repoRoot.appendingPathComponent(".build/vendor/go-enry/lib", isDirectory: true)
    let includeRoot = repoRoot.appendingPathComponent(".build/vendor/go-enry/include", isDirectory: true)
    try FileManager.default.createDirectory(at: libRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: includeRoot, withIntermediateDirectories: true)

    let archivePath = libRoot.appendingPathComponent("libenry.a")
    let generatedHeaderPath = libRoot.appendingPathComponent("libenry.h")
    let installedHeaderPath = includeRoot.appendingPathComponent("enry.h")
    try Data("stale-archive".utf8).write(to: archivePath)
    try Data("stale-generated-header".utf8).write(to: generatedHeaderPath)
    try Data("stale-installed-header".utf8).write(to: installedHeaderPath)

    let runner = GoEnryMaterializationProcessRunner(results: [:])
    let materializer = GoEnryMaterializer(
      processRunner: runner,
      fileManager: .default,
      hostPlatform: .linux,
      hostArchitecture: .arm64
    )

    _ = try materializer.materialize(
      workspace: WorkspaceContext(
        projectRoot: repoRoot,
        buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
        xcodeWorkspacePath: nil,
        xcodeProjectPath: nil
      )
    )

    // Stale generated header should have been removed
    #expect(!FileManager.default.fileExists(atPath: generatedHeaderPath.path))
    // New archive should be present
    #expect(FileManager.default.fileExists(atPath: archivePath.path))
  }
}

// MARK: - singleHostVariant archive guard (fileExists returns false after moveItem)

@Test func goEnryMaterializerThrowsOnMissingArchiveAfterBuild() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let sharedRoot = repoRoot.appendingPathComponent("ThirdParty/go-enry/shared", isDirectory: true)
    try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
    try "package main\nimport \"C\"\nfunc main() {}\n".write(
      to: sharedRoot.appendingPathComponent("enry.go"),
      atomically: true,
      encoding: .utf8
    )

    let runner = GoEnryMaterializationProcessRunner(results: [:])
    let fakeFM = FakeFileExistsManager(pathsDenied: ["libenry.a"])
    let materializer = GoEnryMaterializer(
      processRunner: runner,
      fileManager: fakeFM,
      hostPlatform: .linux,
      hostArchitecture: .arm64
    )

    do {
      _ = try materializer.materialize(
        workspace: WorkspaceContext(
          projectRoot: repoRoot,
          buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
          xcodeWorkspacePath: nil,
          xcodeProjectPath: nil
        )
      )
      Issue.record("Expected missing archive error.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_go_enry_archive")
    }
  }
}

// MARK: - singleHostVariant header guard (fileExists returns false for header)

@Test func goEnryMaterializerThrowsOnMissingHeaderAfterBuild() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let sharedRoot = repoRoot.appendingPathComponent("ThirdParty/go-enry/shared", isDirectory: true)
    try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
    try "package main\nimport \"C\"\nfunc main() {}\n".write(
      to: sharedRoot.appendingPathComponent("enry.go"),
      atomically: true,
      encoding: .utf8
    )

    let runner = GoEnryMaterializationProcessRunner(results: [:])
    let fakeFM = FakeFileExistsManager(pathsDenied: ["libenry-linux-arm64.h"])
    let materializer = GoEnryMaterializer(
      processRunner: runner,
      fileManager: fakeFM,
      hostPlatform: .linux,
      hostArchitecture: .arm64
    )

    do {
      _ = try materializer.materialize(
        workspace: WorkspaceContext(
          projectRoot: repoRoot,
          buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
          xcodeWorkspacePath: nil,
          xcodeProjectPath: nil
        )
      )
      Issue.record("Expected missing header error.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_go_enry_header")
    }
  }
}

// MARK: - Test Stubs

/// FileManager subclass that denies `fileExists` for paths whose last component matches a denied name.
private final class FakeFileExistsManager: FileManager {
  let pathsDenied: Set<String>

  init(pathsDenied: some Sequence<String>) {
    self.pathsDenied = Set(pathsDenied)
    super.init()
  }

  required init?(coder: NSCoder) {
    fatalError("not implemented")
  }

  override func fileExists(atPath path: String) -> Bool {
    let lastComponent = URL(fileURLWithPath: path).lastPathComponent
    if pathsDenied.contains(lastComponent) {
      return false
    }
    return super.fileExists(atPath: path)
  }
}

private struct FailingLipoProcessRunner: ProcessRunning {
  func run(
    command: String,
    arguments: [String],
    environment: [String: String],
    currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "go",
      arguments.count == 5,
      arguments[0] == "build",
      arguments[1] == "-buildmode=c-archive"
    {
      let archivePath = URL(fileURLWithPath: arguments[3])
      let headerPath = archivePath.deletingPathExtension().appendingPathExtension("h")
      try FileManager.default.createDirectory(
        at: archivePath.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data("archive".utf8).write(to: archivePath)
      try "header".write(to: headerPath, atomically: true, encoding: .utf8)
      return StubProcessRunner.success()
    }

    if command == "/usr/bin/env", arguments.first == "lipo" {
      return CommandResult(exitStatus: 1, stdout: "", stderr: "lipo: can't open input file")
    }

    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 { 1234 }
}

private struct FailingGoBuildProcessRunner: ProcessRunning {
  func run(
    command: String,
    arguments: [String],
    environment: [String: String],
    currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "go", arguments.first == "build" {
      return CommandResult(exitStatus: 1, stdout: "", stderr: "cannot find package")
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 { 1234 }
}
