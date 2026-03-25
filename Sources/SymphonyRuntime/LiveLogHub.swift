import Foundation
import SymphonyShared

actor LiveLogHub {
  private var subscribers = [SessionID: [UUID: AsyncStream<AgentRawEvent>.Continuation]]()

  func publish(_ event: AgentRawEvent) {
    guard let sessionSubscribers = subscribers[event.sessionID] else {
      return
    }

    for continuation in sessionSubscribers.values {
      continuation.yield(event)
    }
  }

  func subscribe(to sessionID: SessionID) -> AsyncStream<AgentRawEvent> {
    let subscriptionID = UUID()
    var continuation: AsyncStream<AgentRawEvent>.Continuation?

    let stream = AsyncStream<AgentRawEvent> { newContinuation in
      continuation = newContinuation
    }
    let registeredContinuation = continuation!

    subscribers[sessionID, default: [:]][subscriptionID] = registeredContinuation
    registeredContinuation.onTermination = { @Sendable _ in
      Task {
        await self.unsubscribe(subscriptionID, from: sessionID)
      }
    }
    return stream
  }

  private func unsubscribe(_ subscriptionID: UUID, from sessionID: SessionID) {
    subscribers[sessionID]?[subscriptionID] = nil
    if subscribers[sessionID]?.isEmpty == true {
      subscribers[sessionID] = nil
    }
  }

  func subscriberCount(for sessionID: SessionID) -> Int {
    subscribers[sessionID]?.count ?? 0
  }
}
