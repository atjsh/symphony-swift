import Foundation
import Testing

@testable import SymphonyXcodeValidation
@testable import SymphonyXcodeValidationCLI

@Suite("SymphonyXcodeValidationRunner Advanced")
struct SymphonyXcodeValidationRunnerAdvancedTests {
  @Test func runnerInfoLoggingEmitsLifecycleRetryAndCompletionMessages() async throws {
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
    let capturedLines = LockedStringBox()
    let runner = XcodeValidationRunner(
      processExecutor: executor,
      now: environment.now,
      logSink: { capturedLines.append($0) }
    )

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .info,
        skipFullMatrix: true
      )
    )
    let lines = capturedLines.values

    #expect(lines.contains(where: { $0.contains("Run started") && $0.contains("build_profile=fast") }))
    #expect(
      lines.contains(where: {
        $0.contains("Scenario started")
          && $0.contains("phase=mitigation")
          && $0.contains("run=progress-report-model")
      })
    )
    #expect(lines.contains(where: { $0.contains("Building test artifact") }))
    #expect(lines.contains(where: { $0.contains("Reusing build artifact") }))
    #expect(lines.contains(where: { $0.contains("Retrying scenario after transient simulator failure") }))
    #expect(lines.contains(where: { $0.contains("Copied exported artifacts") }))
    #expect(lines.contains(where: { $0.contains("Run completed") && $0.contains("status=passed") }))
  }

  @Test func runnerQuietLoggingEmitsNothing() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let capturedLines = LockedStringBox()
    let runner = XcodeValidationRunner(
      processExecutor: executor,
      now: environment.now,
      logSink: { capturedLines.append($0) }
    )

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .quiet,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )
    let lines = capturedLines.values

    #expect(lines.isEmpty)
  }

  @Test func runnerDebugLoggingIncludesCommandAndPathDetails() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let capturedLines = LockedStringBox()
    let runner = XcodeValidationRunner(
      processExecutor: executor,
      now: environment.now,
      logSink: { capturedLines.append($0) }
    )

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .debug,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )
    let lines = capturedLines.values

    #expect(lines.contains(where: { $0.contains("Launching command") && $0.contains("xcodebuild") }))
    #expect(lines.contains(where: { $0.contains("derived_data_path=") }))
    #expect(lines.contains(where: { $0.contains("result_bundle_path=") }))
    #expect(lines.contains(where: { $0.contains("export_root=") }))
  }

  @Test func runnerLogsBuildFailuresWithTrimmedCommandOutput() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub(
      buildFailures: [
        ValidationBuildDescriptor(platform: "macos", plan: "app-tests", buildProfile: "fast"):
          ValidationCommandResult(
            exitStatus: 65,
            stdout: "",
            stderr: String(repeating: "error: xcodebuild build-for-testing failed badly. ", count: 20)
          )
      ]
    )
    let capturedLines = LockedStringBox()
    let runner = XcodeValidationRunner(
      processExecutor: executor,
      now: environment.now,
      logSink: { capturedLines.append($0) }
    )

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .info,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )
    let lines = capturedLines.values

    #expect(lines.contains(where: { $0.contains("Build-for-testing failed") }))
    #expect(lines.contains(where: { $0.contains("output_excerpt=") }))
    #expect(lines.contains(where: { $0.contains("...") }))
  }

  @Test func runnerLogsXCResultFallbackWarningsAndDoesNotPersistLogFiles() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub(
      summaryMode: .invalidJSON,
      testsMode: .invalidJSON
    )
    let capturedLines = LockedStringBox()
    let runner = XcodeValidationRunner(
      processExecutor: executor,
      now: environment.now,
      logSink: { capturedLines.append($0) }
    )

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .info,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )
    let lines = capturedLines.values

    #expect(lines.contains(where: { $0.contains("xcresult summary decode failed") }))
    #expect(lines.contains(where: { $0.contains("xcresult tests decode failed") }))

    let topLevelChildren = try FileManager.default.contentsOfDirectory(
      at: environment.outputRoot,
      includingPropertiesForKeys: nil
    )
    #expect(topLevelChildren.contains(where: { $0.lastPathComponent == "summary.json" }))
    #expect(topLevelChildren.contains(where: { $0.lastPathComponent == "manifest.json" }))
    #expect(topLevelChildren.contains(where: { $0.lastPathComponent == "audit-summary.json" }))
    #expect(topLevelChildren.contains(where: { $0.lastPathComponent.lowercased().contains("log") }) == false)
  }

  @Test func runnerAggressiveProfileWarmsLaterBuildsWithoutStartingLaterTestsBeforeMitigationPass() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let probe = ValidationExecutionProbe()
    let executor = ValidationProcessExecutorStub(
      buildDelay: 0.05,
      testDelay: 0.20,
      probe: probe
    )
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        executionProfile: .aggressive,
        logLevel: .quiet
      )
    )

    let events = probe.events
    let mitigationFinishIndex = try #require(
      events.firstIndex(of: .testFinished(.init(
        platform: "macos",
        plan: "ui-tests",
        phase: "mitigation",
        runName: "accessibility-audit"
      )))
    )
    let warmedBuildIndex = try #require(
      events.firstIndex(of: .buildStarted(.init(
        platform: "ios",
        plan: "app",
        buildProfile: "fast"
      )))
    )

    #expect(warmedBuildIndex < mitigationFinishIndex)
    #expect(
      events[..<mitigationFinishIndex].contains { event in
        switch event {
        case .testStarted(let descriptor):
          descriptor.phase != "mitigation"
        default:
          false
        }
      } == false
    )
  }

  @Test func runnerAggressiveProfileRunsIndependentDestinationTestsConcurrently() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let probe = ValidationExecutionProbe()
    let executor = ValidationProcessExecutorStub(
      buildDelay: 0.02,
      testDelay: 0.15,
      probe: probe
    )
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let summary = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        executionProfile: .aggressive,
        logLevel: .quiet
      )
    )

    #expect(summary.status == .passed)
    #expect(probe.maxConcurrentTests >= 2)
  }

  @Test func runnerAggressiveProfileAvoidsRebootingSuccessfulSimulatorLanesBetweenScenarios() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        executionProfile: .aggressive,
        logLevel: .quiet
      )
    )

    #expect(executor.bootstatusCommandCount(for: "E09AB2DE-2B82-49E2-8119-6C2FD1227C04") == 1)
    #expect(executor.bootstatusCommandCount(for: "FB1A9F71-0620-4314-BF84-1BD1C46ABF5D") == 1)
  }

  @Test func runnerMovesAttachmentExportOffDestinationLane() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let probe = ValidationExecutionProbe()
    let executor = ValidationProcessExecutorStub(
      testDelay: 0.02,
      exportDelay: 0.50,
      probe: probe
    )
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        executionProfile: .aggressive,
        logLevel: .quiet,
        skipRichCapture: true
      )
    )

    let events = probe.events
    let exportFinishedIndex = try #require(
      events.firstIndex(of: .exportFinished(.init(
        platform: "macos",
        plan: "ui-tests",
        phase: "mitigation",
        runName: "accessibility-audit"
      )))
    )
    let nextTestStartedIndex = try #require(
      events.firstIndex(of: .testStarted(.init(
        platform: "macos",
        plan: "app",
        phase: "full-matrix",
        runName: "full-app"
      )))
    )

    #expect(nextTestStartedIndex < exportFinishedIndex)
  }

  @Test func runnerSerialProfileKeepsSingleLaneExecution() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let probe = ValidationExecutionProbe()
    let executor = ValidationProcessExecutorStub(
      buildDelay: 0.02,
      testDelay: 0.05,
      probe: probe
    )
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    _ = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        executionProfile: .serial,
        logLevel: .quiet
      )
    )

    #expect(probe.maxConcurrentTests == 1)
  }

  @Test func runnerCanonicalOnlyDeduplicatesPersistedManifestMediaArtifactsKeepingLastSourceResultBundle() async throws {
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

    let manifestURL = environment.outputRoot.appendingPathComponent("manifest.json")
    let manifestData = try Data(contentsOf: manifestURL)
    let manifestArtifacts = try JSONDecoder().decode([MediaArtifact].self, from: manifestData)
    let uniqueKeys = Set(manifestArtifacts.map(\.canonicalMediaKey))

    #expect(uniqueKeys.count == manifestArtifacts.count)
    guard uniqueKeys.count == manifestArtifacts.count else {
      return
    }

    #expect(summary.mediaArtifacts == manifestArtifacts)

    let retainedRootArtifact = manifestArtifacts.first(where: {
      $0.platform == "macos"
        && $0.plan == "ui-tests"
        && $0.checkpoint == "root"
        && $0.artifactType == .screenshot
    })
    let requiredRetainedRootArtifact = try #require(retainedRootArtifact)
    #expect(
      requiredRetainedRootArtifact.sourceResultBundle.hasSuffix(
        "/intermediates/macos/ui-tests/full-matrix/full-ui-tests/result.xcresult"
      )
    )
  }
}
