import Foundation
import SymphonyShared

extension SymphonyHarnessTool {
  func writeSharedRunArtifacts(
    plan: ExecutionPlan,
    request: ExecutionRequest,
    summary: SharedRunSummary,
    startedAt: Date,
    endedAt: Date,
    extraSummaryLines: [String]
  ) throws {
    let createdAt = DateFormatting.iso8601(endedAt)
    let summaryPath = plan.sharedRunRoot.appendingPathComponent("summary.txt")
    let summaryJSONPath = plan.sharedRunRoot.appendingPathComponent("summary.json")
    let indexPath = plan.sharedRunRoot.appendingPathComponent("index.json")
    let subjectEntries = summary.subjectResults.map { result in
      ArtifactIndexEntry(
        name: result.subject,
        relativePath: "subjects/\(result.subject)",
        kind: "directory",
        createdAt: createdAt
      )
    }
    let index = SharedRunIndex(
      command: request.command,
      runID: summary.runID,
      startedAt: DateFormatting.iso8601(startedAt),
      endedAt: DateFormatting.iso8601(endedAt),
      entries: [
        ArtifactIndexEntry(
          name: "summary.txt",
          relativePath: "summary.txt",
          kind: "file",
          createdAt: createdAt
        ),
        ArtifactIndexEntry(
          name: "summary.json",
          relativePath: "summary.json",
          kind: "file",
          createdAt: createdAt
        ),
        ArtifactIndexEntry(
          name: "index.json",
          relativePath: "index.json",
          kind: "file",
          createdAt: createdAt
        ),
        ArtifactIndexEntry(
          name: "subjects",
          relativePath: "subjects",
          kind: "directory",
          createdAt: createdAt
        ),
      ] + subjectEntries,
      anomalies: summary.anomalies
    )

    let validationPolicyText =
      plan.validationPolicies.isEmpty
      ? "validation_policies: none"
      : "validation_policies: \(plan.validationPolicies.map(\.rawValue).joined(separator: ", "))"
    let aggregateAnomalyCodes = summary.anomalies.map { anomaly -> String in
      if let subject = anomaly.subject {
        return "\(subject):\(anomaly.code)"
      }
      return anomaly.code
    }
    let aggregateAnomaliesText =
      aggregateAnomalyCodes.isEmpty
      ? "aggregate_anomalies: none"
      : "aggregate_anomalies: \(aggregateAnomalyCodes.joined(separator: ", "))"

    let summaryLines =
      [
        "command: \(request.command.rawValue)",
        "requested_subjects: \((request.subjects + request.explicitTestSubjects).joined(separator: ", "))",
        "defaulted_subjects: \(plan.defaultedSubjects.joined(separator: ", "))",
        "started_at: \(DateFormatting.iso8601(startedAt))",
        "ended_at: \(DateFormatting.iso8601(endedAt))",
        "aggregate_outcome: \(aggregateOutcome(from: summary.subjectResults, anomalies: summary.anomalies))",
        "shared_run_root: \(plan.sharedRunRoot.path)",
        validationPolicyText,
      ]
      + summary.subjectResults.map {
        "subject_artifact_root \($0.subject): \($0.artifactSet.artifactRoot.path)"
      }
      + extraSummaryLines
      + [aggregateAnomaliesText]

    try summaryLines.joined(separator: "\n").write(
      to: summaryPath,
      atomically: true,
      encoding: .utf8
    )
    try (encodePrettyJSON(summary) + "\n").write(
      to: summaryJSONPath,
      atomically: true,
      encoding: .utf8
    )
    try (encodePrettyJSON(index) + "\n").write(
      to: indexPath,
      atomically: true,
      encoding: .utf8
    )
    try artifactManager.updateLatestLink(
      familyRoot: plan.sharedRunRoot.deletingLastPathComponent(),
      target: plan.sharedRunRoot
    )
  }

  func loadSubjectArtifactSet(subject: String, subjectRoot: URL) throws -> SubjectArtifactSet {
    let coverageTextPath = subjectRoot.appendingPathComponent("coverage.txt")
    let coverageJSONPath = subjectRoot.appendingPathComponent("coverage.json")
    let resultBundlePath = subjectRoot.appendingPathComponent("result.xcresult", isDirectory: true)
    let logPath = subjectRoot.appendingPathComponent("process-stdout-stderr.txt")
    let indexPath = subjectRoot.appendingPathComponent("index.json")
    let anomalies: [ArtifactAnomaly]
    if let artifactIndex = try? artifactManager.loadArtifactIndexIfPresent(at: indexPath) {
      anomalies = artifactIndex.anomalies
    } else {
      var decodedAnomalies = [ArtifactAnomaly]()
      if let data = try? Data(contentsOf: indexPath) {
        if let decodedIndex = try? JSONDecoder().decode(SharedRunIndex.self, from: data) {
          decodedAnomalies = decodedIndex.anomalies
        }
      }
      anomalies = decodedAnomalies
    }

    return SubjectArtifactSet(
      subject: subject,
      artifactRoot: subjectRoot,
      summaryPath: subjectRoot.appendingPathComponent("summary.txt"),
      indexPath: indexPath,
      coverageTextPath: FileManager.default.fileExists(atPath: coverageTextPath.path)
        ? coverageTextPath : nil,
      coverageJSONPath: FileManager.default.fileExists(atPath: coverageJSONPath.path)
        ? coverageJSONPath : nil,
      resultBundlePath: FileManager.default.fileExists(atPath: resultBundlePath.path)
        ? resultBundlePath : nil,
      logPath: logPath,
      anomalies: anomalies
    )
  }

  func writeSkippedSubjectArtifacts(
    subject: HarnessSubject,
    command: HarnessCommand,
    subjectRoot: URL,
    outcome: SubjectRunOutcome,
    reason: String
  ) throws -> SubjectArtifactSet {
    try writeSyntheticSubjectArtifacts(
      subject: subject,
      command: command,
      subjectRoot: subjectRoot,
      outcome: outcome,
      reason: reason,
      anomalyCode: outcome == .unsupported ? "unsupported_subject_execution" : "skipped_subject_execution"
    )
  }

  func writeFailedSubjectArtifacts(
    subject: HarnessSubject,
    command: HarnessCommand,
    subjectRoot: URL,
    reason: String
  ) throws -> SubjectArtifactSet {
    try writeSyntheticSubjectArtifacts(
      subject: subject,
      command: command,
      subjectRoot: subjectRoot,
      outcome: .failure,
      reason: reason,
      anomalyCode: "subject_execution_failed"
    )
  }

  func writeSyntheticSubjectArtifacts(
    subject: HarnessSubject,
    command: HarnessCommand,
    subjectRoot: URL,
    outcome: SubjectRunOutcome,
    reason: String,
    anomalyCode: String
  ) throws -> SubjectArtifactSet {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: subjectRoot, withIntermediateDirectories: true)

    let anomaly = ArtifactAnomaly(
      code: anomalyCode,
      message: reason,
      phase: command.rawValue,
      subject: subject.name
    )
    let createdAt = DateFormatting.iso8601(Date())
    let processLogPath = subjectRoot.appendingPathComponent("process-stdout-stderr.txt")
    let summaryPath = subjectRoot.appendingPathComponent("summary.txt")
    let summaryJSONPath = subjectRoot.appendingPathComponent("summary.json")
    let indexPath = subjectRoot.appendingPathComponent("index.json")

    try reason.write(to: processLogPath, atomically: true, encoding: .utf8)
    try [
      "command: \(command.rawValue)",
      "subject: \(subject.name)",
      "outcome: \(outcome.rawValue)",
      "artifact_root: \(subjectRoot.path)",
      "reason: \(reason)",
    ].joined(separator: "\n").write(
      to: summaryPath,
      atomically: true,
      encoding: .utf8
    )
    try (encodePrettyJSON(
      SyntheticSubjectSummary(
        command: command,
        subject: subject.name,
        outcome: outcome,
        artifactRoot: subjectRoot.path,
        reason: reason
      )
    ) + "\n").write(
      to: summaryJSONPath,
      atomically: true,
      encoding: .utf8
    )
    try (encodePrettyJSON(
      SharedRunIndex(
        command: command,
        runID: subject.name,
        startedAt: createdAt,
        endedAt: createdAt,
        entries: [
          ArtifactIndexEntry(
            name: "summary.txt",
            relativePath: "summary.txt",
            kind: "file",
            createdAt: createdAt
          ),
          ArtifactIndexEntry(
            name: "summary.json",
            relativePath: "summary.json",
            kind: "file",
            createdAt: createdAt
          ),
          ArtifactIndexEntry(
            name: "index.json",
            relativePath: "index.json",
            kind: "file",
            createdAt: createdAt
          ),
          ArtifactIndexEntry(
            name: "process-stdout-stderr.txt",
            relativePath: "process-stdout-stderr.txt",
            kind: "file",
            createdAt: createdAt
          ),
        ],
        anomalies: [anomaly]
      )
    ) + "\n").write(
      to: indexPath,
      atomically: true,
      encoding: .utf8
    )

    return SubjectArtifactSet(
      subject: subject.name,
      artifactRoot: subjectRoot,
      summaryPath: summaryPath,
      indexPath: indexPath,
      coverageTextPath: nil,
      coverageJSONPath: nil,
      resultBundlePath: nil,
      logPath: processLogPath,
      anomalies: [anomaly]
    )
  }

}
