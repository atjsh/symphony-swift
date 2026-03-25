import Foundation
import SQLite3
import SymphonyShared

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SymphonyRuntimeError: Error, Equatable, Sendable {
    case sqlite(String)
    case encoding(String)
}

public final class SQLiteServerStateStore: @unchecked Sendable {
    private let databaseURL: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var database: OpaquePointer?

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        let parent = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            throw SymphonyRuntimeError.sqlite("Failed to open SQLite database at \(databaseURL.path).")
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

        return event
    }

    public func issues() throws -> [IssueSummary] {
        let loadedIssues: [Issue] = try query(
            "SELECT snapshot_json FROM issues ORDER BY COALESCE(priority, 999999), identifier ASC;"
        ) { statement in
            try decode(Issue.self, fromColumn: 0, statement: statement)
        }

        return try loadedIssues.map { issue in
            let latestRun = try latestRun(for: issue.id)
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

    public func issueDetail(id: IssueID) throws -> IssueDetail? {
        guard let issue = try queryOne(
            "SELECT snapshot_json FROM issues WHERE issue_id = ? LIMIT 1;",
            bindings: [.text(id.rawValue)],
            map: { statement in
                try decode(Issue.self, fromColumn: 0, statement: statement)
            }
        ) else {
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
        guard var detail = try queryOne(
            "SELECT snapshot_json FROM runs WHERE run_id = ? LIMIT 1;",
            bindings: [.text(id.rawValue)],
            map: { statement in
                try decode(RunDetail.self, fromColumn: 0, statement: statement)
            }
        ) else {
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

    public func logs(sessionID: SessionID, cursor: EventCursor?, limit: Int) throws -> LogEntriesResponse? {
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
        let nextCursor = items.last.map { EventCursor(sessionID: sessionID, lastDeliveredSequence: $0.sequence) }
        return LogEntriesResponse(
            sessionID: sessionID,
            provider: session.provider,
            items: items,
            nextCursor: nextCursor,
            hasMore: hasMore
        )
    }

    private func latestRun(for issueID: IssueID) throws -> RunSummary? {
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

    private func logStats(sessionID: SessionID) throws -> RunLogStats {
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

    private func nextSequence(for sessionID: SessionID) throws -> Int {
        try queryOne(
            "SELECT COALESCE(MAX(sequence), 0) + 1 FROM agent_events WHERE session_id = ?;",
            bindings: [.text(sessionID.rawValue)],
            map: { statement in
                columnInt(statement, index: 0)
            }
        )!
    }

    private func installSchema() throws {
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

    private func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        try lock.sync {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)
            try stepUntilDone(statement)
        }
    }

    private func query<T>(_ sql: String, bindings: [SQLiteBinding] = [], row: (OpaquePointer) throws -> T) throws -> [T] {
        try lock.sync {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)
            return try stepRows(statement, row: row)
        }
    }

    private func queryOne<T>(_ sql: String, bindings: [SQLiteBinding] = [], map: (OpaquePointer) throws -> T) throws -> T? {
        try query(sql, bindings: bindings, row: map).first
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else {
            throw SymphonyRuntimeError.sqlite("SQLite database is closed.")
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw sqliteError(message: "Failed to prepare SQLite statement.")
        }
        return statement
    }

    private func stepUntilDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(message: "Failed to execute SQLite statement.")
        }
    }

    private func stepRows<T>(_ statement: OpaquePointer, row: (OpaquePointer) throws -> T) throws -> [T] {
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

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer) throws {
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

    private func encode<T: Encodable>(_ value: T) throws -> String {
        do {
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        } catch {
            throw SymphonyRuntimeError.encoding("Failed to encode JSON snapshot.")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, fromColumn index: Int32, statement: OpaquePointer) throws -> T {
        guard let text = columnOptionalString(statement, index: index) else {
            throw SymphonyRuntimeError.encoding("Missing JSON snapshot in SQLite row.")
        }

        do {
            return try decoder.decode(T.self, from: Data(text.utf8))
        } catch {
            throw SymphonyRuntimeError.encoding("Failed to decode JSON snapshot.")
        }
    }

    private func sqliteError(message: String) -> SymphonyRuntimeError {
        let detail = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown sqlite error"
        return .sqlite("\(message) \(detail)")
    }

    private func closeDatabase(_ handle: OpaquePointer?) {
        guard let handle else {
            return
        }
        sqlite3_close(handle)
        if database == handle {
            database = nil
        }
    }
}

public struct SymphonyAPIRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct SymphonyHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public final class SymphonyHTTPAPI: @unchecked Sendable {
    private let store: SQLiteServerStateStore
    private let version: String
    private let trackerKind: String
    private let now: @Sendable () -> Date
    private let refresh: @Sendable () -> Void
    private let encoder: JSONEncoder

    public init(
        store: SQLiteServerStateStore,
        version: String,
        trackerKind: String,
        now: (@Sendable () -> Date)? = nil,
        refresh: (@Sendable () -> Void)? = nil
    ) {
        self.store = store
        self.version = version
        self.trackerKind = trackerKind
        self.now = now ?? Date.init
        self.refresh = refresh ?? {}
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    public func respond(to request: SymphonyAPIRequest) throws -> SymphonyHTTPResponse {
        let components = URLComponents(string: "http://localhost\(request.path)")!
        let path = components.path
        let method = request.method.uppercased()

        switch (method, path) {
        case ("GET", "/api/v1/health"):
            return try ok(HealthResponse(
                status: "ok",
                serverTime: Self.iso8601(now()),
                version: version,
                trackerKind: trackerKind
            ))
        case ("GET", "/api/v1/issues"):
            return try ok(IssuesResponse(items: store.issues()))
        case ("POST", "/api/v1/refresh"):
            refresh()
            return try response(statusCode: 202, value: RefreshResponse(queued: true, requestedAt: Self.iso8601(now())))
        default:
            break
        }

        if path.hasPrefix("/api/v1/issues/") {
            guard method == "GET" else {
                return try error(statusCode: 405, code: "method_not_allowed", message: "This endpoint only supports GET.")
            }
            let issueID = String(path.dropFirst("/api/v1/issues/".count))
            guard let detail = try store.issueDetail(id: IssueID(issueID)) else {
                return try error(statusCode: 404, code: "issue_not_found", message: "Issue \(issueID) was not found.")
            }
            return try ok(detail)
        }

        if path.hasPrefix("/api/v1/runs/") {
            guard method == "GET" else {
                return try error(statusCode: 405, code: "method_not_allowed", message: "This endpoint only supports GET.")
            }
            let runID = String(path.dropFirst("/api/v1/runs/".count))
            guard let detail = try store.runDetail(id: RunID(runID)) else {
                return try error(statusCode: 404, code: "run_not_found", message: "Run \(runID) was not found.")
            }
            return try ok(detail)
        }

        if path.hasPrefix("/api/v1/logs/") {
            guard method == "GET" else {
                return try error(statusCode: 405, code: "method_not_allowed", message: "This endpoint only supports GET.")
            }
            let sessionID = SessionID(String(path.dropFirst("/api/v1/logs/".count)))
            let queryItems = components.queryItems ?? []
            let cursorValue = queryItems.first(where: { $0.name == "cursor" })?.value
            let cursor = cursorValue.map(EventCursor.init(rawValue:))
            let limitValue = queryItems.first(where: { $0.name == "limit" })?.value
            let limit = limitValue.flatMap(Int.init) ?? 50
            guard let logs = try store.logs(sessionID: sessionID, cursor: cursor, limit: limit) else {
                return try error(statusCode: 404, code: "session_not_found", message: "Session \(sessionID.rawValue) was not found.")
            }
            return try ok(logs)
        }

        if path.hasPrefix("/api/v1/issues") || path.hasPrefix("/api/v1/runs") || path.hasPrefix("/api/v1/logs") {
            return try error(statusCode: 405, code: "method_not_allowed", message: "This endpoint does not support \(method).")
        }

        return try error(statusCode: 404, code: "not_found", message: "The requested endpoint does not exist.")
    }

    private func ok<T: Encodable>(_ value: T) throws -> SymphonyHTTPResponse {
        try response(statusCode: 200, value: value)
    }

    private func error(statusCode: Int, code: String, message: String) throws -> SymphonyHTTPResponse {
        try response(statusCode: statusCode, value: ErrorEnvelope(error: ErrorPayload(code: code, message: message)))
    }

    private func response<T: Encodable>(statusCode: Int, value: T) throws -> SymphonyHTTPResponse {
        SymphonyHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: try encoder.encode(value)
        )
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private enum SQLiteBinding {
    case int(Int?)
    case text(String?)
}

extension SQLiteServerStateStore {
    var diagnostics: Diagnostics {
        Diagnostics(store: self)
    }

    struct Diagnostics {
        fileprivate let store: SQLiteServerStateStore

        private enum ProbeError: Error {
            case rowFailure
            case unexpected
        }

        enum StepRowsProbeResult: Equatable {
            case success
            case rowFailure
            case unexpectedFailure
        }

        func closeDatabase() {
            store.closeDatabase(store.database)
        }

        func executeSelectStatementError() -> SymphonyRuntimeError? {
            captureRuntimeError(performing: try store.execute("SELECT 1;"))
        }

        func prepareInvalidStatementError() -> SymphonyRuntimeError? {
            captureRuntimeError(performing: try store.prepare("SELECT FROM"))
        }

        func bindNilValues() throws {
            let statement = try store.prepare("SELECT ?, ?;")
            defer { sqlite3_finalize(statement) }
            try store.bind([.int(nil), .text(nil)], to: statement)
            _ = try store.stepRows(statement) { rawStatement in
                (
                    columnOptionalInt(rawStatement, index: 0),
                    columnString(rawStatement, index: 1)
                )
            }
        }

        func queryInterruptedStatementError() -> SymphonyRuntimeError? {
            captureRuntimeError(performing: try performRecursiveQuery(interrupted: true))
        }

        func queryCompletedStatementError() -> SymphonyRuntimeError? {
            captureRuntimeError(performing: try performRecursiveQuery(interrupted: false))
        }

        func bindValueOnFinalizedStatementError() -> SymphonyRuntimeError? {
            captureRuntimeError(performing: try bindValueOnFinalizedStatementProbe())
        }

        func encodeThrowingValueError() -> SymphonyRuntimeError? {
            captureRuntimeError(performing: try store.encode(ThrowingEncodable()))
        }

        func stepRowsProbe(mode: StepRowsProbeResult) -> StepRowsProbeResult {
            do {
                let statement = try store.prepare("SELECT 1;")
                defer { sqlite3_finalize(statement) }
                _ = try store.stepRows(statement) { _ in
                    switch mode {
                    case .success:
                        return 1
                    case .rowFailure:
                        throw ProbeError.rowFailure
                    case .unexpectedFailure:
                        throw ProbeError.unexpected
                    }
                }
                return .success
            } catch ProbeError.rowFailure {
                return .rowFailure
            } catch {
                return .unexpectedFailure
            }
        }

        func captureRuntimeErrorWhenBodySucceeds() -> SymphonyRuntimeError? { captureRuntimeError {} }

        func captureRuntimeErrorForRuntimeFailure() -> SymphonyRuntimeError? { captureRuntimeError { throw SymphonyRuntimeError.sqlite("Known diagnostic error.") } }

        func captureRuntimeErrorForUnexpectedProbe() -> SymphonyRuntimeError? { captureRuntimeError { throw ProbeError.rowFailure } }

        func captureRuntimeErrorForUnexpectedAutoclosureProbe() -> SymphonyRuntimeError? { captureRuntimeError(performing: try unexpectedAutoclosureProbe()) }

        private func performRecursiveQuery(interrupted: Bool) throws {
            let database = store.database!
            let statement = try store.prepare(
                """
                WITH RECURSIVE counter(value) AS (
                    SELECT 1
                    UNION ALL
                    SELECT value + 1 FROM counter WHERE value < 100000
                )
                SELECT value FROM counter;
                """
            )
            defer {
                sqlite3_progress_handler(database, 0, nil, nil)
                sqlite3_finalize(statement)
            }
            if interrupted {
                sqlite3_progress_handler(database, 1_000, { _ in 1 }, nil)
            }
            _ = try store.stepRows(statement) { rawStatement in
                columnInt(rawStatement, index: 0)
            }
        }

        private func bindValueOnFinalizedStatementProbe() throws { let statement = try store.prepare("SELECT ?;"); defer { sqlite3_finalize(statement) }; try store.bind([.text("value"), .text("overflow")], to: statement) }

        private func unexpectedAutoclosureProbe() throws -> Int { throw ProbeError.rowFailure }

        func decodeIssueSnapshot(rawSnapshot: String?) throws -> Issue {
            let statement = try store.prepare("SELECT ?;")
            defer { sqlite3_finalize(statement) }

            let bindResult: Int32
            if let rawSnapshot {
                bindResult = sqlite3_bind_text(statement, 1, rawSnapshot, -1, sqliteTransient)
            } else {
                bindResult = sqlite3_bind_null(statement, 1)
            }
            precondition(bindResult == SQLITE_OK)
            _ = try store.stepRows(statement) { _ in
                ()
            }

            let secondStatement = try store.prepare("SELECT ?;")
            defer { sqlite3_finalize(secondStatement) }
            let secondBindResult: Int32
            if let rawSnapshot {
                secondBindResult = sqlite3_bind_text(secondStatement, 1, rawSnapshot, -1, sqliteTransient)
            } else {
                secondBindResult = sqlite3_bind_null(secondStatement, 1)
            }
            precondition(secondBindResult == SQLITE_OK)
            precondition(sqlite3_step(secondStatement) == SQLITE_ROW)
            return try store.decode(Issue.self, fromColumn: 0, statement: secondStatement)
        }

        func sqliteError(message: String) -> SymphonyRuntimeError {
            store.sqliteError(message: message)
        }

        private func captureRuntimeError(_ body: () throws -> Void) -> SymphonyRuntimeError? {
            do {
                try body()
                return nil
            } catch let error as SymphonyRuntimeError {
                return error
            } catch {
                return .sqlite("Unexpected diagnostic error: \(error.localizedDescription)")
            }
        }

        private func captureRuntimeError<T>(performing body: @autoclosure () throws -> T) -> SymphonyRuntimeError? {
            do {
                _ = try body()
                return nil
            } catch let error as SymphonyRuntimeError {
                return error
            } catch {
                return .sqlite("Unexpected diagnostic error: \(error.localizedDescription)")
            }
        }
    }
}

private struct ThrowingEncodable: Encodable {
    func encode(to encoder: Encoder) throws {
        struct ProbeError: Error {}
        throw ProbeError()
    }
}

private func columnString(_ statement: OpaquePointer, index: Int32) -> String {
    columnOptionalString(statement, index: index) ?? ""
}

private func columnOptionalString(_ statement: OpaquePointer, index: Int32) -> String? {
    guard let pointer = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: pointer)
}

private func columnInt(_ statement: OpaquePointer, index: Int32) -> Int {
    Int(sqlite3_column_int64(statement, index))
}

private func columnOptionalInt(_ statement: OpaquePointer, index: Int32) -> Int? {
    sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : columnInt(statement, index: index)
}

private extension NSLock {
    func sync<T>(_ body: () throws -> T) throws -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
