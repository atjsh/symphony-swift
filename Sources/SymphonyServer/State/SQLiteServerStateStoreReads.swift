import Foundation
import SQLite3
import SymphonyShared
import SymphonyServerCore

extension SQLiteServerStateStore {

  public func issues() throws -> [IssueSummary] {
    let loadedIssues: [Issue] = try query(
      "SELECT snapshot_json FROM issues ORDER BY COALESCE(priority, 999999), identifier ASC;"
    ) { statement in
      try decode(Issue.self, fromColumn: 0, statement: statement)
    }

    return try loadedIssues.map { issue in
      let latestRun = try currentRun(for: issue.id)
      return IssueSummary(
        issueID: issue.id,
        identifier: issue.identifier,
        title: issue.title,
        state: issue.state,
        issueState: issue.issueState,
        priority: issue.priority,
        currentProvider: latestRun?.provider,
        currentRunID: latestRun?.runID,
        currentSessionID: latestRun?.sessionID
      )
    }
  }

  func currentRun(for issueID: IssueID) throws -> RunSummary? {
    guard let latestRun = try latestRun(for: issueID) else { return nil }
    guard Self.isCurrentRunStatus(latestRun.status) else { return nil }
    return latestRun
  }

  public func issueDetail(id: IssueID) throws -> IssueDetail? {
    guard
      let issue = try queryOne(
        "SELECT snapshot_json FROM issues WHERE issue_id = ? LIMIT 1;",
        bindings: [.text(id.rawValue)],
        map: { statement in
          try decode(Issue.self, fromColumn: 0, statement: statement)
        }
      )
    else {
      return nil
    }

    let recentSessions = try query(
      """
      SELECT s.snapshot_json
      FROM agent_sessions s
      INNER JOIN runs r ON r.run_id = s.run_id
      WHERE r.issue_id = ?
      ORDER BY COALESCE(s.last_event_at, '') DESC, s.session_id DESC;
      """,
      bindings: [.text(id.rawValue)]
    ) { statement in
      try decode(AgentSession.self, fromColumn: 0, statement: statement)
    }

    let workspacePath = try queryOne(
      "SELECT workspace_path FROM workspaces WHERE issue_id = ? LIMIT 1;",
      bindings: [.text(id.rawValue)],
      map: { statement in
        columnString(statement, index: 0)
      }
    )

    return IssueDetail(
      issue: issue,
      latestRun: try latestRun(for: id),
      workspacePath: workspacePath,
      recentSessions: recentSessions
    )
  }

  public func runDetail(id: RunID) throws -> RunDetail? {
    guard
      var detail = try queryOne(
        "SELECT snapshot_json FROM runs WHERE run_id = ? LIMIT 1;",
        bindings: [.text(id.rawValue)],
        map: { statement in
          try decode(RunDetail.self, fromColumn: 0, statement: statement)
        }
      )
    else {
      return nil
    }

    guard let sessionID = detail.sessionID else {
      return detail
    }

    let logs = try logStats(sessionID: sessionID)
    detail = RunDetail(
      runID: detail.runID,
      issueID: detail.issueID,
      issueIdentifier: detail.issueIdentifier,
      attempt: detail.attempt,
      status: detail.status,
      provider: detail.provider,
      providerSessionID: detail.providerSessionID,
      providerRunID: detail.providerRunID,
      startedAt: detail.startedAt,
      endedAt: detail.endedAt,
      workspacePath: detail.workspacePath,
      sessionID: detail.sessionID,
      lastError: detail.lastError,
      issue: detail.issue,
      turnCount: detail.turnCount,
      lastAgentEventType: detail.lastAgentEventType,
      lastAgentMessage: detail.lastAgentMessage,
      tokens: detail.tokens,
      logs: logs
    )
    return detail
  }

  public func session(sessionID: SessionID) throws -> AgentSession? {
    try queryOne(
      "SELECT snapshot_json FROM agent_sessions WHERE session_id = ? LIMIT 1;",
      bindings: [.text(sessionID.rawValue)],
      map: { statement in
        try decode(AgentSession.self, fromColumn: 0, statement: statement)
      }
    )
  }

  public func logs(sessionID: SessionID, cursor: EventCursor?, limit: Int) throws
    -> LogEntriesResponse?
  {
    guard let session = try session(sessionID: sessionID) else {
      return nil
    }
    if let cursorSessionID = cursor?.sessionID, cursorSessionID != sessionID {
      return nil
    }

    let boundedLimit = max(1, min(limit, 100))
    let lastDelivered = cursor?.lastDeliveredSequence?.rawValue ?? 0
    let rows = try query(
      """
      SELECT session_id, provider, sequence, timestamp, raw_json, provider_event_type, normalized_event_kind
      FROM agent_events
      WHERE session_id = ? AND sequence > ?
      ORDER BY sequence ASC
      LIMIT ?;
      """,
      bindings: [.text(sessionID.rawValue), .int(lastDelivered), .int(boundedLimit + 1)]
    ) { statement in
      AgentRawEvent(
        sessionID: SessionID(columnString(statement, index: 0)),
        provider: columnString(statement, index: 1),
        sequence: EventSequence(columnInt(statement, index: 2)),
        timestamp: columnString(statement, index: 3),
        rawJSON: columnString(statement, index: 4),
        providerEventType: columnString(statement, index: 5),
        normalizedEventKind: columnOptionalString(statement, index: 6)
      )
    }

    let hasMore = rows.count > boundedLimit
    let items = hasMore ? Array(rows.prefix(boundedLimit)) : rows
    let nextCursor = items.last.map {
      EventCursor(sessionID: sessionID, lastDeliveredSequence: $0.sequence)
    }
    return LogEntriesResponse(
      sessionID: sessionID,
      provider: session.provider,
      items: items,
      nextCursor: nextCursor,
      hasMore: hasMore
    )
  }

  func latestRun(for issueID: IssueID) throws -> RunSummary? {
    try queryOne(
      """
      SELECT snapshot_json
      FROM runs
      WHERE issue_id = ?
      ORDER BY started_at DESC, run_id DESC
      LIMIT 1;
      """,
      bindings: [.text(issueID.rawValue)],
      map: { statement in
        let detail = try decode(RunDetail.self, fromColumn: 0, statement: statement)
        return RunSummary(
          runID: detail.runID,
          issueID: detail.issueID,
          issueIdentifier: detail.issueIdentifier,
          attempt: detail.attempt,
          status: detail.status,
          provider: detail.provider,
          providerSessionID: detail.providerSessionID,
          providerRunID: detail.providerRunID,
          startedAt: detail.startedAt,
          endedAt: detail.endedAt,
          workspacePath: detail.workspacePath,
          sessionID: detail.sessionID,
          lastError: detail.lastError
        )
      }
    )
  }

  static func isCurrentRunStatus(_ status: String) -> Bool {
    if let lifecycleState = RunLifecycleState(rawValue: status) {
      return lifecycleState.isActive
    }

    switch status.lowercased() {
    case "running", "queued", "active",
      "preparingworkspace", "buildingprompt", "launchingagentprocess",
      "initializingsession", "streamingturn", "finishing":
      return true
    case "succeeded", "failed", "timedout", "stalled",
      "canceledbyreconciliation", "cancelled", "canceled",
      "done", "complete", "completed":
      return false
    default:
      return true
    }
  }

  func logStats(sessionID: SessionID) throws -> RunLogStats {
    let tuple = try queryOne(
      """
      SELECT COUNT(*), MAX(sequence)
      FROM agent_events
      WHERE session_id = ?;
      """,
      bindings: [.text(sessionID.rawValue)],
      map: { statement in
        (columnInt(statement, index: 0), columnOptionalInt(statement, index: 1))
      }
    )!

    return RunLogStats(
      eventCount: tuple.0,
      latestSequence: tuple.1.map(EventSequence.init)
    )
  }
}
