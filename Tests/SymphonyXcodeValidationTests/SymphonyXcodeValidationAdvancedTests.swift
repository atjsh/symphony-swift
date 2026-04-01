import Foundation
import Testing

@testable import SymphonyXcodeValidation

@Suite("SymphonyXcodeValidation Advanced")
struct SymphonyXcodeValidationAdvancedTests {
  @Test func systemValidationProcessExecutorDrainsLargeCommandOutput() throws {
    let executor = SystemValidationProcessExecutor()
    let command = ValidationCommand(
      executable: "sh",
      arguments: [
        "-c",
        """
        awk 'BEGIN {
          for (i = 0; i < 20000; i++) {
            print "stdout-line";
            print "stderr-line" > "/dev/stderr";
          }
        }'
        """,
      ],
      environment: [:],
      currentDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
    )
    let startedAt = Date()

    let result = try executor.run(command)

    #expect(result.exitStatus == 0)
    #expect(result.stdout.contains("stdout-line"))
    #expect(result.stderr.contains("stderr-line"))
    #expect(Date().timeIntervalSince(startedAt) < 10)
  }

  @Test func attachmentManifestProducesStructuredMediaArtifacts() throws {
    let exportRoot = URL(fileURLWithPath: "/tmp/export", isDirectory: true)
    let attachmentManifest = """
      [
        {
          "attachments": [
            {
              "configurationName": "Default",
              "deviceId": "E09AB2DE-2B82-49E2-8119-6C2FD1227C04",
              "deviceName": "iPhone 17 Pro Max",
              "exportedFileName": "root.png",
              "isAssociatedWithFailure": false,
              "suggestedHumanReadableName": "surface=root__orientation=portrait__variant=base__artifact=screenshot_0_ABC.png",
              "timestamp": 1774771926.179
            }
          ],
          "testIdentifier": "SymphonySwiftUIAppUITests/testRichMediaWalkthroughCapturesExtensibleSurfaceMatrix()",
          "testIdentifierURL": "test://example"
        }
      ]
      """
    let run = ValidationRunRecord(
      phase: .richCapture,
      destination: .iPhoneSimulator,
      plan: .uiTests,
      runName: "rich-media",
      outcome: .passed,
      resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
      summary: ValidationTestSummary(
        result: "Passed",
        passedTests: 1,
        failedTests: 0,
        testFailures: []
      ),
      startedAt: Date(timeIntervalSince1970: 10),
      endedAt: Date(timeIntervalSince1970: 20)
    )

    let artifacts = try ValidationAttachmentCatalog.mediaArtifacts(
      manifestData: Data(attachmentManifest.utf8),
      exportRoot: exportRoot,
      run: run
    )

    #expect(artifacts.count == 1)
    #expect(artifacts[0].platform == "ios")
    #expect(artifacts[0].plan == "ui-tests")
    #expect(
      artifacts[0].test
        == "SymphonySwiftUIAppUITests/testRichMediaWalkthroughCapturesExtensibleSurfaceMatrix()")
    #expect(artifacts[0].checkpoint == "root")
    #expect(artifacts[0].surface == "root")
    #expect(artifacts[0].orientation == "portrait")
    #expect(artifacts[0].variant == "base")
    #expect(artifacts[0].artifactType == .screenshot)
    #expect(artifacts[0].sourceResultBundle == "/tmp/result.xcresult")
    #expect(artifacts[0].file == "/tmp/export/root.png")
  }

  @Test func xcresultTestsFallbackParserBuildsFailureSummaryFromTestTree() throws {
    let payload = """
      {
        "devices": [],
        "testPlanConfigurations": [],
        "testNodes": [
          {
            "nodeType": "Test Plan",
            "name": "SymphonySwiftUIAppTests",
            "result": "Failed",
            "children": [
              {
                "nodeType": "Unit test bundle",
                "name": "SymphonySwiftUIAppTests",
                "result": "Failed",
                "children": [
                  {
                    "nodeType": "Test Suite",
                    "name": "SymphonyOperatorModelTests",
                    "children": [
                      {
                        "nodeType": "Test Case",
                        "name": "ProgressReportViewModelShowsCachedSnapshotBeforeRefreshing()",
                        "nodeIdentifier": "SymphonySwiftUIAppTests/SymphonyOperatorModelTests/ProgressReportViewModelShowsCachedSnapshotBeforeRefreshing()",
                        "result": "Failed",
                        "children": [
                          {
                            "nodeType": "Failure Message",
                            "name": "Timed out waiting for cached snapshot publication.",
                            "details": "Timed out waiting for cached snapshot publication."
                          }
                        ]
                      },
                      {
                        "nodeType": "Test Case",
                        "name": "ProgressReportRefreshIgnoresOverlappingRequests()",
                        "nodeIdentifier": "SymphonySwiftUIAppTests/SymphonyOperatorModelTests/ProgressReportRefreshIgnoresOverlappingRequests()",
                        "result": "Passed"
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }
      """

    let summary = try XCResultTestsPayloadParser.makeSummary(from: Data(payload.utf8))

    #expect(summary.result == "Failed")
    #expect(summary.passedTests == 1)
    #expect(summary.failedTests == 1)
    #expect(
      summary.testFailures == [
        ValidationTestFailure(
          testIdentifier: "SymphonySwiftUIAppTests/SymphonyOperatorModelTests/ProgressReportViewModelShowsCachedSnapshotBeforeRefreshing()",
          failureText: "Timed out waiting for cached snapshot publication."
        )
      ]
    )
  }

  @Test func summaryAggregationMarksMitigationFailuresAsBlockers() {
    let mitigationFailure = ValidationRunRecord(
      phase: .mitigation,
      destination: .macOS,
      plan: .appTests,
      runName: "progress-report-model",
      outcome: .failed,
      resultBundlePath: URL(fileURLWithPath: "/tmp/progress.xcresult"),
      summary: ValidationTestSummary(
        result: "Failed",
        passedTests: 0,
        failedTests: 1,
        testFailures: [
          ValidationTestFailure(
            testIdentifier: "SymphonyOperatorModelTests/ProgressReportViewModelShowsCachedSnapshotBeforeRefreshing()",
            failureText: "Timed out waiting for condition."
          )
        ]
      ),
      startedAt: Date(timeIntervalSince1970: 10),
      endedAt: Date(timeIntervalSince1970: 20)
    )
    let matrixFailure = ValidationRunRecord(
      phase: .fullMatrix,
      destination: .iPadSimulator,
      plan: .uiTests,
      runName: "full-ui-tests",
      outcome: .failed,
      resultBundlePath: URL(fileURLWithPath: "/tmp/ui-tests.xcresult"),
      summary: ValidationTestSummary(
        result: "Failed",
        passedTests: 12,
        failedTests: 1,
        testFailures: [
          ValidationTestFailure(
            testIdentifier: "SymphonySwiftUIAppUITests/testAccessibilityAuditCoversRequiredCheckpoints()",
            failureText: "Contrast failed"
          )
        ]
      ),
      startedAt: Date(timeIntervalSince1970: 30),
      endedAt: Date(timeIntervalSince1970: 40)
    )

    let summary = ValidationSummaryBuilder.makeSummary(
      outputRoot: URL(fileURLWithPath: "/tmp/report", isDirectory: true),
      runRecords: [mitigationFailure, matrixFailure],
      mediaArtifacts: [],
      auditIssues: []
    )

    #expect(summary.status == .blocked)
    #expect(summary.unresolvedBlockers.count == 1)
    #expect(
      summary.unresolvedBlockers[0]
        == "SymphonyOperatorModelTests/ProgressReportViewModelShowsCachedSnapshotBeforeRefreshing()")
  }

  @Test func retryPolicyRetriesTransientSimulatorRunnerDisconnects() {
    let summary = ValidationTestSummary(
      result: "Failed",
      passedTests: 0,
      failedTests: 1,
      testFailures: [
        ValidationTestFailure(
          testIdentifier: "Symphony encountered an error",
          failureText: "Failed to establish communication with the test runner. (Underlying Error: Channel disconnected)"
        )
      ]
    )

    #expect(
      ValidationRetryPolicy.shouldRetrySimulatorScenario(
        destination: .iPadSimulator,
        summary: summary
      )
    )
    #expect(
      !ValidationRetryPolicy.shouldRetrySimulatorScenario(
        destination: .macOS,
        summary: summary
      )
    )
  }

  @Test func retryPolicyRetriesTransientSimulatorRunnerLaunchCrashes() {
    let summary = ValidationTestSummary(
      result: "Failed",
      passedTests: 0,
      failedTests: 1,
      testFailures: [
        ValidationTestFailure(
          testIdentifier: "XcodeValidationGallery encountered an error",
          failureText:
            "Failed to install or launch the test runner. (Underlying Error: The operation couldn’t be completed. (Mach error -308 - (ipc/mig) server died))"
        )
      ]
    )

    #expect(
      ValidationRetryPolicy.shouldRetrySimulatorScenario(
        destination: .iPhoneSimulator,
        summary: summary
      )
    )
    #expect(
      !ValidationRetryPolicy.shouldRetrySimulatorScenario(
        destination: .macOS,
        summary: summary
      )
    )
  }

  @Test func retryPolicyRetriesTransientSimulatorBootstrapSignalTermCrashes() {
    let summary = ValidationTestSummary(
      result: "Failed",
      passedTests: 0,
      failedTests: 1,
      testFailures: [
        ValidationTestFailure(
          testIdentifier: "XcodeValidationGallery encountered an error",
          failureText:
            "Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with signal term before establishing connection.)"
        )
      ]
    )

    #expect(
      ValidationRetryPolicy.shouldRetrySimulatorScenario(
        destination: .iPadSimulator,
        summary: summary
      )
    )
    #expect(
      !ValidationRetryPolicy.shouldRetrySimulatorScenario(
        destination: .macOS,
        summary: summary
      )
    )
  }

  @Test func retryPolicyUsesThreeAttemptsForSimulatorDestinations() {
    #expect(ValidationRetryPolicy.maxAttempts(for: .macOS) == 1)
    #expect(ValidationRetryPolicy.maxAttempts(for: .iPhoneSimulator) == 3)
    #expect(ValidationRetryPolicy.maxAttempts(for: .iPadSimulator) == 3)
  }

  @Test func retryPolicyAllowsTransientSimulatorFailuresUntilFinalAttempt() {
    let summary = ValidationTestSummary(
      result: "Failed",
      passedTests: 0,
      failedTests: 1,
      testFailures: [
        ValidationTestFailure(
          testIdentifier: "XcodeValidationGallery encountered an error",
          failureText:
            "Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with signal term before establishing connection.)"
        )
      ]
    )

    #expect(
      ValidationRetryPolicy.shouldRetryScenario(
        destination: .iPadSimulator,
        summary: summary,
        afterAttempt: 0,
        maxAttempts: 3
      )
    )
    #expect(
      ValidationRetryPolicy.shouldRetryScenario(
        destination: .iPadSimulator,
        summary: summary,
        afterAttempt: 1,
        maxAttempts: 3
      )
    )
    #expect(
      !ValidationRetryPolicy.shouldRetryScenario(
        destination: .iPadSimulator,
        summary: summary,
        afterAttempt: 2,
        maxAttempts: 3
      )
    )
    #expect(
      !ValidationRetryPolicy.shouldRetryScenario(
        destination: .macOS,
        summary: summary,
        afterAttempt: 0,
        maxAttempts: 1
      )
    )
  }

  @Test func retryPolicyDoesNotRetryDeterministicAccessibilityFailures() {
    let summary = ValidationTestSummary(
      result: "Failed",
      passedTests: 7,
      failedTests: 1,
      testFailures: [
        ValidationTestFailure(
          testIdentifier: "SymphonySwiftUIAppUITests/testAccessibilityAuditCoversRequiredCheckpoints()",
          failureText: "Element has no description"
        )
      ]
    )

    #expect(
      !ValidationRetryPolicy.shouldRetrySimulatorScenario(
        destination: .iPadSimulator,
        summary: summary
      )
    )
  }
}
