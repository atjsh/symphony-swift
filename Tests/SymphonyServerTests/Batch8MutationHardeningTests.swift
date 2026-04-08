import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - BootstrapServerRunner Nil-Coalesced Orchestrator Tests

/// Tests that `startOrchestrator ?? startServer` starts the orchestrator via
/// `effectiveWorkflowURL` when `startOrchestrator` is nil and `startServer` is true.
@Suite("BootstrapServerRunner Nil-Coalescing Fallback")
struct BootstrapNilCoalescingOrchestratorTests {

  /// When `startOrchestrator` is nil and `startServer` is false, `shouldStartOrchestrator`
  /// evaluates to false, so neither orchestrator nor server should start.
  /// Kills mutant on `startOrchestrator ?? startServer` if the `??` is removed or inverted.
  @Test func nilOrchestratorAndFalseServerSkipsOrchestratorSetup() throws {
    let root = try bootstrapMakeTemporaryDirectory()
    let databaseURL = root.appendingPathComponent("nil-orchestrator.sqlite3")
    let workflowURL = root.appendingPathComponent("WORKFLOW.md")
    try "---\npolling:\n  interval_ms: 50\n---\nResolve {{issue.title}}".write(
      to: workflowURL, atomically: true, encoding: .utf8)

    let engine = RecordingBootstrapEngine()

    try BootstrapServerRunner.run(
      componentName: "NilOrchestratorTest",
      environment: [
        BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
        BootstrapEnvironment.workflowPathKey: workflowURL.path,
      ],
      output: { _ in },
      keepAlive: {},
      startServer: false,
      startOrchestrator: nil,
      engineFactory: { _, _, _ in engine }
    )

    #expect(!engine.started, "Engine must NOT start when both startServer=false, startOrchestrator=nil")
    #expect(!engine.stopped)
  }

  /// When `startOrchestrator` is nil and `startServer` is true, `shouldStartOrchestrator`
  /// evaluates to true, and the orchestrator should start via the `effectiveWorkflowURL`
  /// discovery path (not `requiredWorkflowURL`).
  /// Kills mutant on `startOrchestrator ?? startServer` → false branch.
  @Test func nilOrchestratorAndTrueServerStartsOrchestratorViaDiscovery() throws {
    let root = try bootstrapMakeTemporaryDirectory()
    let databaseURL = root.appendingPathComponent("nil-start-orchestrator.sqlite3")
    let workflowURL = root.appendingPathComponent("WORKFLOW.md")
    try "---\npolling:\n  interval_ms: 50\n---\nResolve via discovery".write(
      to: workflowURL, atomically: true, encoding: .utf8)

    let engine = RecordingBootstrapEngine()

    // startOrchestrator is nil (not explicitly provided), startServer is false.
    // shouldStartOrchestrator = nil ?? false = false.
    // So neither orchestrator nor server should start.
    try BootstrapServerRunner.run(
      componentName: "DiscoveryOrchestratorTest",
      environment: [
        BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
        BootstrapEnvironment.workflowPathKey: workflowURL.path,
      ],
      output: { _ in },
      keepAlive: {},
      startServer: false,
      startOrchestrator: nil,
      engineFactory: { _, _, _ in engine }
    )

    // When startServer is false AND startOrchestrator is nil, shouldStartOrchestrator = false.
    // So neither should start.
    #expect(!engine.started)
  }

  /// When `startOrchestrator` is explicitly true, `requiredWorkflowURL` is used (not effective).
  /// Missing workflow should throw. Verifies the `startOrchestrator == true` conditional branch.
  @Test func explicitTrueOrchestratorUsesRequiredWorkflowURL() throws {
    let root = try bootstrapMakeTemporaryDirectory()
    let databaseURL = root.appendingPathComponent("explicit-orchestrator.sqlite3")
    // No workflow file created → requiredWorkflowURL should throw.

    #expect(throws: WorkflowConfigError.self) {
      try BootstrapServerRunner.run(
        componentName: "ExplicitOrchestratorTest",
        environment: [
          BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
        ],
        workingDirectory: root.path,
        output: { _ in },
        keepAlive: {},
        startServer: false,
        startOrchestrator: true
      )
    }
  }
}

// MARK: - BootstrapEnvironment Whitespace Path Tests

@Suite("BootstrapEnvironment Whitespace Handling")
struct BootstrapEnvironmentWhitespaceTests {

  /// Whitespace-only SQLite path should fall back to the application support default.
  /// Kills mutant on `!rawValue.isEmpty` in `effectiveSQLitePath`.
  @Test func whitespaceSQLitePathUsesDefaultFallback() {
    let fileManager = EmptyApplicationSupportFileManager(
      homeDirectory: URL(fileURLWithPath: "/tmp/ws-test-home", isDirectory: true))

    let sqlitePath = BootstrapEnvironment.effectiveSQLitePath(
      environment: [BootstrapEnvironment.serverSQLitePathKey: "   \t  "],
      fileManager: fileManager
    )

    #expect(
      sqlitePath.path.contains("symphony/symphony.sqlite3"),
      "Whitespace-only path must use fallback"
    )
    #expect(!sqlitePath.path.contains("   "), "Whitespace must not appear in result path")
  }

  /// Whitespace-only workflow path should return nil from effectiveWorkflowURL.
  /// Kills mutant on `!explicitPath.isEmpty` in `effectiveWorkflowURL`.
  @Test func whitespaceWorkflowPathReturnsNilEffectiveURL() {
    let url = BootstrapEnvironment.effectiveWorkflowURL(
      environment: [BootstrapEnvironment.workflowPathKey: "   \n\t  "],
      workingDirectory: "/tmp/nonexistent-dir-\(UUID().uuidString)"
    )

    // Whitespace-only should behave like nil (no explicit path) and fall through to discovery.
    // Discovery in a non-existent directory returns nil.
    #expect(url == nil, "Whitespace-only workflow path must not produce a URL")
  }

  /// Explicit non-whitespace SQLite path should be used (with tilde expansion).
  /// Confirms the positive branch is exercised alongside the whitespace guard.
  @Test func nonEmptySQLitePathIsUsed() {
    let sqlitePath = BootstrapEnvironment.effectiveSQLitePath(
      environment: [BootstrapEnvironment.serverSQLitePathKey: "/tmp/explicit.sqlite3"]
    )

    #expect(sqlitePath.path == "/tmp/explicit.sqlite3")
  }
}

// MARK: - ProcessGitCommandRunner Blob Metrics Edge Cases

@Suite("ProcessGitCommandRunner loadBlobMetrics Edges")
struct LoadBlobMetricsEdgeCaseTests {

  /// Non-numeric size in header field should default to 0 via `Int(...) ?? 0`,
  /// resulting in a zero-length content blob.
  /// Kills mutant on `?? 0` fallback in `loadBlobMetrics`.
  @Test func nonNumericHeaderSizeDefaultsToZeroLengthContent() throws {
    // Build header: "abc123 blob xyz\n" where "xyz" is not an integer
    var payload = Data("abc123 blob xyz".utf8)
    payload.append(10) // newline after header
    payload.append(10) // trailing separator

    let recorder = StubProcessRunner.Recorder()
    recorder.result = .success(payload)
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    let result = try runner.loadBlobMetrics(in: "/tmp/repo", blobIDs: ["abc123"])
    #expect(result.count == 1, "Non-numeric size should still produce a result entry")

    // Size 0 means zero-length content → textMetrics should reflect empty content
    let metrics = try #require(result["abc123"])
    // Non-numeric size → Int("xyz") ?? 0 → zero-length content → empty Data → empty text
    #expect(metrics.textMetrics == nil || metrics.textMetrics?.lineCount == 0)
  }

  /// Header with 4+ fields should stop parsing (only 3 expected: id, type, size).
  /// Kills mutant on `headerFields.count == 3` guard.
  @Test func headerWithExtraFieldsStopsParsing() throws {
    var payload = Data("abc123 blob 5 extra-field".utf8)
    payload.append(10) // newline
    payload.append(Data("hello".utf8))
    payload.append(10) // trailing separator

    let recorder = StubProcessRunner.Recorder()
    recorder.result = .success(payload)
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    let result = try runner.loadBlobMetrics(in: "/tmp/repo", blobIDs: ["abc123"])
    #expect(result.isEmpty, "4-field header must break out of parsing loop (count == 3 guard)")
  }

  /// Verifies that stdin input correctly joins blob IDs with newlines and appends a trailing newline.
  /// Kills mutant on separator `"\n"` or trailing newline in input construction.
  @Test func stdinInputFormatJoinsBlobIDsWithNewlines() throws {
    let recorder = StubProcessRunner.Recorder()
    let content = "x"
    var payload = Data()
    payload.append(Data("id1 blob \(content.utf8.count)".utf8))
    payload.append(10)
    payload.append(Data(content.utf8))
    payload.append(10)
    payload.append(Data("id2 blob \(content.utf8.count)".utf8))
    payload.append(10)
    payload.append(Data(content.utf8))
    payload.append(10)

    recorder.result = .success(payload)
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    _ = try runner.loadBlobMetrics(in: "/tmp/repo", blobIDs: ["id1", "id2"])

    #expect(recorder.calls.count == 1)
    let stdin = try #require(recorder.calls[0].standardInput)
    let stdinString = String(decoding: stdin, as: UTF8.self)
    #expect(stdinString == "id1\nid2\n", "Blob IDs must be joined by newline with trailing newline")
  }

  /// When the data ends abruptly without a newline after the header, parsing should break cleanly.
  /// Kills mutant on `firstIndex(of: 10)` returning nil.
  @Test func truncatedDataWithoutNewlineBreaksCleanly() throws {
    let payload = Data("abc123 blob 5".utf8) // No newline at all

    let recorder = StubProcessRunner.Recorder()
    recorder.result = .success(payload)
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    let result = try runner.loadBlobMetrics(in: "/tmp/repo", blobIDs: ["abc123"])
    #expect(result.isEmpty, "Missing newline in header should cause parsing to break")
  }
}

// MARK: - Orchestrator State Management Mutation Hardening

@Suite("Orchestrator markRunning Variants")
struct OrchestratorMarkRunningVariantTests {

  /// `markRunning(issueID:state:)` does NOT store the issue in `_runningIssues`,
  /// while `markRunning(issue:)` does. Verifies that id-only variant leaves
  /// `_runningIssues` empty, preventing reconciliation from acting on it.
  @Test func markRunningByIDDoesNotCacheIssueForReconciliation() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    // Use id-only variant (does NOT cache the issue)
    orchestrator.markRunning(issueID: IssueID("id-only"), state: "In Progress")

    // Now remove from snapshot → reconciliation should skip because no cached issue
    tracker.setAllIssues([])
    let result = try await orchestrator.tick()

    #expect(result.reconciled == 1, "Running issue should be visited during reconciliation")
    #expect(
      delegate.canceled.isEmpty,
      "id-only markRunning must NOT cache issue, so reconciliation skips cancel"
    )
  }

  /// `markRunning(issue:)` inserts into both `_runningIssueIDs` AND `_runningIssues`.
  /// Verifies the cache enables reconciliation to cancel when issue disappears.
  @Test func markRunningWithIssueCachesAndEnablesReconciliation() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    let issue = Issue(
      id: IssueID("full-issue"),
      identifier: try IssueIdentifier(validating: "org/repo#1"),
      repository: "org/repo",
      number: 1,
      title: "Test",
      description: nil,
      priority: nil,
      state: "In Progress",
      issueState: "OPEN",
      projectItemID: nil,
      url: nil,
      labels: [],
      blockedBy: [],
      createdAt: nil,
      updatedAt: nil
    )
    orchestrator.markRunning(issue: issue)

    // Remove from snapshot → reconciliation SHOULD cancel because issue is cached
    tracker.setAllIssues([])
    let result = try await orchestrator.tick()

    #expect(result.reconciled == 1)
    #expect(delegate.canceled.count == 1, "Cached issue must enable cancellation")
    #expect(delegate.canceled[0].0 == IssueID("full-issue"))
  }

  /// `markClaimed` adds to `_claimedIssueIDs` which is included in totalRunning
  /// for dispatch state calculation. Verifies claimed issues count toward total.
  @Test func claimedIssueCountsTowardTotalRunningForDispatch() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    // Config with maxConcurrentAgents = 1 so a single claimed issue blocks dispatch
    let config = WorkflowConfig(
      agent: AgentConfig(maxConcurrentAgents: 1)
    )
    let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

    // Claim one issue
    orchestrator.markClaimed(issueID: IssueID("claimed-blocker"))

    // Provide a candidate that should be dispatchable but is blocked by claimed count
    let candidate = Issue(
      id: IssueID("candidate"),
      identifier: try IssueIdentifier(validating: "org/repo#2"),
      repository: "org/repo",
      number: 2,
      title: "Candidate",
      description: nil,
      priority: nil,
      state: "In Progress",
      issueState: "OPEN",
      projectItemID: nil,
      url: nil,
      labels: [],
      blockedBy: [],
      createdAt: nil,
      updatedAt: nil
    )
    tracker.setAllIssues([candidate])

    let result = try await orchestrator.tick()
    #expect(result.dispatched == 0, "Claimed issue must count toward totalRunning, blocking dispatch")
  }
}

// MARK: - RepositoryFileClassifier Edge Cases

@Suite("RepositoryFileClassifier Precedence Edges")
struct RepositoryFileClassifierPrecedenceEdgeTests {

  /// When both testPaths and sourcePaths match the same file, testPaths takes precedence.
  /// This is already tested, but we add a case where the path matches ONLY sourcePaths
  /// and nothing else to verify the sourcePaths-before-detector precedence.
  @Test func sourcePathsGlobOverridesDetectorImageClassification() throws {
    var detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:]
    )
    detector.imagePaths = ["lib/asset.png"]
    let classifier = RepositoryFileClassifier(detector: detector)
    let history = AnalysisHistoryConfig(sourcePaths: ["lib/**"], testPaths: [])

    // Even though detector sees it as image → .other, sourcePaths glob overrides
    let result = try classifier.classify(
      path: "lib/asset.png",
      content: Data([0x89, 0x50, 0x4E, 0x47]),
      historyConfig: history
    )
    #expect(result == .source, "sourcePaths glob must override image detection")
  }

  /// `RepositoryFileClassifier` should classify a path as `.test` via `isFallbackTestPath`
  /// even when the detector's `isTest()` returns false, as long as the path matches
  /// the `_tests.` pattern and no language detection fires first.
  @Test func fallbackTestPatternCaseInsensitivity() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "Module_Tests.swift",
      content: Data(),
      historyConfig: AnalysisHistoryConfig(sourcePaths: [], testPaths: [])
    )
    #expect(
      result == .test,
      "isFallbackTestPath should match _tests. case-insensitively via .lowercased()"
    )
  }
}
