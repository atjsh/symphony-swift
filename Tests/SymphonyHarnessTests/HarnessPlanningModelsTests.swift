import Foundation
import Testing

@testable import SymphonyHarness

@Test func executionRequestAndPlanPreserveCanonicalHarnessInputs() throws {
  let request = ExecutionRequest(
    command: .validate,
    subjects: ["SymphonyShared", "SymphonyServerCLI"],
    explicitTestSubjects: ["SymphonyServerCLITests"],
    environment: ["CI": "1"],
    outputMode: .quiet
  )

  #expect(request.command == .validate)
  #expect(request.subjects == ["SymphonyShared", "SymphonyServerCLI"])
  #expect(request.explicitTestSubjects == ["SymphonyServerCLITests"])
  #expect(request.environment == ["CI": "1"])
  #expect(request.outputMode == .quiet)

  let serverCLI = try #require(HarnessSubjects.subject(named: "SymphonyServerCLI"))
  let app = try #require(HarnessSubjects.subject(named: "SymphonySwiftUIApp"))
  let supported = CapabilityOutcome(status: .supported)
  let skipped = CapabilityOutcome(
    status: .skipped,
    reason: "Xcode is unavailable on this host."
  )

  let plan = ExecutionPlan(
    subjectRuns: [
      ScheduledSubjectRun(
        subject: serverCLI,
        command: .validate,
        schedulerLane: "swiftpm-default",
        requiresExclusiveDestination: false,
        capabilityOutcome: supported
      ),
      ScheduledSubjectRun(
        subject: app,
        command: .validate,
        schedulerLane: "xcode-exclusive",
        requiresExclusiveDestination: true,
        capabilityOutcome: skipped
      ),
    ],
    sharedRunRoot: URL(fileURLWithPath: "/tmp/repo/.build/harness/runs/run-1", isDirectory: true),
    defaultedSubjects: ["SymphonyShared"],
    validationPolicies: [.coverage, .artifacts, .environment]
  )

  #expect(plan.subjectRuns.map(\.subject.name) == ["SymphonyServerCLI", "SymphonySwiftUIApp"])
  #expect(plan.sharedRunRoot.lastPathComponent == "run-1")
  #expect(plan.defaultedSubjects == ["SymphonyShared"])
  #expect(plan.validationPolicies == [.coverage, .artifacts, .environment])
  #expect(plan.subjectRuns[1].capabilityOutcome.status == .skipped)
  #expect(plan.subjectRuns[1].capabilityOutcome.reason == "Xcode is unavailable on this host.")
}

@Test func subjectArtifactSetAndSharedRunSummaryPreservePerSubjectResults() {
  let artifactSet = SubjectArtifactSet(
    subject: "SymphonyServerCLI",
    artifactRoot: URL(fileURLWithPath: "/tmp/repo/.build/harness/runs/run-1/subjects/SymphonyServerCLI"),
    summaryPath: URL(fileURLWithPath: "/tmp/repo/.build/harness/runs/run-1/subjects/SymphonyServerCLI/summary.txt"),
    indexPath: URL(fileURLWithPath: "/tmp/repo/.build/harness/runs/run-1/subjects/SymphonyServerCLI/index.json"),
    coverageTextPath: nil,
    coverageJSONPath: nil,
    resultBundlePath: nil,
    logPath: URL(fileURLWithPath: "/tmp/repo/.build/harness/runs/run-1/subjects/SymphonyServerCLI/process-stdout-stderr.txt"),
    anomalies: [
      ArtifactAnomaly(
        code: "missing_result_bundle",
        message: "No xcresult bundle was produced.",
        phase: "artifacts"
      )
    ]
  )

  let subjectResult = SubjectRunResult(
    subject: "SymphonyServerCLI",
    outcome: .failure,
    artifactSet: artifactSet
  )

  let summary = SharedRunSummary(
    command: .validate,
    runID: "run-1",
    startedAt: Date(timeIntervalSince1970: 1_700_000_000),
    endedAt: Date(timeIntervalSince1970: 1_700_000_060),
    subjects: ["SymphonyServerCLI"],
    subjectResults: [subjectResult],
    anomalies: artifactSet.anomalies
  )

  #expect(summary.command == HarnessCommand.validate)
  #expect(summary.subjects == ["SymphonyServerCLI"])
  #expect(summary.subjectResults.map { $0.subject } == ["SymphonyServerCLI"])
  #expect(summary.subjectResults.first?.outcome == SubjectRunOutcome.failure)
  #expect(summary.subjectResults.first?.artifactSet.artifactRoot.lastPathComponent == "SymphonyServerCLI")
  #expect(summary.anomalies.first?.code == "missing_result_bundle")
}
