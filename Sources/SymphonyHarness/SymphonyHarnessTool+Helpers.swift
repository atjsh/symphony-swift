import Foundation
import SymphonyShared

extension SymphonyHarnessTool {
  func defaultTestProductionSubjects(capabilities: ToolchainCapabilities) -> [HarnessSubject] {
    HarnessSubjects.production.filter { subject in
      !subject.requiresXcode || capabilityOutcome(for: subject, command: .test, capabilities: capabilities).status == .supported
    }
  }

  func capabilityOutcome(
    for subject: HarnessSubject,
    command _: HarnessCommand,
    capabilities: ToolchainCapabilities
  ) -> CapabilityOutcome {
    guard subject.requiresXcode else {
      return CapabilityOutcome(status: .supported)
    }
    guard capabilities.supportsSimulatorCommands else {
      return CapabilityOutcome(status: .unsupported, reason: Self.noXcodeMessage)
    }
    return CapabilityOutcome(status: .supported)
  }

  func schedulerLane(for subject: HarnessSubject) -> String {
    if subject.requiresExclusiveDestination {
      return "xcode-exclusive"
    }
    return "\(subject.buildSystem.rawValue)-default"
  }

  func uniqueSubjects(_ subjects: [HarnessSubject]) -> [HarnessSubject] {
    var seen = Set<String>()
    return subjects.filter { subject in
      seen.insert(subject.name).inserted
    }
  }

  func buildCommandFamily(for command: HarnessCommand) -> BuildCommandFamily {
    if command == .build {
      return .build
    }
    if command == .run {
      return .run
    }
    return .test
  }

  func makeSharedRunID(command: HarnessCommand, date: Date) -> String {
    "\(DateFormatting.runTimestamp(for: date))-\(command.rawValue)-\(UUID().uuidString.lowercased())"
  }

  func aggregateOutcome(from subjectResults: [SubjectRunResult], anomalies: [ArtifactAnomaly]) -> String {
    let hardFailureCodes: Set<String> = [
      "coverage_policy_failed",
      "environment_policy_failed",
      "artifact_policy_failed",
      "xcode_test_plans_failed",
      "accessibility_validation_failed",
    ]
    if subjectResults.contains(where: { $0.outcome == .failure }) {
      return "failure"
    }
    if anomalies.contains(where: { hardFailureCodes.contains($0.code) }) {
      return "failure"
    }
    if subjectResults.contains(where: { $0.outcome == .unsupported || $0.outcome == .skipped }) {
      return "partial"
    }
    if anomalies.contains(where: { $0.code.hasPrefix("skipped_") }) {
      return "partial"
    }
    return "success"
  }

  func isDefaultRepositoryValidate(_ request: ExecutionRequest) -> Bool {
    request.command == .validate
      && request.subjects.isEmpty
      && request.explicitTestSubjects.isEmpty
  }

  func buildSelection(for subject: HarnessSubject) throws -> SubjectExecutionSelection {
    switch subject.buildSystem {
    case .swiftpm:
      return SubjectExecutionSelection(
        legacyProduct: .server,
        subjectName: subject.name,
        scheme: subject.name,
        swiftPMProduct: swiftPMProduct(for: subject),
        swiftPMTestFilter: nil,
        onlyTesting: []
      )
    case .xcode:
      return SubjectExecutionSelection(
        legacyProduct: .client,
        subjectName: subject.name,
        scheme: subject.name,
        swiftPMProduct: nil,
        swiftPMTestFilter: nil,
        onlyTesting: []
      )
    }
  }

  func testSelection(
    for subject: HarnessSubject,
    productionSubject: HarnessSubject?
  ) throws -> SubjectExecutionSelection {
    switch subject.buildSystem {
    case .swiftpm:
      let filter: String
      if subject.kind == .test || subject.kind == .uiTest {
        filter = subject.name
      } else {
        var defaultFilter = subject.name
        if let defaultTestCompanion = subject.defaultTestCompanion {
          defaultFilter = defaultTestCompanion
        }
        filter = defaultFilter
      }
      return SubjectExecutionSelection(
        legacyProduct: .server,
        subjectName: subject.name,
        scheme: productionSubject?.name ?? subject.name,
        swiftPMProduct: nil,
        swiftPMTestFilter: filter,
        onlyTesting: []
      )

    case .xcode:
      let scheme = productionSubject?.name ?? "SymphonySwiftUIApp"
      let onlyTesting: [String]
      if subject.kind == .test || subject.kind == .uiTest {
        onlyTesting = [subject.name]
      } else {
        var selectedTests = [String]()
        if let defaultTestCompanion = subject.defaultTestCompanion {
          selectedTests = [defaultTestCompanion]
        }
        onlyTesting = selectedTests
      }
      return SubjectExecutionSelection(
        legacyProduct: .client,
        subjectName: subject.name,
        scheme: scheme,
        swiftPMProduct: nil,
        swiftPMTestFilter: nil,
        onlyTesting: onlyTesting
      )
    }
  }

  func runSelection(for subject: HarnessSubject) throws -> SubjectExecutionSelection {
    guard HarnessSubjects.runnableSubjectNames.contains(subject.name) else {
      throw unsupportedSubjectBridgeError(forSubject: subject.name)
    }

    switch subject.buildSystem {
    case .swiftpm:
      return SubjectExecutionSelection(
        legacyProduct: .server,
        subjectName: subject.name,
        scheme: subject.name,
        swiftPMProduct: swiftPMProduct(for: subject),
        swiftPMTestFilter: nil,
        onlyTesting: []
      )
    case .xcode:
      return SubjectExecutionSelection(
        legacyProduct: .client,
        subjectName: subject.name,
        scheme: subject.name,
        swiftPMProduct: nil,
        swiftPMTestFilter: nil,
        onlyTesting: []
      )
    }
  }

  func resolveHarnessSubject(named name: String) throws -> HarnessSubject {
    guard let subject = HarnessSubjects.subject(named: name) else {
      throw unsupportedSubjectBridgeError(forSubject: name)
    }
    return subject
  }

  func swiftPMProduct(for subject: HarnessSubject) -> String {
    switch subject.name {
    case "SymphonyServerCLI":
      return "symphony-server"
    case "SymphonyHarnessCLI":
      return "harness"
    default:
      return subject.name
    }
  }

  func endpointOverrides(from environment: [String: String]) -> (
    serverURL: String?, scheme: String?, host: String?, port: Int?
  ) {
    let port: Int?
    if let rawPort = environment["SYMPHONY_SERVER_PORT"] {
      port = Int(rawPort)
    } else {
      port = nil
    }
    return (
      serverURL: environment["SYMPHONY_SERVER_URL"],
      scheme: environment["SYMPHONY_SERVER_SCHEME"],
      host: environment["SYMPHONY_SERVER_HOST"],
      port: port
    )
  }

  static func artifactValidationPolicyOutcome(
    for subjectResults: [SubjectRunResult]
  ) -> (summaryLines: [String], anomalies: [ArtifactAnomaly], failureMessage: String?) {
    let fileManager = FileManager.default
    let artifactPolicyFailed = subjectResults.contains { result in
      !fileManager.fileExists(atPath: result.artifactSet.summaryPath.path)
        || !fileManager.fileExists(atPath: result.artifactSet.indexPath.path)
        || !fileManager.fileExists(atPath: result.artifactSet.logPath.path)
    }
    guard artifactPolicyFailed else {
      return (["validation_policy_result artifacts: success"], [], nil)
    }
    return (
      ["validation_policy_result artifacts: failure"],
      [
        ArtifactAnomaly(
          code: "artifact_policy_failed",
          message: "One or more subject runs did not materialize the required canonical artifact files.",
          phase: "validate-policy"
        )
      ],
      "validate failed for repository artifact policies."
    )
  }

  static func defaultAppValidationPolicyOutcome(
    subjectResults: [SubjectRunResult],
    supportsSimulatorCommands: Bool,
    buildStateRoot: URL
  ) -> (summaryLines: [String], anomalies: [ArtifactAnomaly], failureMessage: String?) {
    guard supportsSimulatorCommands else {
      return (
        [
          "validation_policy_result xcodeTestPlans: skipped",
          "validation_policy_result accessibility: skipped",
        ],
        [
          ArtifactAnomaly(
            code: "skipped_xcode_test_plans",
            message: Self.noXcodeMessage,
            phase: "validate-policy"
          ),
          ArtifactAnomaly(
            code: "skipped_accessibility_validation",
            message: Self.noXcodeMessage,
            phase: "validate-policy"
          ),
        ],
        nil
      )
    }

    var appResult: SubjectRunResult?
    for subjectResult in subjectResults where subjectResult.subject == "SymphonySwiftUIApp" {
      appResult = subjectResult
      break
    }
    if appResult == nil {
      appResult = SubjectRunResult(
        subject: "SymphonySwiftUIApp",
        outcome: .failure,
        artifactSet: SubjectArtifactSet(
          subject: "SymphonySwiftUIApp",
          artifactRoot: buildStateRoot,
          summaryPath: buildStateRoot.appendingPathComponent("missing-summary.txt"),
          indexPath: buildStateRoot.appendingPathComponent("missing-index.json"),
          coverageTextPath: nil,
          coverageJSONPath: nil,
          resultBundlePath: nil,
          logPath: buildStateRoot.appendingPathComponent("missing-log.txt"),
          anomalies: []
        )
      )
    }
    let resolvedAppResult = appResult!
    var accessibilityPlanFailed = false
    var xcodePlanFailed = false
    for anomaly in resolvedAppResult.artifactSet.anomalies {
      if anomaly.code == "accessibility_validation_plan_failed"
        || anomaly.code == "missing_accessibility_validation_plan"
      {
        accessibilityPlanFailed = true
      }
      if anomaly.code == "xcode_test_plan_execution_failed" {
        xcodePlanFailed = true
      }
    }
    if resolvedAppResult.outcome == .failure && !accessibilityPlanFailed {
      xcodePlanFailed = true
    }
    if resolvedAppResult.outcome == .success {
      return (
        [
          "validation_policy_result xcodeTestPlans: success",
          "validation_policy_result accessibility: success",
        ],
        [],
        nil
      )
    }

    var summaryLines = [String]()
    var anomalies = [ArtifactAnomaly]()
    var failureMessage: String?
    if xcodePlanFailed {
      summaryLines.append("validation_policy_result xcodeTestPlans: failure")
      anomalies.append(
        ArtifactAnomaly(
          code: "xcode_test_plans_failed",
          message: "The default app validation plan set failed.",
          phase: "validate-policy"
        )
      )
      failureMessage = "validate failed for required app validation plans."
    } else {
      summaryLines.append("validation_policy_result xcodeTestPlans: success")
    }
    if accessibilityPlanFailed {
      summaryLines.append("validation_policy_result accessibility: failure")
      anomalies.append(
        ArtifactAnomaly(
          code: "accessibility_validation_failed",
          message: "The required accessibility validation suite failed.",
          phase: "validate-policy"
        )
      )
      if failureMessage == nil {
        failureMessage = "validate failed for required accessibility validation."
      }
    } else {
      summaryLines.append("validation_policy_result accessibility: success")
    }
    return (summaryLines, anomalies, failureMessage)
  }

  func unsupportedSubjectBridgeError(for request: ExecutionRequest) -> SymphonyHarnessError {
    let requestedSubjects = request.subjects + request.explicitTestSubjects
    return unsupportedSubjectBridgeError(forSubject: requestedSubjects.joined(separator: ", "))
  }

  func unsupportedSubjectBridgeError(forSubject subject: String) -> SymphonyHarnessError {
    SymphonyHarnessError(
      code: "subject_bridge_unavailable",
      message:
        "ExecutionRequest does not support the requested subject selection for \(subject). Use the canonical subject and command combinations or the dedicated doctor API."
    )
  }

  static let noXcodeMessage =
    "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
}
