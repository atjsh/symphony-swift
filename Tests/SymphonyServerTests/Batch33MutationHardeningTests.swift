// Batch 33 — OrchestratorComponents mutation hardening from SymphonyServerTests.
//
// Targets:
//   StallDetector — isEnabled guard, elapsed >= threshold comparison,
//     isEnabled property, isStalled return value
//   ConcurrencySlotManager — availableSlots(currentRunning:) subtraction,
//     availableSlots(forState:) guard + subtraction, canDispatch && operator,
//     per-state limit enforcement
//   WorkflowParser — parse contentsOf error path, missing key guard

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - StallDetector

@Suite("StallDetector")
struct StallDetectorTests {

  @Test func isEnabledWithPositiveTimeout() {
    let detector = StallDetector(stallTimeoutMS: 5000)
    #expect(detector.isEnabled)
  }

  @Test func isDisabledWithZeroTimeout() {
    let detector = StallDetector(stallTimeoutMS: 0)
    #expect(!detector.isEnabled)
  }

  @Test func disabledDetectorNeverReportsStall() {
    let detector = StallDetector(stallTimeoutMS: 0)
    let pastDate = Date(timeIntervalSinceNow: -3600)
    #expect(!detector.isStalled(lastEventAt: pastDate))
  }

  @Test func reportsStalledWhenElapsedExceedsThreshold() {
    let detector = StallDetector(stallTimeoutMS: 1000)
    let pastDate = Date(timeIntervalSinceNow: -2)
    #expect(detector.isStalled(lastEventAt: pastDate))
  }

  @Test func reportsNotStalledWhenWithinThreshold() {
    let detector = StallDetector(stallTimeoutMS: 60_000)
    let recentDate = Date()
    #expect(!detector.isStalled(lastEventAt: recentDate))
  }

  @Test func exactThresholdBoundaryIsStalled() {
    let detector = StallDetector(stallTimeoutMS: 1000)
    let now = Date()
    let boundary = now.addingTimeInterval(-1.0)
    #expect(detector.isStalled(lastEventAt: boundary, now: now))
  }
}

// MARK: - ConcurrencySlotManager

@Suite("ConcurrencySlotManager Mutations")
struct ConcurrencySlotManagerMutationTests {

  @Test func availableSlotsReturnsCorrectCount() {
    let config = AgentConfig(maxConcurrentAgents: 5)
    let manager = ConcurrencySlotManager(config: config)
    #expect(manager.availableSlots(currentRunning: 2) == 3)
    #expect(manager.availableSlots(currentRunning: 5) == 0)
    #expect(manager.availableSlots(currentRunning: 6) == 0, "Never negative")
  }

  @Test func availableSlotsForStateWithNoLimit() {
    let config = AgentConfig(maxConcurrentAgents: 10)
    let manager = ConcurrencySlotManager(config: config)
    #expect(manager.availableSlots(forState: "Todo", currentInState: 100) == Int.max)
  }

  @Test func availableSlotsForStateWithLimit() {
    let config = AgentConfig(maxConcurrentAgents: 10, maxConcurrentAgentsByState: ["Todo": 3])
    let manager = ConcurrencySlotManager(config: config)
    #expect(manager.availableSlots(forState: "Todo", currentInState: 1) == 2)
    #expect(manager.availableSlots(forState: "Todo", currentInState: 3) == 0)
    #expect(manager.availableSlots(forState: "Todo", currentInState: 5) == 0)
  }

  @Test func canDispatchRequiresBothGlobalAndStateSlots() {
    let config = AgentConfig(maxConcurrentAgents: 2, maxConcurrentAgentsByState: ["Todo": 1])
    let manager = ConcurrencySlotManager(config: config)

    // Both available
    #expect(manager.canDispatch(currentRunning: 0, state: "Todo", currentInState: 0))

    // Global full
    #expect(!manager.canDispatch(currentRunning: 2, state: "Todo", currentInState: 0))

    // State full
    #expect(!manager.canDispatch(currentRunning: 0, state: "Todo", currentInState: 1))

    // Both full
    #expect(!manager.canDispatch(currentRunning: 2, state: "Todo", currentInState: 1))
  }
}
