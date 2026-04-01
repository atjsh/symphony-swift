import Foundation

public enum ValidationLogLevel: String, Codable, CaseIterable, Sendable {
  case quiet
  case info
  case debug
}

public enum ValidationLogHooks {
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

enum ValidationLogSeverity: String {
  case debug
  case info
  case warning
  case error
}

enum ValidationLogger {
  static func log(
    configuredLevel: ValidationLogLevel,
    severity: ValidationLogSeverity,
    timestamp: Date,
    sinkOverride: (@Sendable (String) -> Void)? = nil,
    message: @autoclosure () -> String
  ) {
    guard configuredLevel.includes(severity) else {
      return
    }

    let line =
      "[\(iso8601(timestamp))] [SymphonyXcodeValidation] \(severity.rawValue): \(message())"
    if let sink = sinkOverride ?? ValidationLogHooks.sinkOverride {
      sink(line)
      return
    }

    if let data = "\(line)\n".data(using: .utf8) {
      FileHandle.standardError.write(data)
    }
  }

  private static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}

struct ValidationRunLogger: Sendable {
  let level: ValidationLogLevel
  let now: @Sendable () -> Date
  let sink: (@Sendable (String) -> Void)?

  init(
    level: ValidationLogLevel,
    now: @escaping @Sendable () -> Date,
    sink: (@Sendable (String) -> Void)? = nil
  ) {
    self.level = level
    self.now = now
    self.sink = sink
  }

  func debug(_ message: @autoclosure () -> String) {
    log(.debug, message())
  }

  func info(_ message: @autoclosure () -> String) {
    log(.info, message())
  }

  func warning(_ message: @autoclosure () -> String) {
    log(.warning, message())
  }

  func error(_ message: @autoclosure () -> String) {
    log(.error, message())
  }

  private func log(_ severity: ValidationLogSeverity, _ message: @autoclosure () -> String) {
    ValidationLogger.log(
      configuredLevel: level,
      severity: severity,
      timestamp: now(),
      sinkOverride: sink,
      message: message()
    )
  }
}

private extension ValidationLogLevel {
  func includes(_ severity: ValidationLogSeverity) -> Bool {
    switch self {
    case .quiet:
      false
    case .info:
      severity != .debug
    case .debug:
      true
    }
  }
}
