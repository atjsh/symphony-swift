import Foundation
import Testing

@testable import SymphonyXcodeValidation

// MARK: - Markdown Summary and Command Helpers

@Suite("MutationHardening - CommandHelpers")
struct MutationHardeningCommandHelpersTests {

  @Test func renderMarkdownSummaryContainsAllExpectedSections() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let summary = ValidationSummary(
      outputRoot: "/tmp/output",
      status: .passed,
      runRecords: [
        ValidationRunRecord(
          phase: .mitigation,
          destination: .macOS,
          plan: .appTests,
          runName: "progress-report-model",
          outcome: .passed,
          resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
          summary: ValidationTestSummary(
            result: "Passed", passedTests: 1, failedTests: 0, testFailures: []
          ),
          startedAt: Date(timeIntervalSince1970: 10),
          endedAt: Date(timeIntervalSince1970: 20)
        ),
      ],
      mediaArtifacts: [],
      auditIssues: [],
      unresolvedBlockers: []
    )

    let markdown = runner.renderMarkdownSummary(summary)

    #expect(markdown.contains("# Xcode Validation Summary"))
    #expect(markdown.contains("- Status: passed"))
    #expect(markdown.contains("- Output root: /tmp/output"))
    #expect(markdown.contains("- Media artifacts: 0"))
    #expect(markdown.contains("- Audit issues: 0"))
    #expect(markdown.contains("## Runs"))
    #expect(markdown.contains("mitigation | macos | app-tests | progress-report-model | passed"))
    #expect(markdown.contains("## Unresolved Blockers") == false)
  }

  @Test func renderMarkdownSummaryIncludesUnresolvedBlockersSection() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let summary = ValidationSummary(
      outputRoot: "/tmp/output",
      status: .blocked,
      runRecords: [
        ValidationRunRecord(
          phase: .mitigation,
          destination: .macOS,
          plan: .appTests,
          runName: "test",
          outcome: .failed,
          resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
          summary: ValidationTestSummary(
            result: "Failed", passedTests: 0, failedTests: 1,
            testFailures: [
              ValidationTestFailure(testIdentifier: "blocker/test()", failureText: "crash"),
            ]
          ),
          startedAt: Date(timeIntervalSince1970: 10),
          endedAt: Date(timeIntervalSince1970: 20)
        ),
      ],
      mediaArtifacts: [],
      auditIssues: [],
      unresolvedBlockers: ["blocker/test()"]
    )

    let markdown = runner.renderMarkdownSummary(summary)

    #expect(markdown.contains("## Unresolved Blockers"))
    #expect(markdown.contains("- blocker/test()"))
    #expect(markdown.contains("blocker/test(): crash"))
  }

  @Test func trimmedOutputExcerptTruncatesLongOutput() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let longOutput = String(repeating: "error line\n", count: 100)
    let excerpt = runner.trimmedOutputExcerpt(from: longOutput)

    #expect(excerpt.hasSuffix("..."))
    #expect(excerpt.count <= 244)
  }

  @Test func trimmedOutputExcerptReturnsEmptyPlaceholderForBlankInput() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    #expect(runner.trimmedOutputExcerpt(from: "") == "<empty>")
    #expect(runner.trimmedOutputExcerpt(from: "   \n \n  ") == "<empty>")
  }

  @Test func trimmedOutputExcerptReturnsShortOutputUnchanged() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let shortOutput = "error: build failed"
    let excerpt = runner.trimmedOutputExcerpt(from: shortOutput)

    #expect(excerpt == "error: build failed")
    #expect(excerpt.hasSuffix("...") == false)
  }

  @Test func shellQuotedEscapesWhitespaceAndQuoteCharacters() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    #expect(runner.shellQuoted("simple") == "simple")
    #expect(runner.shellQuoted("has space") == "\"has space\"")
    #expect(runner.shellQuoted("has\"quote") == "\"has\\\"quote\"")
    #expect(runner.shellQuoted("has'single") == "\"has'single\"")
    #expect(runner.shellQuoted("has\ttab") == "\"has\ttab\"")
  }

  @Test func checkpointExtractsValueFromAuditPrefixedAttachmentNames() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    #expect(runner.checkpoint(from: "audit__checkpoint=logs__surface=logs.txt") == "audit")
    #expect(runner.checkpoint(from: "screenshot__surface=root.png") == nil)
    #expect(runner.checkpoint(from: "no-prefix") == nil)
  }

  @Test func sanitizedFileNameReplacesSlashColonAndSpace() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let result = runner.sanitizedFileName("path/to:file name.png")
    #expect(result == "path-to-file-name.png")
  }

  @Test func stableFileNameProducesConsistentNaming() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let artifact = MediaArtifact(
      platform: "ios",
      plan: "ui-tests",
      test: "SomeTests/test()",
      checkpoint: "main",
      surface: "root",
      orientation: "landscape",
      variant: "dark",
      artifactType: .screenshot,
      file: "/tmp/original.png",
      sourceResultBundle: "/tmp/result.xcresult"
    )
    let fileName = runner.stableFileName(for: artifact, pathExtension: "png")

    #expect(fileName.contains("platform=ios"))
    #expect(fileName.contains("plan=ui-tests"))
    #expect(fileName.contains("checkpoint=main"))
    #expect(fileName.contains("surface=root"))
    #expect(fileName.contains("orientation=landscape"))
    #expect(fileName.contains("variant=dark"))
    #expect(fileName.contains("artifact=screenshot"))
    #expect(fileName.hasSuffix(".png"))
    #expect(fileName.contains("/") == false)
  }

  @Test func parseSummaryPayloadExtractsTestIdentifierFromStringOrURL() throws {
    let environment = try ValidationRunnerTestEnvironment.make()
    let executor = ValidationProcessExecutorStub()
    let runner = XcodeValidationRunner(processExecutor: executor, now: environment.now)

    let payloadWithString = """
      {"result":"Failed","passedTests":0,"failedTests":1,"testFailures":[{"failureText":"crash","testIdentifierString":"Tests/test()"}]}
      """
    let summary1 = try runner.parseSummaryPayload(from: Data(payloadWithString.utf8))
    #expect(summary1.testFailures[0].testIdentifier == "Tests/test()")

    let payloadWithURL = """
      {"result":"Failed","passedTests":0,"failedTests":1,"testFailures":[{"failureText":"crash","testIdentifierURL":"test://Tests/test()"}]}
      """
    let summary2 = try runner.parseSummaryPayload(from: Data(payloadWithURL.utf8))
    #expect(summary2.testFailures[0].testIdentifier == "test://Tests/test()")
  }
}

// MARK: - Attachment Parsing and Media

@Suite("MutationHardening - AttachmentParsing")
struct MutationHardeningAttachmentParsingTests {

  @Test func mediaArtifactsFiltersPNGAttachmentsOnly() throws {
    let exportRoot = URL(fileURLWithPath: "/tmp/export", isDirectory: true)
    let manifest = """
      [
        {
          "attachments": [
            {
              "configurationName": "Default",
              "deviceId": "stub",
              "deviceName": "Stub",
              "exportedFileName": "screenshot.png",
              "isAssociatedWithFailure": false,
              "suggestedHumanReadableName": "surface=root__orientation=portrait__variant=base__artifact=screenshot_0_ABC.png",
              "timestamp": 1
            },
            {
              "configurationName": "Default",
              "deviceId": "stub",
              "deviceName": "Stub",
              "exportedFileName": "log.txt",
              "isAssociatedWithFailure": false,
              "suggestedHumanReadableName": "log_file.txt",
              "timestamp": 1
            },
            {
              "configurationName": "Default",
              "deviceId": "stub",
              "deviceName": "Stub",
              "exportedFileName": "video.mov",
              "isAssociatedWithFailure": false,
              "suggestedHumanReadableName": "video_0_ABC.mov",
              "timestamp": 1
            }
          ],
          "testIdentifier": "Tests/test()",
          "testIdentifierURL": "test://example"
        }
      ]
      """
    let run = ValidationRunRecord(
      phase: .richCapture, destination: .iPhoneSimulator, plan: .uiTests,
      runName: "rich-media", outcome: .passed,
      resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
      summary: ValidationTestSummary(result: "Passed", passedTests: 1, failedTests: 0, testFailures: []),
      startedAt: Date(timeIntervalSince1970: 10), endedAt: Date(timeIntervalSince1970: 20)
    )

    let artifacts = try ValidationAttachmentCatalog.mediaArtifacts(
      manifestData: Data(manifest.utf8), exportRoot: exportRoot, run: run
    )

    #expect(artifacts.count == 1)
    #expect(artifacts[0].file == "/tmp/export/screenshot.png")
  }

  @Test func attachmentNameMetadataParseExtractsAllFields() {
    let metadata = AttachmentNameMetadata.parse(
      "checkpoint=login__surface=sidebar__orientation=landscape__variant=dark__artifact=auditIssue_0_ABC.png"
    )

    #expect(metadata.checkpoint == "login")
    #expect(metadata.surface == "sidebar")
    #expect(metadata.orientation == "landscape")
    #expect(metadata.variant == "dark")
    #expect(metadata.artifactType == .auditIssue)
  }

  @Test func attachmentNameMetadataParseUsesDefaults() {
    let metadata = AttachmentNameMetadata.parse("surface=root_0_ABC.png")

    #expect(metadata.checkpoint == "root")
    #expect(metadata.surface == "root")
    #expect(metadata.orientation == "portrait")
    #expect(metadata.variant == "base")
    #expect(metadata.artifactType == .screenshot)
  }

  @Test func attachmentNameMetadataParseHandlesNoFields() {
    let metadata = AttachmentNameMetadata.parse("plain-name_0_ABCDEF.png")

    #expect(metadata.checkpoint == "plain-name")
    #expect(metadata.surface == "plain-name")
  }

  @Test func attachmentNameMetadataParseIgnoresMalformedSegments() {
    let metadata = AttachmentNameMetadata.parse("surface=root__badfield__orientation=landscape_0_ABC.png")

    #expect(metadata.surface == "root")
    #expect(metadata.orientation == "landscape")
  }

  @Test func stripXCResultSuffixRemovesTimestampAndUUID() {
    let metadata = AttachmentNameMetadata.parse("surface=root__variant=base_42_E09AB2DE-2B82-49E2-8119-6C2FD1227C04.png")

    #expect(metadata.surface == "root")
    #expect(metadata.variant == "base")
  }
}

// MARK: - Validation Core Logic

@Suite("MutationHardening - CoreLogic")
struct MutationHardeningCoreLogicTests {

  @Test func validationSummaryStatusIsBlockedWhenMitigationFails() {
    let summary = ValidationSummaryBuilder.makeSummary(
      outputRoot: URL(fileURLWithPath: "/tmp/output", isDirectory: true),
      runRecords: [
        ValidationRunRecord(
          phase: .mitigation, destination: .macOS, plan: .appTests,
          runName: "test", outcome: .failed,
          resultBundlePath: URL(fileURLWithPath: "/tmp/r.xcresult"),
          summary: ValidationTestSummary(
            result: "Failed", passedTests: 0, failedTests: 1,
            testFailures: [ValidationTestFailure(testIdentifier: "t()", failureText: "fail")]
          ),
          startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1)
        ),
      ],
      mediaArtifacts: [],
      auditIssues: []
    )

    #expect(summary.status == .blocked)
    #expect(summary.unresolvedBlockers == ["t()"])
  }

  @Test func validationSummaryStatusIsFailedWhenNonMitigationRunFails() {
    let summary = ValidationSummaryBuilder.makeSummary(
      outputRoot: URL(fileURLWithPath: "/tmp/output", isDirectory: true),
      runRecords: [
        ValidationRunRecord(
          phase: .fullMatrix, destination: .macOS, plan: .appTests,
          runName: "full-app", outcome: .failed,
          resultBundlePath: URL(fileURLWithPath: "/tmp/r.xcresult"),
          summary: ValidationTestSummary(
            result: "Failed", passedTests: 0, failedTests: 1,
            testFailures: [ValidationTestFailure(testIdentifier: "t()", failureText: "fail")]
          ),
          startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1)
        ),
      ],
      mediaArtifacts: [],
      auditIssues: []
    )

    #expect(summary.status == .failed)
    #expect(summary.unresolvedBlockers.isEmpty)
  }

  @Test func validationSummaryStatusIsPassedWhenAllRunsPass() {
    let summary = ValidationSummaryBuilder.makeSummary(
      outputRoot: URL(fileURLWithPath: "/tmp/output", isDirectory: true),
      runRecords: [
        ValidationRunRecord(
          phase: .mitigation, destination: .macOS, plan: .appTests,
          runName: "test", outcome: .passed,
          resultBundlePath: URL(fileURLWithPath: "/tmp/r.xcresult"),
          summary: ValidationTestSummary(result: "Passed", passedTests: 1, failedTests: 0, testFailures: []),
          startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1)
        ),
      ],
      mediaArtifacts: [],
      auditIssues: []
    )

    #expect(summary.status == .passed)
  }

  @Test func retryPolicyMaxAttemptsReturnsOneForMacOSThreeForSimulators() {
    #expect(ValidationRetryPolicy.maxAttempts(for: .macOS) == 1)
    #expect(ValidationRetryPolicy.maxAttempts(for: .iPhoneSimulator) == 3)
    #expect(ValidationRetryPolicy.maxAttempts(for: .iPadSimulator) == 3)
  }

  @Test func retryPolicyShouldRetryBlockedOnFinalAttemptBoundary() {
    let transientSummary = ValidationTestSummary(
      result: "Failed", passedTests: 0, failedTests: 1,
      testFailures: [
        ValidationTestFailure(
          testIdentifier: "err",
          failureText: "Failed to establish communication with the test runner"
        ),
      ]
    )

    #expect(
      ValidationRetryPolicy.shouldRetryScenario(
        destination: .iPhoneSimulator, summary: transientSummary,
        afterAttempt: 1, maxAttempts: 3
      ) == true
    )
    #expect(
      ValidationRetryPolicy.shouldRetryScenario(
        destination: .iPhoneSimulator, summary: transientSummary,
        afterAttempt: 2, maxAttempts: 3
      ) == false
    )
  }

  @Test func canonicalMediaKeyNormalizesAbsoluteAndRelativePaths() {
    let absoluteKey = ValidationCanonicalMediaKey(
      platform: "ios", plan: "ui-tests", checkpoint: "main",
      surface: "root", orientation: "portrait", variant: "base",
      artifactType: .screenshot, filePath: "/tmp/./test/../test/file.png"
    )
    let relativeKey = ValidationCanonicalMediaKey(
      platform: "ios", plan: "ui-tests", checkpoint: "main",
      surface: "root", orientation: "portrait", variant: "base",
      artifactType: .screenshot, filePath: "./folder/file.png"
    )

    #expect(absoluteKey.filePath == "/tmp/test/file.png")
    #expect(relativeKey.filePath == "folder/file.png")
  }

  @Test func canonicalMediaKeyFromArtifactUsesArtifactFile() {
    let artifact = MediaArtifact(
      platform: "ios", plan: "ui-tests", test: "t()",
      checkpoint: "main", surface: "root", orientation: "portrait",
      variant: "base", artifactType: .screenshot,
      file: "/tmp/file.png", sourceResultBundle: "/tmp/r.xcresult"
    )

    let key = ValidationCanonicalMediaKey(artifact: artifact)
    #expect(key.filePath == "/tmp/file.png")

    let overriddenKey = ValidationCanonicalMediaKey(artifact: artifact, filePath: "/other/path.png")
    #expect(overriddenKey.filePath == "/other/path.png")
  }
}


