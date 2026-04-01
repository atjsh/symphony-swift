import Foundation
import Testing

@MainActor
func waitUntil(
  timeout: Duration = .seconds(5),
  pollInterval: Duration = .milliseconds(10),
  condition: @escaping @MainActor () -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while !condition() {
    if clock.now >= deadline {
      Issue.record("Timed out waiting for condition.")
      return
    }
    try await Task.sleep(for: pollInterval)
  }
}
