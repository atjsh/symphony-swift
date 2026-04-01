import Foundation
import SymphonyShared

// MARK: - Session Sequence Counter

final class SessionSequenceCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: Int = 0

  func next() -> EventSequence {
    lock.lock()
    let current = _value
    _value += 1
    lock.unlock()
    return EventSequence(current)
  }
}

// MARK: - Session Store

public final class SessionStore: @unchecked Sendable {
  private let lock = NSLock()
  private var _sessions: [SessionID: ProviderManagedSession] = [:]

  public init() {}

  public func store(
    sessionID: SessionID,
    process: LaunchedProcess,
    workspacePath: String = "",
    environment: [String: String] = [:]
  ) {
    let session = ProviderManagedSession(
      process: process,
      workspacePath: workspacePath,
      environment: environment
    )
    lock.withLock { _sessions[sessionID] = session }
  }

  @discardableResult
  public func remove(sessionID: SessionID) -> LaunchedProcess? {
    lock.withLock { _sessions.removeValue(forKey: sessionID)?.process }
  }

  public func process(for sessionID: SessionID) -> LaunchedProcess? {
    lock.withLock { _sessions[sessionID]?.process }
  }

  public func managedSession(for sessionID: SessionID) -> ProviderManagedSession? {
    lock.withLock { _sessions[sessionID] }
  }

  public var count: Int {
    lock.withLock { _sessions.count }
  }
}
