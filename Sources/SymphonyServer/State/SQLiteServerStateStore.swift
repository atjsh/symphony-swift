import Foundation
import SQLite3
import SymphonyShared
import SymphonyServerCore

// SAFETY: @unchecked Sendable — all database operations go through `lock.sync`
// which wraps NSLock for exclusive access to the SQLite handle.
public final class SQLiteServerStateStore: @unchecked Sendable {
  private let databaseURL: URL
  private let lock = NSLock()
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let eventObserver: (@Sendable (AgentRawEvent) -> Void)?
  private(set) var database: OpaquePointer?

  public init(
    databaseURL: URL,
    eventObserver: (@Sendable (AgentRawEvent) -> Void)? = nil
  ) throws {
    self.databaseURL = databaseURL
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()
    self.eventObserver = eventObserver

    let parent = databaseURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

    var handle: OpaquePointer?
    guard
      sqlite3_open_v2(
        databaseURL.path,
        &handle,
        SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
        nil
      ) == SQLITE_OK, let handle
    else {
      throw SymphonyServerError.sqlite("Failed to open SQLite database at \(databaseURL.path).")
    }

    self.database = handle
    do {
      try execute("PRAGMA foreign_keys = ON;")
      try installSchema()
    } catch {
      closeDatabase(handle)
      throw error
    }
  }

  deinit {
    closeDatabase(database)
  }

  public func upsertIssue(_ issue: Issue) throws {
    let snapshot = try encode(issue)
    try execute(
      """
      INSERT INTO issues (
          issue_id,
          identifier,
          title,
          state,
          issue_state,
          priority,
          updated_at,
          snapshot_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(issue_id) DO UPDATE SET
          identifier = excluded.identifier,
          title = excluded.title,
          state = excluded.state,
          issue_state = excluded.issue_state,
          priority = excluded.priority,
          updated_at = excluded.updated_at,
          snapshot_json = excluded.snapshot_json;
      """,
      bindings: [
        .text(issue.id.rawValue),
        .text(issue.identifier.rawValue),
        .text(issue.title),
        .text(issue.state),
        .text(issue.issueState),
        .int(issue.priority),
        .text(issue.updatedAt),
        .text(snapshot),
      ]
    )
  }

  public func upsertRun(_ run: RunDetail) throws {
    try upsertIssue(run.issue)
    let snapshot = try encode(run)
    try execute(
      """
      INSERT INTO runs (
          run_id,
          issue_id,
          started_at,
          status,
          provider,
          session_id,
          workspace_path,
          snapshot_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(run_id) DO UPDATE SET
          issue_id = excluded.issue_id,
          started_at = excluded.started_at,
          status = excluded.status,
          provider = excluded.provider,
          session_id = excluded.session_id,
          workspace_path = excluded.workspace_path,
          snapshot_json = excluded.snapshot_json;
      """,
      bindings: [
        .text(run.runID.rawValue),
        .text(run.issueID.rawValue),
        .text(run.startedAt),
        .text(run.status),
        .text(run.provider),
        .text(run.sessionID?.rawValue),
        .text(run.workspacePath),
        .text(snapshot),
      ]
    )
    try execute(
      """
      INSERT INTO workspaces (issue_id, workspace_path, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(issue_id) DO UPDATE SET
          workspace_path = excluded.workspace_path,
          updated_at = excluded.updated_at;
      """,
      bindings: [
        .text(run.issueID.rawValue),
        .text(run.workspacePath),
        .text(run.startedAt),
      ]
    )
  }

  public func upsertSession(_ session: AgentSession) throws {
    let snapshot = try encode(session)
    try execute(
      """
      INSERT INTO agent_sessions (
          session_id,
          run_id,
          provider,
          last_event_at,
          snapshot_json
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(session_id) DO UPDATE SET
          run_id = excluded.run_id,
          provider = excluded.provider,
          last_event_at = excluded.last_event_at,
          snapshot_json = excluded.snapshot_json;
      """,
      bindings: [
        .text(session.sessionID.rawValue),
        .text(session.runID.rawValue),
        .text(session.provider),
        .text(session.lastEventAt),
        .text(snapshot),
      ]
    )
  }

  public func appendEvent(
    sessionID: SessionID,
    provider: String,
    timestamp: String,
    rawJSON: String,
    providerEventType: String,
    normalizedEventKind: String?
  ) throws -> AgentRawEvent {
    let sequence = EventSequence(try nextSequence(for: sessionID))
    let event = AgentRawEvent(
      sessionID: sessionID,
      provider: provider,
      sequence: sequence,
      timestamp: timestamp,
      rawJSON: rawJSON,
      providerEventType: providerEventType,
      normalizedEventKind: normalizedEventKind
    )
    try execute(
      """
      INSERT INTO agent_events (
          session_id,
          sequence,
          provider,
          timestamp,
          raw_json,
          provider_event_type,
          normalized_event_kind
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
      """,
      bindings: [
        .text(sessionID.rawValue),
        .int(sequence.rawValue),
        .text(provider),
        .text(timestamp),
        .text(rawJSON),
        .text(providerEventType),
        .text(normalizedEventKind),
      ]
    )

    if var session = try session(sessionID: sessionID) {
      session = AgentSession(
        sessionID: session.sessionID,
        provider: session.provider,
        providerSessionID: session.providerSessionID,
        providerThreadID: session.providerThreadID,
        providerTurnID: session.providerTurnID,
        providerRunID: session.providerRunID,
        runID: session.runID,
        providerProcessPID: session.providerProcessPID,
        status: session.status,
        lastEventType: providerEventType,
        lastEventAt: timestamp,
        turnCount: session.turnCount,
        tokenUsage: session.tokenUsage,
        latestRateLimitPayload: session.latestRateLimitPayload
      )
      try upsertSession(session)
    }

    eventObserver?(event)
    return event
  }

  // MARK: - Schema

  func installSchema() throws {
    try execute(
      """
      CREATE TABLE IF NOT EXISTS issues (
          issue_id TEXT PRIMARY KEY,
          identifier TEXT NOT NULL,
          title TEXT NOT NULL,
          state TEXT NOT NULL,
          issue_state TEXT NOT NULL,
          priority INTEGER,
          updated_at TEXT,
          snapshot_json TEXT NOT NULL
      );
      """
    )
    try execute(
      """
      CREATE TABLE IF NOT EXISTS runs (
          run_id TEXT PRIMARY KEY,
          issue_id TEXT NOT NULL,
          started_at TEXT NOT NULL,
          status TEXT NOT NULL,
          provider TEXT NOT NULL,
          session_id TEXT,
          workspace_path TEXT NOT NULL,
          snapshot_json TEXT NOT NULL
      );
      """
    )
    try execute(
      """
      CREATE TABLE IF NOT EXISTS agent_sessions (
          session_id TEXT PRIMARY KEY,
          run_id TEXT NOT NULL,
          provider TEXT NOT NULL,
          last_event_at TEXT,
          snapshot_json TEXT NOT NULL
      );
      """
    )
    try execute(
      """
      CREATE TABLE IF NOT EXISTS workspaces (
          issue_id TEXT PRIMARY KEY,
          workspace_path TEXT NOT NULL,
          updated_at TEXT NOT NULL
      );
      """
    )
    try execute(
      """
      CREATE TABLE IF NOT EXISTS agent_events (
          session_id TEXT NOT NULL,
          sequence INTEGER NOT NULL,
          provider TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          raw_json TEXT NOT NULL,
          provider_event_type TEXT NOT NULL,
          normalized_event_kind TEXT,
          PRIMARY KEY (session_id, sequence)
      );
      """
    )
  }

  // MARK: - SQLite Helpers

  func nextSequence(for sessionID: SessionID) throws -> Int {
    try queryOne(
      "SELECT COALESCE(MAX(sequence), 0) + 1 FROM agent_events WHERE session_id = ?;",
      bindings: [.text(sessionID.rawValue)],
      map: { statement in
        columnInt(statement, index: 0)
      }
    )!
  }

  func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
    try lock.sync {
      let statement = try prepare(sql)
      defer { sqlite3_finalize(statement) }
      try bind(bindings, to: statement)
      try stepUntilDone(statement)
    }
  }

  func query<T>(
    _ sql: String, bindings: [SQLiteBinding] = [], row: (OpaquePointer) throws -> T
  ) throws -> [T] {
    try lock.sync {
      let statement = try prepare(sql)
      defer { sqlite3_finalize(statement) }
      try bind(bindings, to: statement)
      return try stepRows(statement, row: row)
    }
  }

  func queryOne<T>(
    _ sql: String, bindings: [SQLiteBinding] = [], map: (OpaquePointer) throws -> T
  ) throws -> T? {
    try query(sql, bindings: bindings, row: map).first
  }

  func prepare(_ sql: String) throws -> OpaquePointer {
    guard let database else {
      throw SymphonyServerError.sqlite("SQLite database is closed.")
    }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw sqliteError(message: "Failed to prepare SQLite statement.")
    }
    return statement
  }

  func stepUntilDone(_ statement: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw sqliteError(message: "Failed to execute SQLite statement.")
    }
  }

  func stepRows<T>(_ statement: OpaquePointer, row: (OpaquePointer) throws -> T) throws
    -> [T]
  {
    var rows = [T]()
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      rows.append(try row(statement))
      result = sqlite3_step(statement)
    }
    guard result == SQLITE_DONE else {
      throw sqliteError(message: "Failed to query SQLite statement.")
    }
    return rows
  }

  func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer) throws {
    for (offset, binding) in bindings.enumerated() {
      let index = Int32(offset + 1)
      let result: Int32
      switch binding {
      case .int(let value):
        if let value {
          result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        } else {
          result = sqlite3_bind_null(statement, index)
        }
      case .text(let value):
        if let value {
          result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
          result = sqlite3_bind_null(statement, index)
        }
      }
      guard result == SQLITE_OK else {
        throw sqliteError(message: "Failed to bind SQLite statement value.")
      }
    }
  }

  func encode<T: Encodable>(_ value: T) throws -> String {
    do {
      return String(decoding: try encoder.encode(value), as: UTF8.self)
    } catch {
      throw SymphonyServerError.encoding("Failed to encode JSON snapshot.")
    }
  }

  func decode<T: Decodable>(
    _ type: T.Type, fromColumn index: Int32, statement: OpaquePointer
  ) throws -> T {
    guard let text = columnOptionalString(statement, index: index) else {
      throw SymphonyServerError.encoding("Missing JSON snapshot in SQLite row.")
    }

    do {
      return try decoder.decode(T.self, from: Data(text.utf8))
    } catch {
      throw SymphonyServerError.encoding("Failed to decode JSON snapshot.")
    }
  }

  func sqliteError(message: String) -> SymphonyServerError {
    let detail =
      database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown sqlite error"
    return .sqlite("\(message) \(detail)")
  }

  func closeDatabase(_ handle: OpaquePointer?) {
    guard let handle else {
      return
    }
    sqlite3_close(handle)
    if database == handle {
      database = nil
    }
  }
}

fileprivate extension NSLock {
  func sync<T>(_ body: () throws -> T) throws -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
