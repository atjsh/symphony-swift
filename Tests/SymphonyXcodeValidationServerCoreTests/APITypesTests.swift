import Foundation
import Testing
@testable import SymphonyXcodeValidationServerCore

@Suite("ValidationRunConfiguration")
struct ValidationRunConfigurationTests {
  @Test("default initializer uses expected defaults")
  func defaultValues() {
    let config = ValidationRunConfiguration()
    #expect(config.subject == .symphonySwiftUIApp)
    #expect(config.outputRoot == nil)
    #expect(config.artifactRetention == .canonicalOnly)
    #expect(config.buildProfile == .fast)
    #expect(config.executionProfile == .aggressive)
    #expect(config.concurrency == nil)
    #expect(config.logLevel == .info)
    #expect(config.skipRichCapture == false)
    #expect(config.skipFullMatrix == false)
  }

  @Test("Codable roundtrip preserves all fields")
  func codableRoundtrip() throws {
    let config = ValidationRunConfiguration(
      subject: .xcodeValidationGalleryApp,
      outputRoot: "/tmp/output",
      artifactRetention: .debugFriendly,
      buildProfile: .standard,
      executionProfile: .serial,
      logLevel: .debug,
      skipRichCapture: true,
      skipFullMatrix: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(config)
    let decoded = try JSONDecoder().decode(ValidationRunConfiguration.self, from: data)
    #expect(decoded == config)
  }
}

@Suite("API Types")
struct APITypesTests {
  @Test("RunID Codable roundtrip")
  func runIDCodable() throws {
    let id = RunID("abc-123")
    let data = try JSONEncoder().encode(id)
    let decoded = try JSONDecoder().decode(RunID.self, from: data)
    #expect(decoded == id)
    #expect(String(decoding: data, as: UTF8.self) == "\"abc-123\"")
  }

  @Test("StartRunRequest Codable roundtrip")
  func startRunRequestCodable() throws {
    let request = StartRunRequest(
      configuration: ValidationRunConfiguration(),
      projectRoot: "/Users/test/project"
    )
    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(StartRunRequest.self, from: data)
    #expect(decoded.projectRoot == "/Users/test/project")
    #expect(decoded.configuration == request.configuration)
  }

  @Test("RunStatusResponse Codable roundtrip")
  func runStatusResponseCodable() throws {
    let response = RunStatusResponse(
      runID: RunID("run-1"),
      status: .running,
      logLines: [
        LogLine(index: 0, text: "Building..."),
        LogLine(index: 1, text: "Testing..."),
      ],
      currentPhase: .mitigation,
      startedAt: Date(timeIntervalSince1970: 1_000_000)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let data = try encoder.encode(response)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try decoder.decode(RunStatusResponse.self, from: data)
    #expect(decoded.runID == RunID("run-1"))
    #expect(decoded.status == .running)
    #expect(decoded.logLines.count == 2)
    #expect(decoded.logLines[0].text == "Building...")
    #expect(decoded.currentPhase == .mitigation)
    #expect(decoded.error == nil)
  }

  @Test("RunSummaryResponse carries ValidationSummary")
  func runSummaryResponseFields() {
    let response = RunSummaryResponse(
      runID: RunID("run-2"),
      summary: .init(
        outputRoot: "/tmp",
        status: .passed,
        runRecords: [],
        mediaArtifacts: [],
        auditIssues: [],
        unresolvedBlockers: []
      )
    )
    #expect(response.summary.status == .passed)
    #expect(response.runID.rawValue == "run-2")
  }

  @Test("ValidationServerHealthResponse defaults to ok")
  func healthResponseDefault() throws {
    let health = ValidationServerHealthResponse()
    let data = try JSONEncoder().encode(health)
    let decoded = try JSONDecoder().decode(ValidationServerHealthResponse.self, from: data)
    #expect(decoded.status == "ok")
  }

  @Test("LogLine equality")
  func logLineEquality() {
    let a = LogLine(index: 0, text: "hello")
    let b = LogLine(index: 0, text: "hello")
    let c = LogLine(index: 1, text: "hello")
    #expect(a == b)
    #expect(a != c)
  }
}
