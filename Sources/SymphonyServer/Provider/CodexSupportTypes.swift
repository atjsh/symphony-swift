import Foundation
import SymphonyShared
import SymphonyServerCore

// MARK: - Codex Session State

final class CodexSessionState: @unchecked Sendable {
  private let lock = NSLock()
  private let sequenceCounter = SessionSequenceCounter()
  private var _issueIdentifier: String?
  private var _issueTitle: String?
  private var _threadID: String?
  private var _turnID: String?
  private var nextRequestID = 4

  func recordIssueContext(identifier: String, title: String) {
    lock.withLock {
      _issueIdentifier = identifier
      _issueTitle = title
    }
  }

  var issueIdentifier: String? {
    lock.withLock { _issueIdentifier }
  }

  var issueTitle: String? {
    lock.withLock { _issueTitle }
  }

  var threadID: String? {
    lock.withLock { _threadID }
  }

  var turnID: String? {
    lock.withLock { _turnID }
  }

  func recordThreadID(_ threadID: String) {
    lock.withLock {
      _threadID = threadID
    }
  }

  func recordTurnID(_ turnID: String) {
    lock.withLock {
      _turnID = turnID
    }
  }

  func nextSequence() -> EventSequence {
    sequenceCounter.next()
  }

  func nextTurnRequestID() -> Int {
    lock.withLock {
      defer { nextRequestID += 1 }
      return nextRequestID
    }
  }
}

// MARK: - Codex Session Registry

final class CodexSessionRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var states: [SessionID: CodexSessionState] = [:]

  func state(for sessionID: SessionID) -> CodexSessionState {
    lock.withLock {
      if let existing = states[sessionID] {
        return existing
      }

      let state = CodexSessionState()
      states[sessionID] = state
      return state
    }
  }

  func threadID(for sessionID: SessionID) -> String? {
    lock.withLock { states[sessionID]?.threadID }
  }

  func turnID(for sessionID: SessionID) -> String? {
    lock.withLock { states[sessionID]?.turnID }
  }

  func remove(sessionID: SessionID) {
    _ = lock.withLock {
      states.removeValue(forKey: sessionID)
    }
  }
}

// MARK: - Codex Terminal Outcome

enum CodexTerminalOutcome: String, Sendable {
  case completed
  case failed
  case interrupted
}

// MARK: - Codex Timeout Monitor

final class CodexTimeoutMonitor: @unchecked Sendable {
  private let lock = NSLock()
  private var readTimeoutTask: Task<Void, Never>?
  private var turnTimeoutTask: Task<Void, Never>?
  private var _terminalError: Error?

  func startReadTimeout(
    sessionID: SessionID,
    readTimeoutMS: Int,
    process: LaunchedProcess,
    finish: @escaping @Sendable (Error) -> Void
  ) {
    guard readTimeoutMS > 0 else { return }
    lock.withLock {
      readTimeoutTask?.cancel()
      readTimeoutTask = Task {
        do {
          try await Task.sleep(nanoseconds: UInt64(readTimeoutMS) * 1_000_000)
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        let timeoutError = ProviderAdapterError.readTimeout(
          sessionID: sessionID,
          readTimeoutMS: readTimeoutMS
        )
        finish(timeoutError)
        process.terminate()
      }
    }
  }

  func cancelReadTimeout() {
    lock.withLock {
      readTimeoutTask?.cancel()
      readTimeoutTask = nil
    }
  }

  func startTurnTimeout(
    sessionID: SessionID,
    turnTimeoutMS: Int,
    process: LaunchedProcess
  ) {
    guard turnTimeoutMS > 0 else { return }
    lock.withLock {
      turnTimeoutTask?.cancel()
      turnTimeoutTask = Task {
        do {
          try await Task.sleep(nanoseconds: UInt64(turnTimeoutMS) * 1_000_000)
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        lock.withLock {
          _terminalError = ProviderAdapterError.turnTimeout(
            sessionID: sessionID,
            turnTimeoutMS: turnTimeoutMS
          )
        }
        process.terminate()
      }
    }
  }

  func consumeTerminalError() -> Error? {
    lock.withLock {
      defer { _terminalError = nil }
      return _terminalError
    }
  }

  func cancelAll() {
    lock.withLock {
      readTimeoutTask?.cancel()
      readTimeoutTask = nil
      turnTimeoutTask?.cancel()
      turnTimeoutTask = nil
      _terminalError = nil
    }
  }
}

// MARK: - Codex Startup State

final class CodexStartupState: @unchecked Sendable {
  private let lock = NSLock()
  private let issueIdentifier: String
  private let issueTitle: String
  private let workspacePath: String
  private let prompt: String
  private let config: CodexProviderConfig
  private var didSendTurnStart = false

  init(issue: Issue?, workspacePath: String, prompt: String, config: CodexProviderConfig) {
    self.issueIdentifier = issue?.identifier.rawValue ?? "unknown"
    self.issueTitle = issue?.title ?? "Untitled"
    self.workspacePath = workspacePath
    self.prompt = prompt
    self.config = config
  }

  func turnStartMessageIfNeeded(threadID: String) -> [String: Any]? {
    lock.withLock {
      guard !didSendTurnStart else { return nil }
      didSendTurnStart = true
      return makeCodexTurnStartMessage(
        id: 3,
        threadID: threadID,
        issueIdentifier: issueIdentifier,
        issueTitle: issueTitle,
        workspacePath: workspacePath,
        input: prompt,
        config: config
      )
    }
  }
}

// MARK: - Codex Output Buffer

final class CodexOutputBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var remainder = ""

  func append(_ chunk: String) -> [String] {
    lock.withLock {
      remainder += chunk
      return drainCompleteLines()
    }
  }

  func finish() -> [String] {
    lock.withLock {
      defer { remainder = "" }
      let trimmed = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return [] }
      return [trimmed]
    }
  }

  private func drainCompleteLines() -> [String] {
    var lines = [String]()
    while let newlineIndex = remainder.firstIndex(where: \.isNewline) {
      let line = String(remainder[..<newlineIndex]).trimmingCharacters(
        in: .whitespacesAndNewlines)
      remainder = newlineIndex < remainder.index(before: remainder.endIndex)
        ? String(remainder[remainder.index(after: newlineIndex)...])
        : ""
      if !line.isEmpty {
        lines.append(line)
      }
    }
    return lines
  }
}
