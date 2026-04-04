import Foundation

/// A type-safe representation of arbitrary JSON values.
///
/// Replaces `[String: Any]` and `Any` in JSON parsing code while remaining
/// `Codable`, `Sendable`, and `Equatable`. Use this for JSON structures
/// whose schema is not known at compile time (e.g. provider protocol messages).
public enum JSONValue: Codable, Sendable, Equatable, Hashable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  // MARK: - Convenience accessors

  public var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  public var intValue: Int? {
    if case .int(let value) = self { return value }
    return nil
  }

  public var doubleValue: Double? {
    switch self {
    case .double(let value): return value
    case .int(let value): return Double(value)
    default: return nil
    }
  }

  public var boolValue: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  public var arrayValue: [JSONValue]? {
    if case .array(let value) = self { return value }
    return nil
  }

  public var objectValue: [String: JSONValue]? {
    if case .object(let value) = self { return value }
    return nil
  }

  public var isNull: Bool {
    if case .null = self { return true }
    return false
  }

  /// Subscript for object access.
  public subscript(key: String) -> JSONValue? {
    objectValue?[key]
  }

  /// Subscript for array access.
  public subscript(index: Int) -> JSONValue? {
    guard let array = arrayValue, index >= 0, index < array.count else { return nil }
    return array[index]
  }

  // MARK: - Codable

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let int = try? container.decode(Int.self) {
      self = .int(int)
    } else if let double = try? container.decode(Double.self) {
      self = .double(double)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
    } else if let object = try? container.decode([String: JSONValue].self) {
      self = .object(object)
    } else {
      throw DecodingError.typeMismatch(
        JSONValue.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Unable to decode JSONValue"
        )
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }
}
