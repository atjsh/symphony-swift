import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer

// MARK: - codexStartupThreadID mutation hardening

@Test func codexStartupThreadIDReturnsNilForNilMessage() {
  #expect(codexStartupThreadID(from: nil) == nil)
}

@Test func codexStartupThreadIDExtractsFromThreadStartedMethod() {
  let msg = ProviderJSONMessage.parse(
    #"{"method":"thread/started","params":{"thread":{"id":"t-123"}}}"#
  )
  #expect(codexStartupThreadID(from: msg) == "t-123")
}

@Test func codexStartupThreadIDIgnoresEmptyThreadIDInThreadStarted() {
  let msg = ProviderJSONMessage.parse(
    #"{"method":"thread/started","params":{"thread":{"id":"   "}}}"#
  )
  #expect(codexStartupThreadID(from: msg) == nil)
}

@Test func codexStartupThreadIDFallsBackToResultPath() {
  let msg = ProviderJSONMessage.parse(
    #"{"result":{"thread":{"id":"result-thread"}}}"#
  )
  #expect(codexStartupThreadID(from: msg) == "result-thread")
}

@Test func codexStartupThreadIDFallsBackToParamsThreadID() {
  let msg = ProviderJSONMessage.parse(
    #"{"params":{"thread_id":"flat-thread"}}"#
  )
  #expect(codexStartupThreadID(from: msg) == "flat-thread")
}

@Test func codexStartupThreadIDFallsBackToParamsThreadIdCamelCase() {
  let msg = ProviderJSONMessage.parse(
    #"{"params":{"threadId":"camel-thread"}}"#
  )
  #expect(codexStartupThreadID(from: msg) == "camel-thread")
}

@Test func codexStartupThreadIDReturnsNilWhenAllPathsEmpty() {
  let msg = ProviderJSONMessage.parse(
    #"{"method":"thread/started","params":{"thread":{"id":""}}}"#
  )
  // thread/started path fails (empty), result path fails (no result), flat path fails (no thread_id)
  #expect(codexStartupThreadID(from: msg) == nil)
}

@Test func codexStartupThreadIDPrefersThreadStartedOverResultPath() {
  // When method is "thread/started" and both params.thread.id and result.thread.id exist,
  // it should return from the thread/started path first
  let msg = ProviderJSONMessage.parse(
    #"{"method":"thread/started","params":{"thread":{"id":"params-t"}},"result":{"thread":{"id":"result-t"}}}"#
  )
  #expect(codexStartupThreadID(from: msg) == "params-t")
}

// MARK: - codexTurnID mutation hardening

@Test func codexTurnIDReturnsNilForNilMessage() {
  #expect(codexTurnID(from: nil) == nil)
}

@Test func codexTurnIDExtractsFromParamsTurnObject() {
  let msg = ProviderJSONMessage.parse(
    #"{"params":{"turn":{"id":"turn-abc"}}}"#
  )
  #expect(codexTurnID(from: msg) == "turn-abc")
}

@Test func codexTurnIDIgnoresEmptyTurnID() {
  let msg = ProviderJSONMessage.parse(
    #"{"params":{"turn":{"id":"  "}}}"#
  )
  #expect(codexTurnID(from: msg) == nil)
}

@Test func codexTurnIDFallsBackToFlatTurnID() {
  let msg = ProviderJSONMessage.parse(
    #"{"params":{"turn_id":"flat-turn"}}"#
  )
  #expect(codexTurnID(from: msg) == "flat-turn")
}

@Test func codexTurnIDFallsBackToCamelCaseTurnId() {
  let msg = ProviderJSONMessage.parse(
    #"{"params":{"turnId":"camel-turn"}}"#
  )
  #expect(codexTurnID(from: msg) == "camel-turn")
}

@Test func codexTurnIDFallsBackToResultPath() {
  let msg = ProviderJSONMessage.parse(
    #"{"result":{"turn":{"id":"result-turn"}}}"#
  )
  #expect(codexTurnID(from: msg) == "result-turn")
}

@Test func codexTurnIDReturnsNilWhenAllPathsEmpty() {
  let msg = ProviderJSONMessage.parse(
    #"{"params":{"turn":{"id":""},"turn_id":""}}"#
  )
  #expect(codexTurnID(from: msg) == nil)
}

// MARK: - shouldSuppressSuccessfulCodexResponse mutation hardening

@Test func suppressReturnsFalseForNilMessage() {
  #expect(shouldSuppressSuccessfulCodexResponse(nil) == false)
}

@Test func suppressReturnsFalseWhenErrorPresent() {
  let msg = ProviderJSONMessage.parse(
    #"{"id":1,"result":{"ok":true},"error":"something broke"}"#
  )
  #expect(shouldSuppressSuccessfulCodexResponse(msg) == false)
}

@Test func suppressReturnsFalseWhenIdMissing() {
  let msg = ProviderJSONMessage.parse(
    #"{"result":{"ok":true}}"#
  )
  #expect(shouldSuppressSuccessfulCodexResponse(msg) == false)
}

@Test func suppressReturnsFalseWhenResultMissing() {
  let msg = ProviderJSONMessage.parse(
    #"{"id":1}"#
  )
  #expect(shouldSuppressSuccessfulCodexResponse(msg) == false)
}

@Test func suppressReturnsFalseWhenMethodPresent() {
  let msg = ProviderJSONMessage.parse(
    #"{"id":1,"result":{"ok":true},"method":"turn/completed"}"#
  )
  #expect(shouldSuppressSuccessfulCodexResponse(msg) == false)
}

@Test func suppressReturnsFalseWhenTypePresent() {
  let msg = ProviderJSONMessage.parse(
    #"{"id":1,"result":{"ok":true},"type":"status"}"#
  )
  #expect(shouldSuppressSuccessfulCodexResponse(msg) == false)
}

@Test func suppressReturnsTrueOnlyWhenIdAndResultPresentAndNoMethodNoType() {
  let msg = ProviderJSONMessage.parse(
    #"{"id":1,"result":{"ok":true}}"#
  )
  #expect(shouldSuppressSuccessfulCodexResponse(msg) == true)
}

// MARK: - codexTurnOutcome mutation hardening

@Test func codexTurnOutcomeReturnsNilForInvalidJSON() {
  #expect(codexTurnOutcome(from: "not json") == nil)
}

@Test func codexTurnOutcomeReturnsNilForMissingMethod() {
  #expect(codexTurnOutcome(from: #"{"params":{}}"#) == nil)
}

@Test func codexTurnOutcomeReturnsNilForUnknownMethod() {
  #expect(codexTurnOutcome(from: #"{"method":"turn/started"}"#) == nil)
}

@Test func codexTurnOutcomeReturnsFailed() {
  let json = #"{"method":"turn/completed","result":{"status":"failed"}}"#
  #expect(codexTurnOutcome(from: json) == .failed)
}

@Test func codexTurnOutcomeReturnsFailedForErrorOutcome() {
  let json = #"{"method":"turn/completed","result":{"outcome":"error"}}"#
  #expect(codexTurnOutcome(from: json) == .failed)
}

@Test func codexTurnOutcomeReturnsInterruptedForCancelled() {
  let json = #"{"method":"turn/completed","params":{"state":"cancelled"}}"#
  #expect(codexTurnOutcome(from: json) == .interrupted)
}

@Test func codexTurnOutcomeReturnsInterruptedForCanceledSpelling() {
  let json = #"{"method":"turn/completed","params":{"state":"canceled"}}"#
  #expect(codexTurnOutcome(from: json) == .interrupted)
}

@Test func codexTurnOutcomeReturnsInterruptedForInterrupted() {
  let json = #"{"method":"turn/completed","result":{"outcome":"interrupted"}}"#
  #expect(codexTurnOutcome(from: json) == .interrupted)
}

@Test func codexTurnOutcomeReturnsCompletedForSuccessOutcome() {
  let json = #"{"method":"turn/completed","result":{"status":"success"}}"#
  #expect(codexTurnOutcome(from: json) == .completed)
}

@Test func codexTurnOutcomeReturnsCompletedWhenNoOutcomeStringFound() {
  let json = #"{"method":"turn/completed","params":{"unrelated":"data"}}"#
  #expect(codexTurnOutcome(from: json) == .completed)
}

@Test func codexTurnOutcomeHandlesTurnFailed() {
  #expect(codexTurnOutcome(from: #"{"method":"turn/failed"}"#) == .failed)
}

@Test func codexTurnOutcomeHandlesTurnCancelled() {
  #expect(codexTurnOutcome(from: #"{"method":"turn/cancelled"}"#) == .interrupted)
}

@Test func codexTurnOutcomeHandlesTurnInterrupted() {
  #expect(codexTurnOutcome(from: #"{"method":"turn/interrupted"}"#) == .interrupted)
}

@Test func codexTurnOutcomeSearchesNestedPayloadForOutcome() {
  let json = #"{"method":"turn/completed","params":{"payload":{"terminal":{"outcome":"failed"}}}}"#
  #expect(codexTurnOutcome(from: json) == .failed)
}

@Test func codexTurnOutcomeSkipsEmptyOutcomeStrings() {
  // Array with empty strings and a valid one — should find the valid one
  let json = #"{"method":"turn/completed","result":{"outcome":["","  ","failed"]}}"#
  #expect(codexTurnOutcome(from: json) == .failed)
}

// MARK: - makeCodexTurnStartMessage mutation hardening

@Test func makeCodexTurnStartMessageIncludesRequiredFields() throws {
  let msg = makeCodexTurnStartMessage(
    id: 42,
    threadID: "t1",
    issueIdentifier: "org/repo#1",
    issueTitle: "Fix bug",
    workspacePath: "/tmp/workspace",
    input: "prompt text",
    config: .defaults
  )
  #expect(msg["id"] as? Int == 42)
  #expect(msg["method"] as? String == "turn/start")
  let params = try #require(msg["params"] as? [String: Any])
  #expect(params["threadId"] as? String == "t1")
  #expect(params["cwd"] as? String == "/tmp/workspace")
  #expect((params["title"] as? String)?.contains("org/repo#1") == true)
  #expect((params["title"] as? String)?.contains("Fix bug") == true)
  let input = try firstInputObject(from: params)
  #expect(input["type"] as? String == "text")
  #expect(input["text"] as? String == "prompt text")
}

// MARK: - makeCodexInterruptMessage mutation hardening

@Test func makeCodexInterruptMessageIncludesAllFields() throws {
  let msg = makeCodexInterruptMessage(id: 7, threadID: "t2", turnID: "turn3")
  #expect(msg["id"] as? Int == 7)
  #expect(msg["method"] as? String == "turn/interrupt")
  let params = try #require(msg["params"] as? [String: Any])
  #expect(params["threadId"] as? String == "t2")
  #expect(params["turnId"] as? String == "turn3")
}
