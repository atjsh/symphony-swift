// Batch39MutationHardeningTests.swift
// -----------------------------------------------------------------
// Mutation targets:
//
// SQLiteAgentRunEventSink.swift — persist error logging paths:
//   Mutation removes catch blocks that log event_sink_persist_start_failed,
//   event_sink_persist_transition_failed, event_sink_persist_event_failed,
//   event_sink_persist_completion_failed when store operations throw.
//
// OrchestratorEngine.swift — delegate persistence failure logs:
//   Mutation removes catch blocks that log issue_sync_persistence_failed and
//   snapshot_refresh_persistence_failed when stateStore.upsertIssue throws.
// -----------------------------------------------------------------

import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - SQLiteAgentRunEventSink Persist Error Logs

@Suite("SQLiteAgentRunEventSink persist error logging")
struct EventSinkPersistErrorLogTests {

  /// Helper: create a fresh store, optionally seed it with a start, then close the DB.
  private func makeSinkWithClosedStore(seedStart: Bool = false) throws -> (
    sink: SQLiteAgentRunEventSink,
    startInfo: AgentRunStartInfo,
    context: RunContext
  ) {
    let dir = try makeAgentRunSinkTemporaryDirectory()
    let store = try SQLiteServerStateStore(
      databaseURL: dir.appendingPathComponent("persist-error.sqlite3"))
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue()
    let context = try makeAgentRunSinkContext(issueID: issue.id, number: issue.number)
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: ProviderName.codex.rawValue,
      sessionID: SessionID("s-persist-err"),
      workspacePath: "/tmp/symphony/test"
    )

    if seedStart {
      sink.runDidStart(startInfo)
    }

    store.diagnostics.closeDatabase()
    return (sink, startInfo, context)
  }

  @Test func persistStartFailureLogsError() async throws {
    let (sink, startInfo, _) = try makeSinkWithClosedStore(seedStart: false)

    let (_, logs) = try await withCapturedRuntimeLogs {
      sink.runDidStart(startInfo)
    }

    let errorLogs = logs.filter { $0.entry.event == "event_sink_persist_start_failed" }
    #expect(errorLogs.count == 1)
    #expect(errorLogs[0].entry.level == "error")
    #expect(errorLogs[0].entry.runID == startInfo.context.runID.rawValue)
    #expect(errorLogs[0].entry.sessionID == startInfo.sessionID.rawValue)
  }

  @Test func persistTransitionFailureLogsError() async throws {
    let (sink, _, context) = try makeSinkWithClosedStore(seedStart: true)

    let (_, logs) = try await withCapturedRuntimeLogs {
      sink.runDidTransition(context, to: .streamingTurn)
    }

    let errorLogs = logs.filter { $0.entry.event == "event_sink_persist_transition_failed" }
    #expect(errorLogs.count == 1)
    #expect(errorLogs[0].entry.level == "error")
    #expect(errorLogs[0].entry.runID == context.runID.rawValue)
  }

  @Test func persistEventFailureLogsError() async throws {
    let (sink, startInfo, _) = try makeSinkWithClosedStore(seedStart: true)

    let event = AgentRawEvent(
      sessionID: startInfo.sessionID,
      provider: startInfo.provider,
      sequence: EventSequence(0),
      timestamp: "2026-04-09T00:00:00Z",
      rawJSON: #"{"type":"message"}"#,
      providerEventType: "message",
      normalizedEventKind: "message"
    )

    let (_, logs) = try await withCapturedRuntimeLogs {
      sink.runDidReceiveEvent(event)
    }

    let errorLogs = logs.filter { $0.entry.event == "event_sink_persist_event_failed" }
    #expect(errorLogs.count == 1)
    #expect(errorLogs[0].entry.level == "error")
    #expect(errorLogs[0].entry.sessionID == startInfo.sessionID.rawValue)
  }

  @Test func persistCompletionFailureLogsError() async throws {
    let (sink, startInfo, context) = try makeSinkWithClosedStore(seedStart: true)

    let result = AgentRunResult(
      context: context,
      sessionID: startInfo.sessionID,
      finalState: .succeeded,
      eventCount: 0,
      error: nil
    )

    let (_, logs) = try await withCapturedRuntimeLogs {
      sink.runDidComplete(result)
    }

    let errorLogs = logs.filter { $0.entry.event == "event_sink_persist_completion_failed" }
    #expect(errorLogs.count == 1)
    #expect(errorLogs[0].entry.level == "error")
    #expect(errorLogs[0].entry.runID == context.runID.rawValue)
    #expect(errorLogs[0].entry.sessionID == startInfo.sessionID.rawValue)
  }
}

// MARK: - EngineOrchestratorDelegate Persistence Failure Logs

@Suite("EngineOrchestratorDelegate persistence failure logs")
struct DelegatePersistenceFailureLogTests {

  private func makeClosedStore() throws -> SQLiteServerStateStore {
    let dir = try makeTemporaryDirectory()
    let store = try SQLiteServerStateStore(
      databaseURL: dir.appendingPathComponent("delegate-err.sqlite3"))
    store.diagnostics.closeDatabase()
    return store
  }

  @Test func issueSyncPersistenceFailureLogsError() async throws {
    let store = try makeClosedStore()
    let observer = CollectingEngineObserver()
    let wsManager = StubWorkspaceManager()
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer, stateStore: store)

    let issue = try makeIssue()

    let (_, logs) = try await withCapturedRuntimeLogs {
      await delegate.orchestratorDidSyncIssues([issue])
    }

    let errorLogs = logs.filter { $0.entry.event == "issue_sync_persistence_failed" }
    #expect(errorLogs.count == 1)
    #expect(errorLogs[0].entry.level == "error")
    #expect(errorLogs[0].entry.issueID == issue.id.rawValue)
    #expect(errorLogs[0].entry.issueIdentifier == issue.identifier.rawValue)
  }

  @Test func snapshotRefreshPersistenceFailureLogsError() async throws {
    let store = try makeClosedStore()
    let observer = CollectingEngineObserver()
    let wsManager = StubWorkspaceManager()
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer, stateStore: store)

    let issue = try makeIssue()

    let (_, logs) = try await withCapturedRuntimeLogs {
      await delegate.orchestratorDidRefreshSnapshot(issue: issue)
    }

    let errorLogs = logs.filter { $0.entry.event == "snapshot_refresh_persistence_failed" }
    #expect(errorLogs.count == 1)
    #expect(errorLogs[0].entry.level == "error")
    #expect(errorLogs[0].entry.issueID == issue.id.rawValue)
    #expect(errorLogs[0].entry.issueIdentifier == issue.identifier.rawValue)
  }
}
