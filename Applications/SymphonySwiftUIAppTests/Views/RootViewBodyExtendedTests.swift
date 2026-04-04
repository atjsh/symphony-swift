// swiftlint:disable force_try
import SwiftUI
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

#if canImport(AppKit)
  import AppKit
#endif
#if canImport(UIKit)
  import UIKit
#endif

@MainActor
@Suite("RootView – Body Extended", .tags(.views))
struct RootViewBodyExtendedTests {
  @Test func BodyEvaluatesWithTokensErrorBlockersLabelsAndAllEventKinds() throws {
    let model = SymphonyOperatorModel(
      client: PassiveSymphonyAPIClient(),
      initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
    )

    let blockerRef = BlockerReference(
      issueID: IssueID("issue-99"),
      identifier: try! IssueIdentifier(validating: "atjsh/example#99"),
      state: "in_progress",
      issueState: "OPEN",
      url: "https://example.com/issues/99"
    )
    let issueWithBlockers = SymphonyShared.Issue(
      id: IssueID("issue-42"),
      identifier: try! IssueIdentifier(validating: "atjsh/example#42"),
      repository: "atjsh/example",
      number: 42,
      title: "Blocked issue",
      description: "Testing all fields",
      priority: 1,
      state: "in_progress",
      issueState: "OPEN",
      projectItemID: "item-42",
      url: "https://example.com/issues/42",
      labels: ["Bug", "Server"],
      blockedBy: [blockerRef],
      createdAt: "2026-03-24T00:00:00Z",
      updatedAt: "2026-03-24T01:00:00Z"
    )
    let session = AgentSession(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      providerSessionID: "ps-42",
      providerThreadID: "thread-42",
      providerTurnID: "turn-42",
      providerRunID: "provider-run-42",
      runID: RunID("run-42"),
      providerProcessPID: nil,
      status: "active",
      lastEventType: "message",
      lastEventAt: "2026-03-24T01:00:00Z",
      turnCount: 5,
      tokenUsage: try! TokenUsage(inputTokens: 10, outputTokens: 20),
      latestRateLimitPayload: #"{"remaining":12,"reset_at":"2026-03-24T01:05:00Z"}"#
    )
    let outputOnlySession = AgentSession(
      sessionID: SessionID("session-43"),
      provider: "copilot",
      providerSessionID: nil,
      providerThreadID: nil,
      providerTurnID: nil,
      providerRunID: nil,
      runID: RunID("run-43"),
      providerProcessPID: nil,
      status: "streaming_turn",
      lastEventType: "usage",
      lastEventAt: nil,
      turnCount: 1,
      tokenUsage: try! TokenUsage(outputTokens: 8),
      latestRateLimitPayload: nil
    )
    let totalOnlySession = AgentSession(
      sessionID: SessionID("session-44"),
      provider: "codex",
      providerSessionID: nil,
      providerThreadID: nil,
      providerTurnID: nil,
      providerRunID: nil,
      runID: RunID("run-44"),
      providerProcessPID: nil,
      status: "waiting_for_retry",
      lastEventType: "usage",
      lastEventAt: nil,
      turnCount: 1,
      tokenUsage: try! TokenUsage(totalTokens: 13),
      latestRateLimitPayload: nil
    )
    model.issueDetail = IssueDetail(
      issue: issueWithBlockers,
      latestRun: makeRunSummary(),
      workspacePath: "/tmp/ws",
      recentSessions: [session, outputOnlySession, totalOnlySession]
    )
    model.issues = [
      IssueSummary(
        issueID: IssueID("issue-42"),
        identifier: try! IssueIdentifier(validating: "atjsh/example#42"),
        title: "Priority issue",
        state: "in_progress",
        issueState: "OPEN",
        priority: 1,
        currentProvider: "claude_code",
        currentRunID: RunID("run-42"),
        currentSessionID: SessionID("session-42")
      ),
      IssueSummary(
        issueID: IssueID("issue-43"),
        identifier: try! IssueIdentifier(validating: "atjsh/example#43"),
        title: "No priority issue",
        state: "queued",
        issueState: "OPEN",
        priority: nil,
        currentProvider: nil,
        currentRunID: nil,
        currentSessionID: nil
      ),
    ]
    model.runDetail = RunDetail(
      runID: RunID("run-42"),
      issueID: IssueID("issue-42"),
      issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#42"),
      attempt: 1,
      status: "failed",
      provider: "claude_code",
      providerSessionID: "ps-42",
      providerRunID: nil,
      startedAt: "2026-03-24T00:00:00Z",
      endedAt: "2026-03-24T01:00:00Z",
      workspacePath: "/tmp/ws",
      sessionID: SessionID("session-42"),
      lastError: "Provider timed out after 300s",
      issue: issueWithBlockers,
      turnCount: 5,
      lastAgentEventType: "error",
      lastAgentMessage: "Timeout exceeded",
      tokens: try! TokenUsage(inputTokens: 1000, outputTokens: 500),
      logs: RunLogStats(eventCount: 10, latestSequence: EventSequence(10))
    )
    model.logEvents = [
      makeEvent(sequence: 1, kind: "message", rawJSON: #"{"message":"hello"}"#),
      makeEvent(sequence: 2, kind: "tool_call", rawJSON: #"{"arguments":"/bin/zsh -lc pwd"}"#),
      makeEvent(sequence: 3, kind: "tool_result", rawJSON: #"{"result":"/tmp/example"}"#),
      makeEvent(sequence: 4, kind: "status", rawJSON: #"{"status":"done"}"#),
      makeEvent(sequence: 5, kind: "usage", rawJSON: #"{"total_tokens":42}"#),
      makeEvent(sequence: 6, kind: "approval_request", rawJSON: #"{"message":"approve?"}"#),
      makeEvent(sequence: 7, kind: "error", rawJSON: #"{"message":"fail"}"#),
      AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(8),
        timestamp: "2026-03-24T00:00:08Z",
        rawJSON: #"{"payload":{"notes":"inspect raw payload"}}"#,
        providerEventType: "provider_custom",
        normalizedEventKind: "unexpected_kind"
      ),
    ]

    let view = SymphonyOperatorRootView(model: model)
    exercise(view)
  }

  @Test func RecentSessionHasVisibleTokenUsageCoversInputOutputTotalAndEmptyBranches() throws {
    #expect(recentSessionHasVisibleTokenUsage(try TokenUsage(inputTokens: 1)))
    #expect(recentSessionHasVisibleTokenUsage(try TokenUsage(outputTokens: 2)))
    #expect(recentSessionHasVisibleTokenUsage(try TokenUsage(totalTokens: 3)))
    #expect(recentSessionHasVisibleTokenUsage(try TokenUsage()) == false)

    #if canImport(AppKit)
      let compactTheme = OperatorTheme(compact: true)
      let intrinsicMetricsHost = NSHostingView(
        rootView: AnyView(
          MetricsStrip(
            theme: compactTheme,
            metrics: [("Input", "1,200"), ("Output", "950"), ("Total", "2,150")]
          )
        )
      )
      #expect(intrinsicMetricsHost.fittingSize.width > 0)

      let intrinsicEmptyFlowHost = NSHostingView(
        rootView: AnyView(
          OperatorFlowLayout(spacing: 8) {}
        )
      )
      #expect(intrinsicEmptyFlowHost.fittingSize.height >= 0)
    #endif

    let theme = OperatorTheme(compact: true)
    render(
      host(
        AnyView(
          VStack(alignment: .leading, spacing: 12) {
            OperatorFlowLayout(spacing: 8) {}
            MetricsStrip(
              theme: theme,
              metrics: [("Input", "1,200"), ("Output", "950"), ("Total", "2,150")]
            )
            TokenUsageStrip(
              theme: theme,
              tokens: try! TokenUsage(inputTokens: 1_200, outputTokens: 950, totalTokens: 2_150)
            )
            TokenUsageStrip(theme: theme, tokens: try! TokenUsage())
          }
        ),
        width: 320,
        height: 320
      )
    )
  }
}

// swiftlint:enable force_try
