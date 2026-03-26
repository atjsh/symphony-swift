import Foundation

@testable import SymphonyRuntime

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
  let json: [String: Any]
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
  try lines.map { line in
    guard let data = line.data(using: .utf8) else {
      throw RuntimeLogTestSupportError.invalidUTF8(line)
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw RuntimeLogTestSupportError.invalidJSONObject(line)
    }
    return CapturedRuntimeLog(line: line, json: object)
  }
}
