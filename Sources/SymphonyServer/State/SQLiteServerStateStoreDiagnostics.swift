import Foundation
import SQLite3
import SymphonyShared

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

    func executeSelectStatementError() -> SymphonyServerError? {
      captureRuntimeError(performing: try store.execute("SELECT 1;"))
    }

    func prepareInvalidStatementError() -> SymphonyServerError? {
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

    func queryInterruptedStatementError() -> SymphonyServerError? {
      captureRuntimeError(performing: try performRecursiveQuery(interrupted: true))
    }

    func queryCompletedStatementError() -> SymphonyServerError? {
      captureRuntimeError(performing: try performRecursiveQuery(interrupted: false))
    }

    func bindValueOnFinalizedStatementError() -> SymphonyServerError? {
      captureRuntimeError(performing: try bindValueOnFinalizedStatementProbe())
    }

    func encodeThrowingValueError() -> SymphonyServerError? {
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

    func captureRuntimeErrorWhenBodySucceeds() -> SymphonyServerError? { captureRuntimeError {} }

    func captureRuntimeErrorForRuntimeFailure() -> SymphonyServerError? {
      captureRuntimeError { throw SymphonyServerError.sqlite("Known diagnostic error.") }
    }

    func captureRuntimeErrorForUnexpectedProbe() -> SymphonyServerError? {
      captureRuntimeError { throw ProbeError.rowFailure }
    }

    func captureRuntimeErrorForUnexpectedAutoclosureProbe() -> SymphonyServerError? {
      captureRuntimeError(performing: try unexpectedAutoclosureProbe())
    }

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

    private func bindValueOnFinalizedStatementProbe() throws {
      let statement = try store.prepare("SELECT ?;")
      defer { sqlite3_finalize(statement) }
      return try store.bind([.text("value"), .text("overflow")], to: statement)
    }

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

    func sqliteError(message: String) -> SymphonyServerError {
      store.sqliteError(message: message)
    }

    private func captureRuntimeError(_ body: () throws -> Void) -> SymphonyServerError? {
      do {
        try body()
        return nil
      } catch let error as SymphonyServerError {
        return error
      } catch {
        return .sqlite("Unexpected diagnostic error: \(error.localizedDescription)")
      }
    }

    private func captureRuntimeError<T>(performing body: @autoclosure () throws -> T)
      -> SymphonyServerError?
    {
      do {
        _ = try body()
        return nil
      } catch let error as SymphonyServerError {
        return error
      } catch {
        return .sqlite("Unexpected diagnostic error: \(error.localizedDescription)")
      }
    }
  }
}
