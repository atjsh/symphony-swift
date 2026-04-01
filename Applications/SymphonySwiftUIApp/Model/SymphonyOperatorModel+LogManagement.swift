import Foundation
import SymphonyShared

// MARK: - Log Management

extension SymphonyOperatorModel {
  func clearLogs() {
    liveLogTask?.cancel()
    liveLogTask = nil
    logCursor = nil
    logEvents = []
    liveStatus = "Idle"
  }

  func startLiveStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?)
  {
    liveLogTask?.cancel()
    liveStatus = "Connecting live stream"
    let client = self.client

    liveLogTask = Task { @MainActor [weak self, client] in
      do {
        let stream = try client.logStream(endpoint: endpoint, sessionID: sessionID, cursor: cursor)
        self?.setLiveStatus("Live")

        for try await event in stream {
          self?.appendLogEvent(event)
        }

        self?.setLiveStatus("Ended")
      } catch is CancellationError {
      } catch {
        self?.setLiveStatus(error.localizedDescription)
      }
    }
  }

  func testingAppendLogEvent(_ event: AgentRawEvent) {
    appendLogEvent(event)
  }

  func testingMergeLogEvents(_ events: [AgentRawEvent]) {
    mergeLogEvents(events)
  }

  var testingLogCursor: EventCursor? {
    logCursor
  }

  private func setLiveStatus(_ status: String) {
    liveStatus = status
  }

  private func appendLogEvent(_ event: AgentRawEvent) {
    mergeLogEvents([event])
    logCursor = EventCursor(sessionID: event.sessionID, lastDeliveredSequence: event.sequence)
  }

  func mergeLogEvents(_ events: [AgentRawEvent]) {
    for event in events where !logEvents.contains(where: { $0.sequence == event.sequence }) {
      logEvents.append(event)
    }
    logEvents.sort { $0.sequence < $1.sequence }
  }

  static func isRelevantLogEvent(_ event: AgentRawEvent) -> Bool {
    switch event.normalizedKind {
    case .message:
      if event.providerEventType.hasSuffix("/delta") {
        return false
      }
      return !SymphonyEventPresentation.isEmptyAgentMessageShell(event: event)
    case .toolCall, .toolResult, .approvalRequest, .error:
      return true
    case .status:
      return event.providerEventType != "skills/changed"
    case .usage, .unknown:
      return false
    }
  }
}
