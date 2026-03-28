import Foundation

public enum RuntimeLogLevel: String, Sendable {
  case info
  case warning
  case error
}

public struct RuntimeLogContext: Sendable, Equatable {
  public var issueID: String?
  public var issueIdentifier: String?
  public var runID: String?
  public var sessionID: String?
  public var provider: String?
  public var providerSessionID: String?
  public var metadata: [String: String]

  public init(
    issueID: String? = nil,
    issueIdentifier: String? = nil,
    runID: String? = nil,
    sessionID: String? = nil,
    provider: String? = nil,
    providerSessionID: String? = nil,
    metadata: [String: String] = [:]
  ) {
    self.issueID = issueID
    self.issueIdentifier = issueIdentifier
    self.runID = runID
    self.sessionID = sessionID
    self.provider = provider
    self.providerSessionID = providerSessionID
    self.metadata = metadata
  }
}

public enum RuntimeLogHooks {
  private final class Storage: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: (@Sendable (String) -> Void)?

    var sinkOverride: (@Sendable (String) -> Void)? {
      get {
        lock.lock()
        defer { lock.unlock() }
        return sink
      }
      set {
        lock.lock()
        sink = newValue
        lock.unlock()
      }
    }
  }

  private static let storage = Storage()

  public static var sinkOverride: (@Sendable (String) -> Void)? {
    get { storage.sinkOverride }
    set { storage.sinkOverride = newValue }
  }
}

public enum RuntimeLogger {
  public static func log(
    level: RuntimeLogLevel,
    event: String,
    context: RuntimeLogContext = RuntimeLogContext(),
    error: String? = nil,
    sensitiveValues: [String] = []
  ) {
    var payload: [String: String] = [
      "timestamp": iso8601Timestamp(),
      "level": level.rawValue,
      "event": event,
    ]

    merge(value: context.issueID, for: "issue_id", into: &payload, sensitiveValues: sensitiveValues)
    merge(
      value: context.issueIdentifier,
      for: "issue_identifier",
      into: &payload,
      sensitiveValues: sensitiveValues
    )
    merge(value: context.runID, for: "run_id", into: &payload, sensitiveValues: sensitiveValues)
    merge(
      value: context.sessionID,
      for: "session_id",
      into: &payload,
      sensitiveValues: sensitiveValues
    )
    merge(
      value: context.provider,
      for: "provider",
      into: &payload,
      sensitiveValues: sensitiveValues
    )
    merge(
      value: context.providerSessionID,
      for: "provider_session_id",
      into: &payload,
      sensitiveValues: sensitiveValues
    )

    for (key, value) in context.metadata.sorted(by: { $0.key < $1.key }) {
      guard payload[key] == nil else { continue }
      payload[key] = redact(value, sensitiveValues: sensitiveValues)
    }

    if let error, !error.isEmpty {
      payload["error"] = redact(error, sensitiveValues: sensitiveValues)
    }

    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let line = String(decoding: data, as: UTF8.self)

    if let sink = RuntimeLogHooks.sinkOverride {
      sink(line)
      return
    }

    if let data = "\(line)\n".data(using: .utf8) {
      FileHandle.standardError.write(data)
    }
  }

  private static func merge(
    value: String?,
    for key: String,
    into payload: inout [String: String],
    sensitiveValues: [String]
  ) {
    guard let value, !value.isEmpty else { return }
    payload[key] = redact(value, sensitiveValues: sensitiveValues)
  }

  private static func iso8601Timestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
  }

  private static func redact(_ value: String, sensitiveValues: [String]) -> String {
    var redacted = value

    for secret
      in sensitiveValues
      .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
      .filter({ !$0.isEmpty })
      .sorted(by: { $0.count > $1.count })
    {
      redacted = redacted.replacingOccurrences(of: secret, with: "[REDACTED]")
    }

    redacted = keyValueSecretRule.stringByReplacingMatches(
      in: redacted,
      range: NSRange(redacted.startIndex..<redacted.endIndex, in: redacted),
      withTemplate: "$1$2[REDACTED]"
    )
    redacted = bearerTokenRule.stringByReplacingMatches(
      in: redacted,
      range: NSRange(redacted.startIndex..<redacted.endIndex, in: redacted),
      withTemplate: "Bearer [REDACTED]"
    )

    redacted = tokenLikeValueRule.stringByReplacingMatches(
      in: redacted,
      range: NSRange(redacted.startIndex..<redacted.endIndex, in: redacted),
      withTemplate: "[REDACTED]"
    )

    return redacted
  }

  private static let bearerTokenRule = try! NSRegularExpression(
    pattern: #"(?i)\bbearer\s+[A-Za-z0-9._-]+"#
  )
  private static let keyValueSecretRule = try! NSRegularExpression(
    pattern:
      #"(?i)\b(api[_-]?key|token|authorization|password|secret)\b\s*([:=])\s*("[^"]*"|[^,;\n]+)"#
  )
  private static let tokenLikeValueRule = try! NSRegularExpression(
    pattern: #"\b(gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]+)\b"#
  )
}
