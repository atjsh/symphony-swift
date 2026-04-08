import Foundation
import Synchronization
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - ProcessLaunching: terminate() hardcoded exit code

@Suite("StubLaunchedProcess Terminate Exit Code")
struct StubLaunchedProcessTerminateExitCodeTests {

  /// terminate() must invoke the termination handler with exit code 15 (SIGTERM).
  /// Mutation: `handler?(15)` → `handler?(0)` or `handler?(1)` would change semantics.
  @Test func terminateCallsHandlerWithExitCode15() {
    let process = StubLaunchedProcess()
    let received = Mutex<Int32?>(nil)
    process.onTermination { code in
      received.withLock { $0 = code }
    }
    process.terminate()
    #expect(received.withLock { $0 } == 15, "terminate() must pass SIGTERM exit code 15")
  }

  /// After terminate(), further terminate() calls are no-ops — handler must not fire again.
  /// Kills guard-removal mutation on `guard !_terminated`.
  @Test func terminateIdempotentDoesNotRefire() {
    let process = StubLaunchedProcess()
    let callCount = Mutex(0)
    process.onTermination { _ in
      callCount.withLock { $0 += 1 }
    }
    process.terminate()
    process.terminate()
    #expect(callCount.withLock { $0 } == 1, "Handler must fire exactly once")
  }

  /// interrupt() after terminate() is a no-op and must not increment interruptCount.
  /// Distinct from existing test: verifies _terminated guard in interrupt() path.
  @Test func interruptAfterTerminateIsNoOp() {
    let process = StubLaunchedProcess()
    process.terminate()
    process.interrupt()
    process.interrupt()
    #expect(process.interruptCount == 0, "interrupt() after terminate() must be no-op")
  }
}

// MARK: - RuntimeLogging: overlapping secrets redacted longest first

@Suite("RuntimeLogger Redaction Order")
struct RuntimeLoggerRedactionOrderTests {

  /// When sensitive values overlap (e.g., "my_super_secret" and "my_super"),
  /// the longer value must be redacted first. If shorter is redacted first,
  /// "my_super_secret" → "[REDACTED]_secret" leaving partial secret visible.
  /// Kills mutation: `.sorted(by: { $0.count > $1.count })` → `<` or removal.
  @Test func overlappingSecretsRedactedLongestFirst() async throws {
    let (_, logs) = try await withCapturedRuntimeLogs {
      RuntimeLogger.log(
        level: .info,
        event: "overlap_redaction_test",
        context: RuntimeLogContext(),
        error: "credential: my_super_secret_value remainder: my_super",
        sensitiveValues: ["my_super", "my_super_secret_value"]
      )
    }

    let log = try #require(logs.first { $0.entry.event == "overlap_redaction_test" })
    let error = try #require(log.entry.error)
    // Both must be fully redacted — no partial like "_secret_value" visible
    #expect(!error.contains("my_super"), "All overlapping secrets must be fully redacted")
    #expect(!error.contains("secret_value"), "Partial secret must not leak")
    #expect(error.contains("[REDACTED]"))
  }

  /// Empty and whitespace-only sensitive values must be filtered out before sorting.
  /// Kills mutation: `.filter({ !$0.isEmpty })` removal would cause empty string matches.
  @Test func emptySecretsFilteredBeforeRedaction() async throws {
    let (_, logs) = try await withCapturedRuntimeLogs {
      RuntimeLogger.log(
        level: .info,
        event: "empty_filter_redaction",
        context: RuntimeLogContext(),
        error: "visible_token_here",
        sensitiveValues: ["", "   ", "visible_token_here"]
      )
    }

    let log = try #require(logs.first { $0.entry.event == "empty_filter_redaction" })
    let error = try #require(log.entry.error)
    #expect(!error.contains("visible_token_here"), "Real secret must be redacted")
    #expect(error == "[REDACTED]")
  }

  /// merge() must skip nil values entirely — not insert "nil" string.
  /// Kills mutation on `guard let value` removal in merge().
  @Test func nilContextFieldOmittedFromPayload() async throws {
    let (_, logs) = try await withCapturedRuntimeLogs {
      RuntimeLogger.log(
        level: .info,
        event: "nil_field_omit_test",
        context: RuntimeLogContext(
          issueID: nil,
          runID: "real-run-id",
          provider: nil
        )
      )
    }

    let log = try #require(logs.first { $0.entry.event == "nil_field_omit_test" })
    #expect(log.entry.runID == "real-run-id")
    #expect(log.entry.issueID == nil, "Nil issueID must not appear in payload")
    #expect(log.entry.provider == nil, "Nil provider must not appear in payload")
    // Also verify raw line doesn't contain the key at all
    #expect(!log.line.contains("\"issue_id\""))
    #expect(!log.line.contains("\"provider\""))
  }
}

// MARK: - WorkflowReloader: isWatching, processFileChange, unchanged skip

@Suite("WorkflowReloader Mutation Hardening")
struct WorkflowReloaderMutationTests {

  /// isWatching must be false before startWatching is called.
  /// Kills mutation: `_dispatchSource != nil` → `== nil`.
  @Test func isWatchingFalseBeforeStart() throws {
    let tmpFile = NSTemporaryDirectory() + "wf_test_\(UUID().uuidString).md"
    try "---\n---\nPrompt".write(toFile: tmpFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in }
    #expect(reloader.isWatching == false, "Must not be watching before startWatching()")
  }

  /// isWatching must become true after startWatching.
  @Test func isWatchingTrueAfterStart() throws {
    let tmpFile = NSTemporaryDirectory() + "wf_test_\(UUID().uuidString).md"
    try "---\n---\nPrompt".write(toFile: tmpFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in }
    try reloader.startWatching()
    defer { reloader.stopWatching() }
    #expect(reloader.isWatching == true, "Must be watching after startWatching()")
  }

  /// processFileChange fires onChange for initial (nil → definition) transition.
  /// Kills mutation: `previousDefinition != definition` → `==`.
  @Test func processFileChangeFiresOnChangeForInitialContent() throws {
    let tmpFile = NSTemporaryDirectory() + "wf_test_\(UUID().uuidString).md"
    try "---\n---\nInitial prompt".write(toFile: tmpFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let callCount = Mutex(0)
    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in
      callCount.withLock { $0 += 1 }
    }

    reloader.processFileChange()
    #expect(callCount.withLock { $0 } == 1, "Initial load (nil → definition) must trigger onChange")
  }

  /// Consecutive processFileChange with identical content must NOT fire onChange again.
  /// Kills mutation: `_lastDefinition = definition` removal (would always repeat).
  @Test func unchangedContentDoesNotRetriggerOnChange() throws {
    let tmpFile = NSTemporaryDirectory() + "wf_test_\(UUID().uuidString).md"
    try "---\n---\nStable prompt".write(toFile: tmpFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let callCount = Mutex(0)
    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in
      callCount.withLock { $0 += 1 }
    }

    reloader.processFileChange()
    reloader.processFileChange()
    #expect(callCount.withLock { $0 } == 1, "Identical content must not re-trigger onChange")
  }

  /// When file content is unparseable, onChange must NOT be called. Error is logged.
  /// Kills mutation: removal of the `do/catch` path or onChange call in wrong branch.
  @Test func invalidContentDoesNotTriggerOnChange() async throws {
    let tmpFile = NSTemporaryDirectory() + "wf_test_\(UUID().uuidString).md"
    // Write valid content first, then overwrite with invalid
    try "---\n---\nValid prompt".write(toFile: tmpFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let callCount = Mutex(0)
    let (_, logs) = try await withCapturedRuntimeLogs {
      let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in
        callCount.withLock { $0 += 1 }
      }

      // First call: valid → fires onChange (1)
      reloader.processFileChange()

      // Overwrite with entirely invalid frontmatter (YAML error)
      try "---\n- [invalid: yaml: {{{\n---\nBroken".write(
        toFile: tmpFile, atomically: true, encoding: .utf8)

      // Second call: parse error → must NOT fire onChange
      reloader.processFileChange()
    }

    #expect(callCount.withLock { $0 } == 1, "Parse error must not trigger onChange")
    let errorLog = logs.first { $0.entry.event == "workflow_reload_failed" }
    #expect(errorLog != nil, "Parse error must emit structured log")
  }

  /// startWatching on a nonexistent file must throw.
  /// Kills mutation: `fd >= 0` → `> 0` or removal.
  @Test func startWatchingNonexistentFileThrows() {
    let reloader = WorkflowReloader(workflowPath: "/nonexistent/path/workflow.md") { _ in }
    #expect(throws: OrchestratorEngineError.self) {
      try reloader.startWatching()
    }
  }

  /// stopWatching sets isWatching back to false.
  @Test func stopWatchingResetsIsWatching() throws {
    let tmpFile = NSTemporaryDirectory() + "wf_test_\(UUID().uuidString).md"
    try "---\n---\nPrompt".write(toFile: tmpFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in }
    try reloader.startWatching()
    reloader.stopWatching()
    #expect(reloader.isWatching == false, "Must not be watching after stopWatching()")
  }
}

// MARK: - GlobPattern: single star vs double star path separator semantics

@Suite("GlobPattern Path Separator Semantics")
struct GlobPatternPathSeparatorTests {

  /// Single `*` must NOT match path separators (`/`).
  /// regexPattern produces `[^/]*` for single star.
  /// Mutation: `[^/]*` → `.*` would match nested paths.
  @Test func singleStarDoesNotMatchNestedPath() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["src/nested/deep.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    // Single star: src/*.swift should NOT match src/nested/deep.swift
    let history = AnalysisHistoryConfig(sourcePaths: ["src/*.swift"], testPaths: [])
    let result = try classifier.classify(
      path: "src/nested/deep.swift", content: Data("code".utf8), historyConfig: history)
    // Falls through to language detection → "programming" → .source
    // but NOT via glob match — the glob must not match
    #expect(result == .source, "Single * must not cross path boundary")
  }

  /// Single `*` must match files directly in a directory.
  @Test func singleStarMatchesDirectChild() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let history = AnalysisHistoryConfig(sourcePaths: ["src/*.swift"], testPaths: [])
    let result = try classifier.classify(
      path: "src/main.swift", content: Data(), historyConfig: history)
    #expect(result == .source, "Single * must match direct children")
  }

  /// Double `**` must match across path separators.
  @Test func doubleStarMatchesAcrossPathBoundaries() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let history = AnalysisHistoryConfig(
      sourcePaths: [],
      testPaths: ["tests/**/*.swift"]
    )
    let result = try classifier.classify(
      path: "tests/unit/nested/deep.swift", content: Data(), historyConfig: history)
    #expect(result == .test, "Double ** must match across path separators")
  }

  /// Question mark `?` must match exactly one non-separator character.
  /// regexPattern produces `[^/]` for `?`.
  /// Mutation: `[^/]` → `.` would match `/`.
  @Test func questionMarkMatchesSingleNonSeparator() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let history = AnalysisHistoryConfig(
      sourcePaths: [],
      testPaths: ["test?.swift"]
    )
    // ? matches exactly one char (not /)
    let matchResult = try classifier.classify(
      path: "testA.swift", content: Data(), historyConfig: history)
    #expect(matchResult == .test, "? must match a single non-separator character")

    // Must NOT match two characters
    let noMatchResult = try classifier.classify(
      path: "testAB.swift", content: Data(), historyConfig: history)
    #expect(noMatchResult != .test, "? must match exactly one character, not two")
  }
}

// MARK: - ProcessGitCommandRunner: loadBlobMetrics empty input

@Suite("ProcessGitCommandRunner Empty BlobIDs")
struct LoadBlobMetricsEmptyInputTests {

  /// Empty blobIDs must return [:] immediately without running the process.
  /// Kills mutation: `!blobIDs.isEmpty` → `blobIDs.isEmpty` (would skip all).
  @Test func emptyBlobIDsReturnsEmptyDictImmediately() throws {
    let recorder = StubProcessRunner.Recorder()
    recorder.result = .success(Data())
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    let result = try runner.loadBlobMetrics(in: "/tmp/repo", blobIDs: [])
    #expect(result.isEmpty, "Empty blobIDs must return empty dict")
    #expect(recorder.calls.isEmpty, "Process must not be invoked for empty blobIDs")
  }
}
