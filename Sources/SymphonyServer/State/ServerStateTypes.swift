import Foundation
import SQLite3
import SymphonyShared

let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SymphonyServerError: Error, Equatable, Sendable {
  case sqlite(String)
  case encoding(String)
}

enum SQLiteBinding {
  case int(Int?)
  case text(String?)
}

struct ThrowingEncodable: Encodable {
  func encode(to encoder: Encoder) throws {
    struct ProbeError: Error {}
    throw ProbeError()
  }
}

func columnString(_ statement: OpaquePointer, index: Int32) -> String {
  columnOptionalString(statement, index: index) ?? ""
}

func columnOptionalString(_ statement: OpaquePointer, index: Int32) -> String? {
  guard let pointer = sqlite3_column_text(statement, index) else {
    return nil
  }
  return String(cString: pointer)
}

func columnInt(_ statement: OpaquePointer, index: Int32) -> Int {
  Int(sqlite3_column_int64(statement, index))
}

func columnOptionalInt(_ statement: OpaquePointer, index: Int32) -> Int? {
  sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : columnInt(statement, index: index)
}
