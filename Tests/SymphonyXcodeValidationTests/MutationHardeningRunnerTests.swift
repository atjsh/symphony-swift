import Foundation
import Testing

@testable import SymphonyXcodeValidation

// MARK: - Runner Execution Paths

@Suite("MutationHardening - RunnerPaths")
struct MutationHardeningRunnerPathsTests {

  @Test func runnerSerialPathMitigationBlockerStopsExecutionEarly() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub(
      scenarioOutcomes: [
        ValidationScenarioDescriptor(
          platform: "macos", plan: "app-tests",
          phase: "mitigation", runName: "progress-report-model"
        ): [
          .failed(
            testIdentifier: "Tests/test()",
            failureText: "blocker"
          ),
        ],
      ]
    )
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let summary = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        executionProfile: .serial,
        logLevel: .quiet
      )
    )

    #expect(summary.status == .blocked)
    #expect(summary.unresolvedBlockers.count == 1)
    #expect(summary.runRecords.count == 2)
    #expect(executor.testWithoutBuildingCommands.count == 2)
  }

  @Test func runnerSkipRichCaptureOmitsRichCaptureScenarios() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let withRich = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .quiet,
        skipRichCapture: false,
        skipFullMatrix: true
      )
    )
    let environment2 = try ValidationRunnerTestEnvironment.make()
    let executor2 = ValidationProcessExecutorStub()
    let runner2 = XcodeValidationRunner(processExecutor: executor2, now: environment2.now)
    let noRich = try await runner2.runAsync(
      ValidationRequest(
        projectRoot: environment2.projectRoot,
        outputRoot: environment2.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .quiet,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )

    #expect(withRich.runRecords.count > noRich.runRecords.count)
    #expect(noRich.runRecords.allSatisfy { $0.phase == .mitigation })
  }

  @Test func runnerSkipFullMatrixOmitsMatrixScenarios() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let withMatrix = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .quiet,
        skipRichCapture: true,
        skipFullMatrix: false
      )
    )
    let environment2 = try ValidationRunnerTestEnvironment.make()
    let executor2 = ValidationProcessExecutorStub()
    let runner2 = XcodeValidationRunner(processExecutor: executor2, now: environment2.now)
    let noMatrix = try await runner2.runAsync(
      ValidationRequest(
        projectRoot: environment2.projectRoot,
        outputRoot: environment2.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .quiet,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )

    #expect(withMatrix.runRecords.count > noMatrix.runRecords.count)
    #expect(
      withMatrix.runRecords.contains(where: { $0.phase == .fullMatrix })
    )
    #expect(
      noMatrix.runRecords.contains(where: { $0.phase == .fullMatrix }) == false
    )
  }

  @Test func fullMatrixScenariosSetExportAttachmentsOnlyForUITests() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let scenarios = runner.makeFullMatrixScenarios(for: .symphonySwiftUIApp)

    let uiTestScenarios = scenarios.filter { $0.plan == .uiTests }
    let nonUITestScenarios = scenarios.filter { $0.plan != .uiTests }

    let allUIExportAttachments = uiTestScenarios.allSatisfy(\.exportAttachments)
    let noNonUIExportAttachments = nonUITestScenarios.allSatisfy({ !$0.exportAttachments })
    #expect(allUIExportAttachments)
    #expect(noNonUIExportAttachments)
  }

  @Test func materializeClearsSimulatorScreenshotOnMacOS() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let definition = ValidationScenarioDefinition(
      destinations: ValidationDestination.defaultMatrix,
      phase: .richCapture, plan: .uiTests,
      runName: "test", onlyTesting: [],
      exportAttachments: true, recordVideo: true,
      captureSimulatorScreenshot: true
    )

    let scenarios = runner.materialize(definition, for: .symphonySwiftUIApp)
    let macOSScenario = scenarios.first(where: { $0.destination == .macOS })
    let iPhoneScenario = scenarios.first(where: { $0.destination == .iPhoneSimulator })

    #expect(macOSScenario?.captureSimulatorScreenshot == false)
    #expect(iPhoneScenario?.captureSimulatorScreenshot == true)
  }

  @Test func shouldUseLegacySerialPathRequiresBothConditions() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let serialRequest = ValidationRequest(
      projectRoot: environment.projectRoot,
      executionProfile: .serial
    )
    let aggressiveRequest = ValidationRequest(
      projectRoot: environment.projectRoot,
      executionProfile: .aggressive
    )
    let serialOverriddenRequest = ValidationRequest(
      projectRoot: environment.projectRoot,
      executionProfile: .serial,
      concurrency: ValidationConcurrency(
        maxParallelBuilds: 2, maxParallelDestinations: 1,
        maxParallelSimulators: 1, warmBuildsBeforeMitigationPass: false
      )
    )

    #expect(runner.shouldUseLegacySerialPath(
      request: serialRequest,
      resolvedConcurrency: serialRequest.resolvedConcurrency()
    ) == true)
    #expect(runner.shouldUseLegacySerialPath(
      request: aggressiveRequest,
      resolvedConcurrency: aggressiveRequest.resolvedConcurrency()
    ) == false)
    #expect(runner.shouldUseLegacySerialPath(
      request: serialOverriddenRequest,
      resolvedConcurrency: serialOverriddenRequest.resolvedConcurrency()
    ) == false)
  }
}

// MARK: - Build Planning

@Suite("MutationHardening - BuildPlanning")
struct MutationHardeningBuildPlanningTests {

  @Test func executionPlanWarmBuildScenariosExcludeMitigationKeys() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let plan = runner.makeExecutionPlan(for: ValidationRequest(
      projectRoot: environment.projectRoot,
      outputRoot: environment.outputRoot,
      artifactRetention: .canonicalOnly
    ))

    let mitigationBuildKeys = Set(plan.mitigationScenarios.map(\.buildKey))
    let warmBuildKeys = Set(plan.warmBuildScenarios.map(\.buildKey))

    #expect(mitigationBuildKeys.isDisjoint(with: warmBuildKeys))
  }

  @Test func executionPlanIncludesRichCaptureAndFullMatrixWhenNotSkipped() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let fullPlan = runner.makeExecutionPlan(for: ValidationRequest(
      projectRoot: environment.projectRoot,
      skipRichCapture: false,
      skipFullMatrix: false
    ))
    let skipBothPlan = runner.makeExecutionPlan(for: ValidationRequest(
      projectRoot: environment.projectRoot,
      skipRichCapture: true,
      skipFullMatrix: true
    ))

    #expect(fullPlan.postMitigationLanes.flatMap(\.scenarios).count > 0)
    #expect(skipBothPlan.postMitigationLanes.isEmpty)
  }

  @Test func executionPlanPostMitigationLanesOmitEmptyDestinations() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let plan = runner.makeExecutionPlan(for: ValidationRequest(
      projectRoot: environment.projectRoot,
      skipRichCapture: true,
      skipFullMatrix: true
    ))

    #expect(plan.postMitigationLanes.allSatisfy { $0.scenarios.isEmpty == false })
  }

  @Test func executionPlanWarmBuildScenariosAreDeduplicatedByBuildKey() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let plan = runner.makeExecutionPlan(for: ValidationRequest(
      projectRoot: environment.projectRoot,
      outputRoot: environment.outputRoot,
      artifactRetention: .canonicalOnly
    ))

    let warmKeys = plan.warmBuildScenarios.map(\.buildKey)
    #expect(warmKeys.count == Set(warmKeys).count)
  }
}

// MARK: - Post Processing and Deduplication

@Suite("MutationHardening - PostProcessing")
struct MutationHardeningPostProcessingTests {

  @Test func deduplicatedKeepingLastRetainsOnlyFinalOccurrence() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let items = [
      ("a", 1), ("b", 2), ("a", 3), ("c", 4), ("b", 5),
    ]
    let result = runner.deduplicatedKeepingLast(items, by: \.0)

    #expect(result.map(\.1) == [3, 4, 5])
  }

  @Test func normalizedMediaArtifactsDeduplicatesOnlyForCanonicalOnly() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let artifact1 = MediaArtifact(
      platform: "ios", plan: "ui-tests", test: "t()",
      checkpoint: "main", surface: "root", orientation: "portrait",
      variant: "base", artifactType: .screenshot,
      file: "/tmp/same.png", sourceResultBundle: "/tmp/r1.xcresult"
    )
    let artifact2 = MediaArtifact(
      platform: "ios", plan: "ui-tests", test: "t()",
      checkpoint: "main", surface: "root", orientation: "portrait",
      variant: "base", artifactType: .screenshot,
      file: "/tmp/same.png", sourceResultBundle: "/tmp/r2.xcresult"
    )

    let canonical = runner.normalizedMediaArtifacts(
      [artifact1, artifact2], artifactRetention: .canonicalOnly
    )
    let debug = runner.normalizedMediaArtifacts(
      [artifact1, artifact2], artifactRetention: .debugFriendly
    )

    #expect(canonical.count == 1)
    #expect(canonical[0].sourceResultBundle == "/tmp/r2.xcresult")
    #expect(debug.count == 2)
  }

  @Test func orderedMakeSummaryPreservesIndexBasedOrdering() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let outcome2 = ValidationIndexedScenarioOutcome(
      index: 2,
      runRecord: ValidationRunRecord(
        phase: .fullMatrix, destination: .macOS, plan: .app,
        runName: "full-app", outcome: .passed,
        resultBundlePath: URL(fileURLWithPath: "/tmp/r2.xcresult"),
        summary: ValidationTestSummary(
          result: "Passed", passedTests: 1, failedTests: 0, testFailures: []
        ),
        startedAt: Date(timeIntervalSince1970: 20),
        endedAt: Date(timeIntervalSince1970: 30)
      ),
      mediaArtifacts: []
    )
    let outcome1 = ValidationIndexedScenarioOutcome(
      index: 1,
      runRecord: ValidationRunRecord(
        phase: .mitigation, destination: .macOS, plan: .appTests,
        runName: "test", outcome: .passed,
        resultBundlePath: URL(fileURLWithPath: "/tmp/r1.xcresult"),
        summary: ValidationTestSummary(
          result: "Passed", passedTests: 1, failedTests: 0, testFailures: []
        ),
        startedAt: Date(timeIntervalSince1970: 10),
        endedAt: Date(timeIntervalSince1970: 20)
      ),
      mediaArtifacts: []
    )

    let summary = runner.makeSummary(
      outputRoot: environment.outputRoot,
      indexedOutcomes: [outcome2, outcome1],
      postProcessingOutcomes: [],
      artifactRetention: .canonicalOnly
    )

    #expect(summary.runRecords[0].phase == .mitigation)
    #expect(summary.runRecords[1].phase == .fullMatrix)
  }
}

// MARK: - Build Failure Handling

@Suite("MutationHardening - BuildFailures")
struct MutationHardeningBuildFailureTests {

  @Test func buildFailureRecordsSyntheticFailureInRunRecord() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub(
      buildFailures: [
        ValidationBuildDescriptor(
          platform: "macos", plan: "app-tests", buildProfile: "fast"
        ):
          ValidationCommandResult(exitStatus: 65, stdout: "", stderr: "build error text"),
      ]
    )
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let summary = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .quiet,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )

    let failedRecords = summary.runRecords.filter { $0.outcome == .failed }
    #expect(failedRecords.count == 1)
    #expect(
      failedRecords[0].summary.testFailures[0].failureText
        .contains("build error text"))
  }

  @Test func buildFailureWithEmptyOutputUsesDefaultMessage() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub(
      buildFailures: [
        ValidationBuildDescriptor(
          platform: "macos", plan: "app-tests", buildProfile: "fast"
        ):
          ValidationCommandResult(exitStatus: 65, stdout: "", stderr: ""),
      ]
    )
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let summary = try await runner.runAsync(
      ValidationRequest(
        projectRoot: environment.projectRoot,
        outputRoot: environment.outputRoot,
        artifactRetention: .canonicalOnly,
        logLevel: .quiet,
        skipRichCapture: true,
        skipFullMatrix: true
      )
    )

    let failedRecords = summary.runRecords.filter { $0.outcome == .failed }
    #expect(
      failedRecords[0].summary.testFailures[0].failureText
        .contains("xcodebuild build-for-testing failed"))
  }
}

// MARK: - XCResult Summary Fallback

@Suite("MutationHardening - XCResultFallback")
struct MutationHardeningXCResultFallbackTests {

  @Test func loadSummaryFallsBackWhenResultBundleMissing() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)
    let logger = ValidationRunLogger(
      level: .quiet, now: environment.now, sink: nil
    )

    let missingBundlePath = environment.outputRoot
      .appendingPathComponent("nonexistent.xcresult")
    let summary = try runner.loadSummary(
      from: missingBundlePath, fallbackFailureText: "test failed hard",
      logger: logger
    )

    #expect(summary.result == "Failed")
    #expect(summary.failedTests == 1)
    #expect(summary.testFailures[0].failureText == "test failed hard")
  }

  @Test func loadSummaryFallsBackToDefaultWhenNoFallbackText() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)
    let logger = ValidationRunLogger(
      level: .quiet, now: environment.now, sink: nil
    )

    let missingBundlePath = environment.outputRoot
      .appendingPathComponent("nonexistent.xcresult")
    let summary = try runner.loadSummary(
      from: missingBundlePath, fallbackFailureText: "", logger: logger
    )

    #expect(
      summary.testFailures[0].failureText
        == "No result bundle was produced.")
  }
}

// MARK: - File Operations

@Suite("MutationHardening - FileOperations")
struct MutationHardeningFileOperationsTests {

  @Test func persistWritesSummaryAndMarkdownFiles() async throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(
      processExecutor: executor, now: environment.now
    )

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

    let fm = FileManager.default
    let outputRoot = environment.outputRoot
    #expect(fm.fileExists(
      atPath: outputRoot.appendingPathComponent("summary.json").path
    ))
    #expect(fm.fileExists(
      atPath: outputRoot.appendingPathComponent("manifest.json").path
    ))
    #expect(fm.fileExists(
      atPath: outputRoot.appendingPathComponent("summary.md").path
    ))

    let markdownData = try Data(
      contentsOf: outputRoot.appendingPathComponent("summary.md")
    )
    let markdown = String(decoding: markdownData, as: UTF8.self)
    #expect(markdown.contains("# Xcode Validation Summary"))
  }

  @Test func locateXCTestRunFindsFirstAlphabeticalFile() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(
      processExecutor: executor, now: environment.now
    )

    let derivedDataPath = environment.outputRoot
      .appendingPathComponent("derived-data", isDirectory: true)
    let productsDir = derivedDataPath
      .appendingPathComponent("Build/Products", isDirectory: true)
    try FileManager.default.createDirectory(
      at: productsDir, withIntermediateDirectories: true
    )

    try Data("b".utf8).write(
      to: productsDir.appendingPathComponent("beta.xctestrun")
    )
    try Data("a".utf8).write(
      to: productsDir.appendingPathComponent("alpha.xctestrun")
    )

    let result = try runner.locateXCTestRun(in: derivedDataPath)
    #expect(result.lastPathComponent == "alpha.xctestrun")
  }

  @Test func locateXCTestRunThrowsWhenNoFilesFound() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(
      processExecutor: executor, now: environment.now
    )

    let emptyDir = environment.outputRoot
      .appendingPathComponent("empty-dd", isDirectory: true)
    try FileManager.default.createDirectory(
      at: emptyDir, withIntermediateDirectories: true
    )

    #expect(throws: Error.self) {
      try runner.locateXCTestRun(in: emptyDir)
    }
  }
}

// MARK: - Destination and Subject Helpers

@Suite("MutationHardening - DestinationHelpers")
struct MutationHardeningDestinationHelpersTests {

  @Test func destinationSimulatorUDIDIsNilForMacOS() {
    #expect(ValidationDestination.macOS.simulatorUDID == nil)
    #expect(ValidationDestination.iPhoneSimulator.simulatorUDID != nil)
    #expect(ValidationDestination.iPadSimulator.simulatorUDID != nil)
  }

  @Test func destinationPlatformDirectoryNameMatchesExpected() {
    #expect(
      ValidationDestination.macOS.platformDirectoryName == "macos"
    )
    #expect(
      ValidationDestination.iPhoneSimulator.platformDirectoryName == "ios"
    )
    #expect(
      ValidationDestination.iPadSimulator.platformDirectoryName == "ipados"
    )
  }

  @Test func validationPlanSlugsMatchExpected() {
    #expect(ValidationPlan.app.slug == "app")
    #expect(ValidationPlan.appTests.slug == "app-tests")
    #expect(ValidationPlan.uiTests.slug == "ui-tests")
  }

  @Test func runPhaseSlugsMatchExpected() {
    #expect(RunPhase.mitigation.slug == "mitigation")
    #expect(RunPhase.richCapture.slug == "rich-capture")
    #expect(RunPhase.fullMatrix.slug == "full-matrix")
  }

  @Test func commandResultCombinedOutputConcatenation() {
    let both = ValidationCommandResult(
      exitStatus: 0, stdout: "out", stderr: "err"
    )
    #expect(both.combinedOutput == "out\nerr")

    let onlyOut = ValidationCommandResult(
      exitStatus: 0, stdout: "out", stderr: ""
    )
    #expect(onlyOut.combinedOutput == "out")

    let onlyErr = ValidationCommandResult(
      exitStatus: 0, stdout: "", stderr: "err"
    )
    #expect(onlyErr.combinedOutput == "err")
  }
}
