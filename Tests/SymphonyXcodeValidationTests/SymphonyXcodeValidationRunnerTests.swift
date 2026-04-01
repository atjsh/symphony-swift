import Foundation
import Testing

@testable import SymphonyXcodeValidation
@testable import SymphonyXcodeValidationCLI

@Suite("SymphonyXcodeValidationRunner")
struct SymphonyXcodeValidationRunnerTests {
  @Test func xcodeValidationRunnerCommandDefaultsToCanonicalOnlyRetentionFastBuildProfileAggressiveExecutionAndInfoLogging() throws {
    let command =
      try SymphonyXcodeValidationRunnerCommand.parseAsRoot([])
      as! SymphonyXcodeValidationRunnerCommand

    #expect(command.subject == .symphonySwiftUIApp)
    #expect(command.artifactRetention == .canonicalOnly)
    #expect(command.buildProfile == .fast)
    #expect(command.executionProfile == .aggressive)
    #expect(command.maxParallelBuilds == nil)
    #expect(command.maxParallelDestinations == nil)
    #expect(command.maxParallelSimulators == nil)
    #expect(command.noWarmBuildsBeforeMitigationPass == false)
    #expect(command.logLevel == .info)
    #expect(command.skipRichCapture == false)
    #expect(command.skipFullMatrix == false)
  }

  @Test func xcodeValidationRunnerCommandParsesExecutionProfileBuildProfileArtifactRetentionLogLevelConcurrencyAndSkipFlags() throws {
    let command =
      try SymphonyXcodeValidationRunnerCommand.parseAsRoot([
        "--execution-profile", "balanced",
        "--build-profile", "standard",
        "--artifact-retention", "debug-friendly",
        "--max-parallel-builds", "4",
        "--max-parallel-destinations", "2",
        "--max-parallel-simulators", "1",
        "--no-warm-builds-before-mitigation-pass",
        "--log-level", "quiet",
        "--skip-rich-capture",
        "--skip-full-matrix",
      ]) as! SymphonyXcodeValidationRunnerCommand

    #expect(command.subject == .symphonySwiftUIApp)
    #expect(command.executionProfile == .balanced)
    #expect(command.buildProfile == .standard)
    #expect(command.artifactRetention == .debugFriendly)
    #expect(command.maxParallelBuilds == 4)
    #expect(command.maxParallelDestinations == 2)
    #expect(command.maxParallelSimulators == 1)
    #expect(command.noWarmBuildsBeforeMitigationPass)
    #expect(command.logLevel == .quiet)
    #expect(command.skipRichCapture)
    #expect(command.skipFullMatrix)
  }

  @Test func xcodeValidationRunnerCommandParsesExplicitFastBuildProfile() throws {
    let command =
      try SymphonyXcodeValidationRunnerCommand.parseAsRoot([
        "--build-profile", "fast",
      ]) as! SymphonyXcodeValidationRunnerCommand

    #expect(command.buildProfile == .fast)
  }

  @Test func xcodeValidationRunnerCommandParsesExplicitDebugLogLevel() throws {
    let command =
      try SymphonyXcodeValidationRunnerCommand.parseAsRoot([
        "--log-level", "debug",
      ]) as! SymphonyXcodeValidationRunnerCommand

    #expect(command.logLevel == .debug)
  }

  @Test func xcodeValidationRunnerCommandParsesExplicitGallerySubject() throws {
    let command =
      try SymphonyXcodeValidationRunnerCommand.parseAsRoot([
        "--subject", "xcode-validation-gallery-app",
      ]) as! SymphonyXcodeValidationRunnerCommand

    #expect(command.subject == .xcodeValidationGalleryApp)
  }

  @Test func xcodeValidationRunnerCommandMakeRequestResolvesProfileConcurrencyOverrides() {
    var command =
      try! SymphonyXcodeValidationRunnerCommand.parseAsRoot([])
      as! SymphonyXcodeValidationRunnerCommand
    command.executionProfile = .balanced
    command.maxParallelBuilds = 5
    command.maxParallelSimulators = 1

    let request = command.makeRequest(
      projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
    )

    #expect(request.subject == .symphonySwiftUIApp)
    #expect(request.executionProfile == .balanced)
    #expect(request.concurrency == .init(
      maxParallelBuilds: 5,
      maxParallelDestinations: 2,
      maxParallelSimulators: 1,
      warmBuildsBeforeMitigationPass: true
    ))
  }

  @Test func xcodeValidationRunnerCommandRejectsInvalidConcurrencyOverrides() {
    var command =
      try! SymphonyXcodeValidationRunnerCommand.parseAsRoot([])
      as! SymphonyXcodeValidationRunnerCommand
    command.maxParallelBuilds = 0
    #expect(throws: Error.self) {
      try command.validate()
    }

    command =
      try! SymphonyXcodeValidationRunnerCommand.parseAsRoot([])
      as! SymphonyXcodeValidationRunnerCommand
    command.maxParallelDestinations = 1
    command.maxParallelSimulators = 2
    #expect(throws: Error.self) {
      try command.validate()
    }
  }

  @Test func runnerUsesGallerySubjectSchemesEnvironmentAndSimulatorBundleIdentifiers() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let summary = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        subject: .xcodeValidationGalleryApp,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .quiet
      )
    )

    #expect(summary.status == .passed)
    #expect(summary.runRecords.count == 14)
    #expect(executor.buildForTestingCommands.count == 9)
    #expect(executor.testWithoutBuildingCommands.count == 14)
    #expect(
      executor.buildForTestingCommands.contains {
        $0.arguments.contains("XcodeValidationGalleryAppUITests")
          && $0.arguments.contains("XcodeValidationGalleryAppUITests")
      }
    )
    #expect(
      executor.buildForTestingCommands.contains {
        $0.arguments.contains("XcodeValidationGalleryAppTests")
      }
    )
    #expect(
      executor.testWithoutBuildingCommands.allSatisfy {
        $0.environment["XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE"] == "1"
      }
    )
    #expect(
      executor.runCommands.contains {
        $0.arguments == [
          "simctl",
          "terminate",
          "E09AB2DE-2B82-49E2-8119-6C2FD1227C04",
          "dev.atjsh.xcode-validation-gallery",
        ]
      }
    )
    #expect(
      executor.runCommands.contains {
        $0.arguments == [
          "simctl",
          "terminate",
          "E09AB2DE-2B82-49E2-8119-6C2FD1227C04",
          "dev.atjsh.xcodevalidationgallery.uitests.xctrunner",
        ]
      }
    )
  }

  @Test func xcodeValidationRunnerCommandSummaryLinesPreserveStdoutContract() {
    let summary = ValidationSummary(
      outputRoot: "/tmp/output",
      status: .blocked,
      runRecords: [],
      mediaArtifacts: [],
      auditIssues: [],
      unresolvedBlockers: ["Blocker A", "Blocker B"]
    )

    #expect(
      SymphonyXcodeValidationRunnerCommand.summaryLines(for: summary) == [
        "status: blocked",
        "output: /tmp/output",
        "runs: 0",
        "media_artifacts: 0",
        "audit_issues: 0",
        "unresolved_blockers:",
        "- Blocker A",
        "- Blocker B",
      ]
    )
  }

  @Test func runnerReusesBuildProductsAcrossFullValidationAndCleansCanonicalArtifacts() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let summary = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .quiet
      )
    )

    #expect(summary.status == .passed)
    #expect(summary.runRecords.count == 14)
    #expect(executor.buildForTestingCommands.count == 9)
    #expect(executor.testWithoutBuildingCommands.count == 14)
    #expect(
      executor.buildForTestingCommands.filter {
        $0.arguments.contains(where: { $0.contains("/intermediates/build-cache/ios/ui-tests/fast/derived-data") })
      }.count == 1
    )
    #expect(
      executor.buildForTestingCommands.allSatisfy { command in
        command.arguments.contains("-enableCodeCoverage")
          && command.arguments.contains("COMPILER_INDEX_STORE_ENABLE=NO")
      }
    )
    #expect(
      executor.testWithoutBuildingCommands.allSatisfy { command in
        command.arguments.contains("-enableCodeCoverage")
      }
    )
    #expect(
      summary.runRecords.allSatisfy { FileManager.default.fileExists(atPath: $0.resultBundlePath.path) }
    )
    #expect(
      summary.mediaArtifacts.allSatisfy { FileManager.default.fileExists(atPath: $0.file) }
    )
    #expect(
      summary.auditIssues.allSatisfy { FileManager.default.fileExists(atPath: $0.file) }
    )
    #expect(
      FileManager.default.fileExists(
        atPath: environment.outputRoot
          .appendingPathComponent("intermediates/build-cache", isDirectory: true).path
      ) == false
    )
    #expect(
      FileManager.default.fileExists(
        atPath: environment.outputRoot.appendingPathComponent("exports", isDirectory: true).path
      ) == false
    )
  }

  @Test func runnerRetryReusesExistingBuildArtifactsWithoutRebuilding() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let transientScenario = ValidationScenarioDescriptor(
      platform: "ios",
      plan: "ui-tests",
      phase: "rich-capture",
      runName: "rich-media"
    )
    let executor = ValidationProcessExecutorStub(
      scenarioOutcomes: [
        transientScenario: [
          .failed(
            testIdentifier: "Symphony encountered an error",
            failureText: "Failed to establish communication with the test runner. (Underlying Error: Channel disconnected)"
          ),
          .passed,
        ]
      ]
    )
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let summary = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .quiet,
        skipFullMatrix: true
      )
    )

    #expect(summary.status == .passed)
    #expect(summary.runRecords.count == 5)
    #expect(executor.buildForTestingCommands.count == 4)
    #expect(executor.testWithoutBuildingCommands.count == 6)
    #expect(
      executor.buildForTestingCommands.filter {
        $0.arguments.contains(where: { $0.contains("/intermediates/build-cache/ios/ui-tests/fast/derived-data") })
      }.count == 1
    )
  }

  @Test func runnerUsesSeparateBuildCachePathsForDifferentBuildProfiles() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        buildProfile: .fast,
        logLevel: .quiet,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        buildProfile: .standard,
        logLevel: .quiet,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )

    #expect(executor.buildForTestingCommands.count == 4)
    #expect(
      executor.buildForTestingCommands.contains {
        $0.arguments.contains(where: { $0.contains("/intermediates/build-cache/macos/app-tests/fast/derived-data") })
      }
    )
    #expect(
      executor.buildForTestingCommands.contains {
        $0.arguments.contains(where: { $0.contains("/intermediates/build-cache/macos/app-tests/standard/derived-data") })
      }
    )
  }

  @Test func runnerKeepsExportsInDebugFriendlyModeButRemovesSharedDerivedData() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .debugFriendly,
        logLevel: .quiet,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )

    #expect(
      FileManager.default.fileExists(
        atPath: environment.outputRoot
          .appendingPathComponent("intermediates/build-cache", isDirectory: true).path
      ) == false
    )
    #expect(
      FileManager.default.fileExists(
        atPath: environment.outputRoot
          .appendingPathComponent(
            "exports/macos/ui-tests/mitigation/accessibility-audit",
            isDirectory: true
          ).path
      )
    )
  }

  @Test func runnerKeepsEverythingWhenRequested() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .keepEverything,
        logLevel: .quiet,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )

    #expect(
      FileManager.default.fileExists(
        atPath: environment.outputRoot
          .appendingPathComponent("intermediates/build-cache/macos/app-tests/fast/derived-data", isDirectory: true)
          .path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: environment.outputRoot
          .appendingPathComponent(
            "exports/macos/ui-tests/mitigation/accessibility-audit",
            isDirectory: true
          ).path
      )
    )
  }

  @Test func runnerCleansEphemeralArtifactsOnEarlyMitigationReturn() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub(
      scenarioOutcomes: [
        ValidationScenarioDescriptor(
          platform: "macos",
          plan: "app-tests",
          phase: "mitigation",
          runName: "progress-report-model"
        ): [
          ValidationScenarioOutcomeStub.failed(
            testIdentifier: "SymphonySwiftUIAppTests/SymphonyOperatorModelTests/ProgressReportViewModelShowsCachedSnapshotBeforeRefreshing()",
            failureText: "Timed out waiting for condition."
          )
        ]
      ]
    )
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let summary = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .quiet
      )
    )

    #expect(summary.status == ValidationStatus.blocked)
    #expect(summary.runRecords.count == 2)
    #expect(summary.unresolvedBlockers.count == 1)
    #expect(
      FileManager.default.fileExists(
        atPath: environment.outputRoot
          .appendingPathComponent("intermediates/build-cache", isDirectory: true).path
      ) == false
    )
    #expect(
      FileManager.default.fileExists(
        atPath: environment.outputRoot.appendingPathComponent("exports", isDirectory: true).path
      ) == false
    )
  }

}
