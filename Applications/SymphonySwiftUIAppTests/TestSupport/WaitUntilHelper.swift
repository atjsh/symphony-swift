import Foundation
import Testing

@MainActor
func waitUntil(
  _ description: String = "condition",
  timeout: Duration = .seconds(5),
  pollInterval: Duration = .milliseconds(10),
  condition: @escaping @MainActor () -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while !condition() {
    if clock.now >= deadline {
      Issue.record("Timed out waiting for \(description).")
      throw POSIXError(.ETIMEDOUT)
    }
    try await Task.sleep(for: pollInterval)
  }
}

@MainActor
func waitUntil(
  _ description: String = "async condition",
  timeout: Duration = .seconds(5),
  pollInterval: Duration = .milliseconds(10),
  condition: @escaping @MainActor () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while !(await condition()) {
    if clock.now >= deadline {
      Issue.record("Timed out waiting for \(description).")
      throw POSIXError(.ETIMEDOUT)
    }
    try await Task.sleep(for: pollInterval)
  }
}
}
