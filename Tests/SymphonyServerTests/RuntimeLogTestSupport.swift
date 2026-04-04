import Foundation

@testable import SymphonyServer
@testable import SymphonyServerCore

private actor RuntimeLogCaptureCoordinator {
  private var isActive = false
  private var waiters = [CheckedContinuation<Void, Never>]()

  func acquire() async {
    guard isActive else {
      isActive = true
      return
    }

    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func release() {
    guard !waiters.isEmpty else {
      isActive = false
      return
    }

    let continuation = waiters.removeFirst()
    continuation.resume()
  }
}

private enum RuntimeLogTestSupportError: Error {
  case invalidUTF8(String)
  case invalidJSONObject(String)
}

private final class RuntimeLogLineBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var lines = [String]()

  func append(_ line: String) {
    lock.withLock {
      lines.append(line)
    }
  }

  var snapshot: [String] {
    lock.withLock { lines }
  }
}

struct CapturedRuntimeLog {
  let line: String
  let entry: RuntimeLogEntry
}

struct RuntimeLogEntry: Decodable {
  var event: String?
  var level: String?
  var runID: String?
  var issueID: String?
  var issueIdentifier: String?
  var sessionID: String?
  var provider: String?
  var providerSessionID: String?
  var component: String?
  var state: String?
  var error: String?
  var timestamp: String?
  var authorization: String?
  var trackerAPIKey: String?
  var endpoint: String?
  var path: String?
  var hook: String?
  var workspacePath: String?
  var statusCode: String?

  private enum CodingKeys: String, CodingKey {
    case event, level, component, state, error, timestamp, authorization, endpoint, provider, path
    case hook
    case runID = "run_id"
    case issueID = "issue_id"
    case issueIdentifier = "issue_identifier"
    case sessionID = "session_id"
    case providerSessionID = "provider_session_id"
    case trackerAPIKey = "tracker_api_key"
    case workspacePath = "workspace_path"
    case statusCode = "status_code"
  }
}

private let runtimeLogCaptureCoordinator = RuntimeLogCaptureCoordinator()

func withCapturedRuntimeLogs<T>(_ body: () async throws -> T) async throws -> (
  T, [CapturedRuntimeLog]
) {
  await runtimeLogCaptureCoordinator.acquire()

  let collector = RuntimeLogLineBuffer()
  let previousSink = RuntimeLogHooks.sinkOverride
  RuntimeLogHooks.sinkOverride = { line in
    collector.append(line)
  }
  do {
    let result = try await body()
    RuntimeLogHooks.sinkOverride = previousSink
    await runtimeLogCaptureCoordinator.release()
    return (result, try decodeCapturedRuntimeLogs(collector.snapshot))
  } catch {
    RuntimeLogHooks.sinkOverride = previousSink
    await runtimeLogCaptureCoordinator.release()
    throw error
  }
}

private func decodeCapturedRuntimeLogs(_ lines: [String]) throws -> [CapturedRuntimeLog] {
  let decoder = JSONDecoder()
  return try lines.map { line in
    guard let data = line.data(using: .utf8) else {
      throw RuntimeLogTestSupportError.invalidUTF8(line)
    }
    let entry = try decoder.decode(RuntimeLogEntry.self, from: data)
    return CapturedRuntimeLog(line: line, entry: entry)
  }
}
