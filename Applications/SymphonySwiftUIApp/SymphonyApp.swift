import SwiftUI
import SymphonyShared

#if canImport(AppKit)
  import AppKit
#endif

@main
struct SymphonyApp: App {
  private let model: SymphonyOperatorModel

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
    let sharedEndpoint = try! ServerEndpoint(
      scheme: endpoint.scheme, host: endpoint.host, port: endpoint.port)

    let client = Self.resolveClient(arguments: ProcessInfo.processInfo.arguments, environment: environment)
    model = SymphonyOperatorModel(client: client, initialEndpoint: sharedEndpoint)

    Self.emitStartupLogsIfNeeded(environment: environment)
  }

  init(
    arguments: [String],
    environment: [String: String],
    startupOutput: @escaping @Sendable (String) -> Void
  ) {
    let endpoint = BootstrapEnvironment.effectiveServerEndpoint(environment: environment)
    let sharedEndpoint = try! ServerEndpoint(
      scheme: endpoint.scheme, host: endpoint.host, port: endpoint.port)

    let client = Self.resolveClient(arguments: arguments, environment: environment)
    model = SymphonyOperatorModel(client: client, initialEndpoint: sharedEndpoint)

    Self.emitStartupLogsIfNeeded(environment: environment, output: startupOutput)
  }

  nonisolated static func emitStartupLogsIfNeeded(environment: [String: String]) {
    if BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: environment) {
      let state = BootstrapStartupState.current(componentName: "Symphony", environment: environment)
      for line in state.startupLogLines {
        defaultStartupOutput(line)
      }
      #if canImport(AppKit)
        DispatchQueue.main.async {
          NSApp.terminate(nil)
        }
      #endif
    }
  }

  nonisolated static func emitStartupLogsIfNeeded(
    environment: [String: String],
    output: @escaping @Sendable (String) -> Void
  ) {
    if BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: environment) {
      let state = BootstrapStartupState.current(componentName: "Symphony", environment: environment)
      for line in state.startupLogLines {
        output(line)
      }
      #if canImport(AppKit)
        DispatchQueue.main.async {
          NSApp.terminate(nil)
        }
      #endif
    }
  }

  nonisolated static func defaultStartupOutput(_ line: String) {
    print(line)
  }

  private var isUITesting: Bool {
    BootstrapEnvironment.isUITesting()
  }

  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
        .task {
          if isUITesting { await model.connect() }
        }
    }
  }
}

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
