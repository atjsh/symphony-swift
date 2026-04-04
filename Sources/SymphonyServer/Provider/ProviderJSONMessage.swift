import Foundation
import SymphonyShared

/// A typed representation of a JSON-RPC-like message from a provider process.
///
/// Replaces `[String: Any]` throughout the provider adapter layer. Covers the
/// union of fields used by Codex CLI, Claude Code, and Copilot CLI protocols.
struct ProviderJSONMessage: Codable, Sendable, Equatable {
  /// JSON-RPC request/response ID.
  let id: JSONValue?
  /// JSON-RPC method name (Codex, Copilot CLI).
  let method: String?
  /// JSON-RPC params object.
  let params: [String: JSONValue]?
  /// JSON-RPC result object.
  let result: [String: JSONValue]?
  /// JSON-RPC error payload (presence indicates an error).
  let error: JSONValue?
  /// Event type field (Claude Code, some Codex events).
  let type: String?
  /// Copilot CLI event identifier.
  let event: String?

  // MARK: - Parsing

  private static let decoder = JSONDecoder()

  /// Decode a provider message from a raw JSON string.
  /// Returns `nil` if the JSON is not a valid object.
  static func parse(_ rawJSON: String) -> ProviderJSONMessage? {
    guard let data = rawJSON.data(using: .utf8) else { return nil }
    return try? decoder.decode(ProviderJSONMessage.self, from: data)
  }

  /// Decode a provider message from raw JSON data.
  static func parse(data: Data) -> ProviderJSONMessage? {
    try? decoder.decode(ProviderJSONMessage.self, from: data)
  }

  // MARK: - Deep value access

  /// Access a nested string value using a key path into `params`.
  func paramsString(_ keys: String...) -> String? {
    nestedString(in: params, keys: keys)
  }

  /// Access a nested string value using a key path into `result`.
  func resultString(_ keys: String...) -> String? {
    nestedString(in: result, keys: keys)
  }

  /// Access a nested object from `params`.
  func paramsObject(_ key: String) -> [String: JSONValue]? {
    params?[key]?.objectValue
  }

  /// Access a nested object from `result`.
  func resultObject(_ key: String) -> [String: JSONValue]? {
    result?[key]?.objectValue
  }

  /// Walk a key path into a JSON object to find a string leaf.
  private func nestedString(in root: [String: JSONValue]?, keys: [String]) -> String? {
    guard let root, let first = keys.first else { return nil }
    guard let value = root[first] else { return nil }

    if keys.count == 1 {
      return value.stringValue
    }

    guard let nested = value.objectValue else { return nil }
    return nestedString(in: nested, keys: Array(keys.dropFirst()))
  }

  // MARK: - Serialization (for outbound messages)

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  /// Encode this message to JSON data.
  func toData() throws -> Data {
    try Self.encoder.encode(self)
  }
}
