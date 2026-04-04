import Foundation

public struct ServerEndpoint: Codable, Hashable, Sendable {
  public let scheme: String
  public let host: String
  public let port: Int

  public init(scheme: String = "http", host: String = "localhost", port: Int = 8080) throws {
    guard Self.isValidScheme(scheme), Self.isValidHost(host), Self.isValidPort(port) else {
      throw SymphonySharedValidationError.invalidServerEndpoint
    }

    self.scheme = scheme
    self.host = host
    self.port = port
  }

  public var url: URL? {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = port
    return components.url
  }

  private static func isValidScheme(_ scheme: String) -> Bool {
    !scheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func isValidHost(_ host: String) -> Bool {
    !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func isValidPort(_ port: Int) -> Bool {
    (1...65535).contains(port)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self = try ServerEndpoint(
      scheme: container.decode(String.self, forKey: .scheme),
      host: container.decode(String.self, forKey: .host),
      port: container.decode(Int.self, forKey: .port)
    )
  }
}

public struct EventCursor: Codable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(sessionID: SessionID, lastDeliveredSequence: EventSequence) {
    let payload = CursorPayload(
      sessionID: sessionID.rawValue, sequence: lastDeliveredSequence.rawValue)
    self.rawValue = Self.encode(payload)
  }

  public var description: String {
    rawValue
  }

  public var sessionID: SessionID? {
    guard let sessionID = Self.decode(rawValue)?.sessionID else {
      return nil
    }

    return SessionID(sessionID)
  }

  public var lastDeliveredSequence: EventSequence? {
    Self.decode(rawValue).map { EventSequence($0.sequence) }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(rawValue: try container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  private struct CursorPayload: Codable, Hashable, Sendable {
    let sessionID: String
    let sequence: Int

    private enum CodingKeys: String, CodingKey {
      case sessionID = "session_id"
      case sequence
    }
  }

  private static func encode(_ payload: CursorPayload) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    // CursorPayload is a trivial Codable struct; encoding cannot fail
    // under normal conditions. If it does, return empty string as defensive fallback.
    guard let data = try? encoder.encode(payload) else {
      return ""
    }
    return data.base64URLEncodedString()
  }

  private static func decode(_ rawValue: String) -> CursorPayload? {
    guard let data = Data(base64URLEncoded: rawValue) else {
      return nil
    }

    return try? JSONDecoder().decode(CursorPayload.self, from: data)
  }
}

public struct ErrorPayload: Codable, Hashable, Sendable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public struct ErrorEnvelope: Codable, Hashable, Sendable {
  public let error: ErrorPayload

  public init(error: ErrorPayload) {
    self.error = error
  }
}
