import Foundation
import SymphonyShared

// MARK: - Stream Finish State

// SAFETY: @unchecked Sendable — `_finished` accessed through `lock.withLock`.
final class StreamFinishState: @unchecked Sendable {
  private let lock = NSLock()
  private var _finished = false

  var isFinished: Bool {
    lock.withLock { _finished }
  }

  func finishIfNeeded(_ action: () -> Void) {
    let shouldFinish = lock.withLock {
      guard !_finished else { return false }
      _finished = true
      return true
    }

    if shouldFinish {
      action()
    }
  }
}

// MARK: - Shared Protocol Helpers

func submitInput(_ input: String, to process: LaunchedProcess) throws {
  guard !input.isEmpty else { return }
  do {
    try process.sendInput(Data(input.utf8))
  } catch {
    throw ProviderAdapterError.processLaunchFailed(error.localizedDescription)
  }
}

func submitJSONMessages(_ messages: [[String: Any]], to process: LaunchedProcess) throws {
  do {
    for message in messages {
      let data = try JSONSerialization.data(withJSONObject: message)
      try process.sendInput(data + Data("\n".utf8))
    }
  } catch {
    throw ProviderAdapterError.processLaunchFailed(error.localizedDescription)
  }
}

func protocolLines(from output: String) -> [String] {
  output
    .split(whereSeparator: \.isNewline)
    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
}

func protocolJSONMessage(from line: String) -> ProviderJSONMessage? {
  ProviderJSONMessage.parse(line)
}

func copilotProviderSessionID(from msg: ProviderJSONMessage?) -> String? {
  msg?.resultString("sessionId")
}

func copilotPromptStopReason(from msg: ProviderJSONMessage?) -> String? {
  msg?.resultString("stopReason")
}
