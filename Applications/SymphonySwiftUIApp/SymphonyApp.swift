import SwiftUI
import SymphonyShared
import SymphonyValidationGallery

#if canImport(AppKit)
  import AppKit
#endif

@main
struct SymphonyApp: App {
  @State private var model: SymphonyOperatorModel
  @State private var galleryStore: ValidationGalleryStore
  @State private var galleryRunnerStore: ValidationRunnerStore
  @State private var galleryImportController: ValidationGalleryImportController
  @State private var galleryExportController: ValidationGalleryExportController

  nonisolated static func resolveClient(
    arguments: [String],
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> (any SymphonyAPIClientProtocol)? {
    BootstrapEnvironment.isUITesting(arguments: arguments, environment: environment)
      ? UITestingSymphonyAPIClient() : nil
  }

  init() {
    let environment = ProcessInfo.processInfo.environment
    let endpoint = BootstrapEnvironment.effectiveServerEndpoint(environment: environment)
    let sharedEndpoint = endpoint.serverEndpoint

    let client = Self.resolveClient(arguments: ProcessInfo.processInfo.arguments, environment: environment)
    #if os(macOS)
      let localServerServices =
        BootstrapEnvironment.isUITesting(arguments: ProcessInfo.processInfo.arguments, environment: environment)
        ? LocalServerServices.uiTesting(environmentProvider: { environment })
        : LocalServerServices.live(environmentProvider: { environment })
      _model = State(initialValue: SymphonyOperatorModel(
        client: client,
        initialEndpoint: sharedEndpoint,
        localServerServices: localServerServices
      ))
    #else
      _model = State(initialValue: SymphonyOperatorModel(client: client, initialEndpoint: sharedEndpoint))
    #endif

    _galleryStore = State(initialValue: Self.makeGalleryStore(environment: environment))
    _galleryRunnerStore = State(initialValue: Self.makeRunnerStore(environment: environment))
    _galleryImportController = State(initialValue: ValidationGalleryImportController(environment: environment))
    _galleryExportController = State(initialValue: ValidationGalleryExportController(environment: environment))

    Self.emitStartupLogsIfNeeded(environment: environment)
  }

  init(
    arguments: [String],
    environment: [String: String],
    startupOutput: @escaping @Sendable (String) -> Void
  ) {
    let endpoint = BootstrapEnvironment.effectiveServerEndpoint(environment: environment)
    let sharedEndpoint = endpoint.serverEndpoint

    let client = Self.resolveClient(arguments: arguments, environment: environment)
    #if os(macOS)
      let localServerServices =
        BootstrapEnvironment.isUITesting(arguments: arguments, environment: environment)
        ? LocalServerServices.uiTesting(environmentProvider: { environment })
        : LocalServerServices.live(environmentProvider: { environment })
      _model = State(initialValue: SymphonyOperatorModel(
        client: client,
        initialEndpoint: sharedEndpoint,
        localServerServices: localServerServices
      ))
    #else
      _model = State(initialValue: SymphonyOperatorModel(client: client, initialEndpoint: sharedEndpoint))
    #endif

    _galleryStore = State(initialValue: Self.makeGalleryStore(environment: environment))
    _galleryRunnerStore = State(initialValue: Self.makeRunnerStore(environment: environment))
    _galleryImportController = State(initialValue: ValidationGalleryImportController(environment: environment))
    _galleryExportController = State(initialValue: ValidationGalleryExportController(environment: environment))

    Self.emitStartupLogsIfNeeded(environment: environment, output: startupOutput)
  }

  nonisolated static func emitStartupLogsIfNeeded(
    environment: [String: String],
    terminateApplication: Bool = true
  ) {
    if BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: environment) {
      let state = BootstrapStartupState.current(componentName: "Symphony", environment: environment)
      for line in state.startupLogLines {
        defaultStartupOutput(line)
      }
      #if canImport(AppKit)
        guard terminateApplication else { return }
        DispatchQueue.main.async {
          NSApp.terminate(nil)
        }
      #endif
    }
  }

  nonisolated static func emitStartupLogsIfNeeded(
    environment: [String: String],
    output: @escaping @Sendable (String) -> Void,
    terminateApplication: Bool = true
  ) {
    if BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: environment) {
      let state = BootstrapStartupState.current(componentName: "Symphony", environment: environment)
      for line in state.startupLogLines {
        output(line)
      }
      #if canImport(AppKit)
        guard terminateApplication else { return }
        DispatchQueue.main.async {
          NSApp.terminate(nil)
        }
      #endif
    }
  }

  nonisolated static func defaultStartupOutput(_ line: String) {
    print(line)
  }

  private static func makeGalleryStore(environment: [String: String]) -> ValidationGalleryStore {
    ValidationGalleryStore(
      loader: ValidationBundleLoader(),
      recentBundleStore: makeRecentBundleStore(environment: environment),
      workspacePreferencesStore: makeWorkspacePreferencesStore(environment: environment)
    )
  }

  private static func makeRunnerStore(environment: [String: String]) -> ValidationRunnerStore {
    let serverURL = URL(string: environment["XCODE_VALIDATION_SERVER_URL"] ?? "http://127.0.0.1:8090")
      ?? URL(string: "http://127.0.0.1:8090")!  // swiftlint:disable:this force_unwrapping
    return ValidationRunnerStore(serverURL: serverURL)
  }

  private static func makeRecentBundleStore(
    environment: [String: String]
  ) -> UserDefaultsValidationRecentBundleStore {
    guard
      let suiteName = environment["XCODE_VALIDATION_GALLERY_UI_TEST_DEFAULTS_SUITE"],
      suiteName.isEmpty == false,
      let userDefaults = UserDefaults(suiteName: suiteName)
    else {
      return UserDefaultsValidationRecentBundleStore()
    }
    return UserDefaultsValidationRecentBundleStore(userDefaults: userDefaults)
  }

  private static func makeWorkspacePreferencesStore(
    environment: [String: String]
  ) -> UserDefaultsValidationGalleryWorkspacePreferencesStore {
    guard
      let suiteName = environment["XCODE_VALIDATION_GALLERY_UI_TEST_DEFAULTS_SUITE"],
      suiteName.isEmpty == false,
      let userDefaults = UserDefaults(suiteName: suiteName)
    else {
      return UserDefaultsValidationGalleryWorkspacePreferencesStore()
    }
    return UserDefaultsValidationGalleryWorkspacePreferencesStore(userDefaults: userDefaults)
  }

  private var isUITesting: Bool {
    BootstrapEnvironment.isUITesting()
  }

  var body: some Scene {
    WindowGroup {
      TabView {
        Tab("Operator", systemImage: "desktopcomputer") {
          ContentView(model: model)
            .task {
              if isUITesting { await model.connect() }
            }
        }
        .accessibilityIdentifier("operatorTab")

        Tab("Validation", systemImage: "checkmark.shield") {
          ValidationGalleryContainerView(
            store: galleryStore,
            runnerStore: galleryRunnerStore,
            importController: galleryImportController,
            exportController: galleryExportController
          )
        }
        .accessibilityIdentifier("validationTab")
      }
      .tabViewStyle(.sidebarAdaptable)
    }
    .defaultSize(width: 1280, height: 820)
    #if os(macOS)
      .defaultPosition(.center)
    #endif
    .windowResizability(.contentMinSize)
    .restorationBehavior(.automatic)
    #if os(macOS)
      .commands {
        SymphonyCommands(model: model)
      }
      .commands {
        ValidationGalleryEmbeddedCommands(
          store: galleryStore,
          importController: galleryImportController
        )
      }
    #endif
    #if os(macOS)
      Window("Server", id: "server-editor") {
        OperatorEndpointEditorView(model: model, initialMode: .localServer)
      }
      .windowResizability(.contentSize)
      .restorationBehavior(.disabled)
      .defaultPosition(.center)
    #endif
  }
}

// swiftlint:disable force_try
struct UITestingSymphonyAPIClient: SymphonyAPIClientProtocol {
  func health(endpoint: ServerEndpoint) async throws -> HealthResponse {
    HealthResponse(
      status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
  }

  func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse {
    IssuesResponse(items: [
      IssueSummary(
        issueID: IssueID("issue-1"),
        identifier: try! IssueIdentifier(validating: "atjsh/example#1"),
        title: "Implement feature",
        state: "in_progress",
        issueState: "OPEN",
        priority: 1,
        currentProvider: "claude_code",
        currentRunID: RunID("run-1"),
        currentSessionID: SessionID("session-1")
      )
    ])
  }

  func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail {
    let issue = Issue(
      id: IssueID("issue-1"),
      identifier: try! IssueIdentifier(validating: "atjsh/example#1"),
      repository: "atjsh/example",
      number: 1,
      title: "Implement feature",
      description: "A test issue for UI testing.",
      priority: 1,
      state: "in_progress",
      issueState: "OPEN",
      projectItemID: "item-1",
      url: "https://example.com/issues/1",
      labels: ["feature", "ui"],
      blockedBy: [],
      createdAt: "2026-03-24T00:00:00Z",
      updatedAt: "2026-03-24T01:00:00Z"
    )
    let run = RunSummary(
      runID: RunID("run-1"),
      issueID: IssueID("issue-1"),
      issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#1"),
      attempt: 1,
      status: "running",
      provider: "claude_code",
      providerSessionID: "ps-1",
      providerRunID: "pr-1",
      startedAt: "2026-03-24T01:00:00Z",
      endedAt: nil,
      workspacePath: "/tmp/symphony/atjsh_example_1",
      sessionID: SessionID("session-1"),
      lastError: nil
    )
    let session = AgentSession(
      sessionID: SessionID("session-1"),
      provider: "claude_code",
      providerSessionID: "ps-1",
      providerThreadID: nil,
      providerTurnID: nil,
      providerRunID: "pr-1",
      runID: RunID("run-1"),
      providerProcessPID: nil,
      status: "active",
      lastEventType: "message",
      lastEventAt: "2026-03-24T01:30:00Z",
      turnCount: 3,
      tokenUsage: try! TokenUsage(inputTokens: 100, outputTokens: 50),
      latestRateLimitPayload: nil
    )
    return IssueDetail(
      issue: issue, latestRun: run, workspacePath: "/tmp/symphony/atjsh_example_1",
      recentSessions: [session])
  }

  func issueProgressReport(endpoint: ServerEndpoint, issueID: IssueID) async throws
    -> IssueProgressReportResponse
  {
    let file = RepositoryFileSummary(
      path: "Sources/App/Main.swift",
      category: .source,
      lineCount: 120,
      characterCount: 3_200,
      byteCount: 3_200
    )
    let activity = RepositoryGitActivitySummary(changedFileCount: 2, additions: 14, deletions: 3)
    let metrics = RepositoryMetricsSnapshot(
      fileCount: 5,
      sourceFileCount: 3,
      testFileCount: 1,
      otherFileCount: 1,
      lineCount: 640,
      characterCount: 15_000,
      byteCount: 15_000,
      largestFile: file,
      smallestFile: file,
      activity: activity
    )
    return IssueProgressReportResponse(
      issueID: issueID,
      generatedAt: "2026-03-24T12:00:00Z",
      report: RepositoryHistoryReport(
        headCommitID: "abcdef1234567890",
        summary: metrics,
        commits: [
          RepositoryHistoryCommit(
            commitID: "abcdef1234567890",
            shortID: "abcdef1",
            subject: "Implement feature",
            authorName: "Taylor",
            committedAt: "2026-03-24T01:00:00Z",
            metrics: metrics,
            activity: activity
          )
        ],
        buckets: [
          RepositoryMetricsBucket(
            bucketID: "bucket-1",
            label: "Current",
            rangeStart: "2026-03-18T00:00:00Z",
            rangeEnd: "2026-03-24T23:59:59Z",
            metrics: metrics
          )
        ]
      ),
      syntaxHealth: RepositorySyntaxHealth(
        status: .configured,
        checkedFileCount: 4,
        diagnosticCount: 1,
        diagnostics: [
          RepositorySyntaxDiagnostic(
            path: "Sources/App/Main.swift",
            message: "Unexpected token",
            severity: "error",
            line: 18,
            column: 7
          )
        ]
      )
    )
  }

  func runDetail(endpoint: ServerEndpoint, runID: RunID) async throws -> RunDetail {
    let issue = Issue(
      id: IssueID("issue-1"),
      identifier: try! IssueIdentifier(validating: "atjsh/example#1"),
      repository: "atjsh/example",
      number: 1,
      title: "Implement feature",
      description: "A test issue for UI testing.",
      priority: 1,
      state: "in_progress",
      issueState: "OPEN",
      projectItemID: "item-1",
      url: "https://example.com/issues/1",
      labels: ["feature", "ui"],
      blockedBy: [],
      createdAt: "2026-03-24T00:00:00Z",
      updatedAt: "2026-03-24T01:00:00Z"
    )
    return RunDetail(
      runID: RunID("run-1"),
      issueID: IssueID("issue-1"),
      issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#1"),
      attempt: 1,
      status: "running",
      provider: "claude_code",
      providerSessionID: "ps-1",
      providerRunID: "pr-1",
      startedAt: "2026-03-24T01:00:00Z",
      endedAt: nil,
      workspacePath: "/tmp/symphony/atjsh_example_1",
      sessionID: SessionID("session-1"),
      lastError: nil,
      issue: issue,
      turnCount: 3,
      lastAgentEventType: "message",
      lastAgentMessage: "Working on the feature implementation.",
      tokens: try! TokenUsage(inputTokens: 100, outputTokens: 50),
      logs: RunLogStats(eventCount: 2, latestSequence: EventSequence(2))
    )
  }

  func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  {
    LogEntriesResponse(
      sessionID: SessionID("session-1"),
      provider: "claude_code",
      items: [
        AgentRawEvent(
          sessionID: SessionID("session-1"),
          provider: "claude_code",
          sequence: EventSequence(1),
          timestamp: "2026-03-24T01:10:00Z",
          rawJSON: #"{"message":"Started"}"#,
          providerEventType: "message",
          normalizedEventKind: "message"
        ),
        AgentRawEvent(
          sessionID: SessionID("session-1"),
          provider: "claude_code",
          sequence: EventSequence(2),
          timestamp: "2026-03-24T01:15:00Z",
          rawJSON: #"{"name":"edit_file","arguments":"Edit main.swift"}"#,
          providerEventType: "tool_use",
          normalizedEventKind: "tool_call"
        ),
      ],
      nextCursor: nil,
      hasMore: false
    )
  }

  func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
    RefreshResponse(queued: true, requestedAt: "2026-03-24T12:00:01Z")
  }

  func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws
    -> AsyncThrowingStream<AgentRawEvent, Error>
  {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}
// swiftlint:enable force_try
