#if os(macOS)
  import Foundation
  import SymphonyServerCore
  import Testing

  @testable import SymphonySwiftUIApp

  @Suite("LocalServerTypes", .tags(.model, .localServer))
  struct LocalServerTypesTests {

    // MARK: - WorkflowPromptPreset

    fileprivate struct PresetExpectation: Sendable, CustomTestStringConvertible {
      let preset: WorkflowPromptPreset
      let expectedTitle: String
      let promptIsEmpty: Bool

      var testDescription: String { preset.rawValue }

      static let cases: [PresetExpectation] = [
        .init(preset: .generalIssueResolution, expectedTitle: "General Issue Resolution", promptIsEmpty: false),
        .init(preset: .featureDelivery, expectedTitle: "Feature Delivery", promptIsEmpty: false),
        .init(preset: .bugInvestigation, expectedTitle: "Bug Investigation", promptIsEmpty: false),
        .init(preset: .blank, expectedTitle: "Blank", promptIsEmpty: true),
      ]
    }

    @Test(arguments: PresetExpectation.cases)
    fileprivate func presetTitleAndSeededPrompt(expectation: PresetExpectation) {
      #expect(expectation.preset.title == expectation.expectedTitle)
      #expect(expectation.preset.seededPrompt.isEmpty == expectation.promptIsEmpty)
      #expect(expectation.preset.id == expectation.preset.rawValue)
    }

    @Test func presetSeededPromptsContainExpectedPlaceholders() {
      #expect(WorkflowPromptPreset.generalIssueResolution.seededPrompt.contains("{{issue.title}}"))
      #expect(WorkflowPromptPreset.featureDelivery.seededPrompt.contains("{{issue.title}}"))
      #expect(WorkflowPromptPreset.bugInvestigation.seededPrompt.contains("{{issue.title}}"))
    }

    // MARK: - LocalServerProfile

    @Test func profileResolvedWorkflowURLFromPath() {
      let profile = LocalServerProfile(workflowPath: "/tmp/WORKFLOW.md")
      let resolved = profile.resolvedWorkflowURL()
      #expect(resolved == URL(fileURLWithPath: "/tmp/WORKFLOW.md"))
    }

    @Test func profileResolvedWorkflowURLExpandsTilde() {
      let profile = LocalServerProfile(workflowPath: "~/WORKFLOW.md")
      let resolved = profile.resolvedWorkflowURL()
      #expect(resolved?.path.contains("~") == false)
      #expect(resolved?.lastPathComponent == "WORKFLOW.md")
    }

    @Test func profileResolvedWorkflowURLReturnsNilForEmptyPath() {
      let profile = LocalServerProfile(workflowPath: "   ")
      let resolved = profile.resolvedWorkflowURL()
      #expect(resolved == nil)
    }

    @Test func profileResolvedWorkflowURLReturnsNilForNilPath() {
      let profile = LocalServerProfile()
      let resolved = profile.resolvedWorkflowURL()
      #expect(resolved == nil)
    }

    @Test func profileResolvedWorkflowURLPrefersBookmark() {
      let expectedURL = URL(fileURLWithPath: "/tmp/resolved-bookmark.md")
      let profile = LocalServerProfile(
        workflowBookmarkData: Data([1, 2, 3]),
        workflowPath: "/tmp/fallback.md"
      )
      let resolved = profile.resolvedWorkflowURL { _ in
        (url: expectedURL, isStale: false)
      }
      #expect(resolved == expectedURL)
    }

    @Test func profileResolvedWorkflowURLFallsToPathOnBookmarkFailure() {
      let profile = LocalServerProfile(
        workflowBookmarkData: Data([1, 2, 3]),
        workflowPath: "/tmp/fallback.md"
      )
      let resolved = profile.resolvedWorkflowURL { _ in
        throw TestModelFailure.failed("stale")
      }
      #expect(resolved == URL(fileURLWithPath: "/tmp/fallback.md"))
    }

    // MARK: - WorkflowAuthoringDraft

    @Test func draftDefaultInitUsesGeneralPreset() {
      let draft = WorkflowAuthoringDraft()
      #expect(draft.promptPreset == .generalIssueResolution)
      #expect(draft.promptBody.contains("{{issue.title}}"))
      #expect(draft.serverHost == "127.0.0.1")
    }

    @Test func draftInitFromDefinitionUsesBlankPreset() {
      let definition = WorkflowDefinition(
        config: .defaults,
        promptTemplate: "Custom prompt"
      )
      let draft = WorkflowAuthoringDraft(definition: definition)
      #expect(draft.promptPreset == .blank)
      #expect(draft.promptBody == "Custom prompt")
    }

    // MARK: - renderCodexSandbox

    @Test func renderCodexSandboxStringValue() {
      let draft = WorkflowAuthoringDraft(
        config: WorkflowConfig(providers: .init(codex: .init(sessionSandbox: .string("network-only"))))
      )
      #expect(draft.codexSessionSandbox == "network-only")
    }

    @Test func renderCodexSandboxBoolValue() {
      let draft = WorkflowAuthoringDraft(
        config: WorkflowConfig(providers: .init(codex: .init(sessionSandbox: .bool(true))))
      )
      #expect(draft.codexSessionSandbox == "true")
    }

    @Test func renderCodexSandboxIntegerValue() {
      let draft = WorkflowAuthoringDraft(
        config: WorkflowConfig(providers: .init(codex: .init(sessionSandbox: .integer(42))))
      )
      #expect(draft.codexSessionSandbox == "42")
    }

    @Test func renderCodexSandboxDoubleValue() {
      let draft = WorkflowAuthoringDraft(
        config: WorkflowConfig(providers: .init(codex: .init(sessionSandbox: .double(3.14))))
      )
      #expect(draft.codexSessionSandbox == "3.14")
    }

    @Test func renderCodexSandboxNullValue() {
      let draft = WorkflowAuthoringDraft(
        config: WorkflowConfig(providers: .init(codex: .init(sessionSandbox: .null)))
      )
      #expect(draft.codexSessionSandbox == "null")
    }

    @Test func renderCodexSandboxArrayValue() {
      let draft = WorkflowAuthoringDraft(
        config: WorkflowConfig(providers: .init(codex: .init(sessionSandbox: .array([.string("a"), .string("b")]))))
      )
      #expect(draft.codexSessionSandbox.contains("- a"))
      #expect(draft.codexSessionSandbox.contains("- b"))
    }

    @Test func renderCodexSandboxObjectValue() {
      let draft = WorkflowAuthoringDraft(
        config: WorkflowConfig(providers: .init(codex: .init(sessionSandbox: .object(["key": .string("val")]))))
      )
      #expect(draft.codexSessionSandbox == "key: val")
    }

    // MARK: - WorkflowAuthoringError

    @Test func authoringErrorDescriptions() {
      let intError = WorkflowAuthoringError.invalidInteger(field: "port", value: "abc")
      #expect(intError.errorDescription?.contains("port") == true)
      #expect(intError.errorDescription?.contains("abc") == true)

      let lineError = WorkflowAuthoringError.invalidStateConcurrencyLine("bad line")
      #expect(lineError.errorDescription?.contains("bad line") == true)
    }

    // MARK: - LocalServerLaunchError

    fileprivate struct LaunchErrorExpectation: @unchecked Sendable, CustomTestStringConvertible {
      let error: LocalServerLaunchError
      let expectedSubstring: String

      var testDescription: String { expectedSubstring }

      static let cases: [LaunchErrorExpectation] = [
        .init(error: .workflowNotConfigured, expectedSubstring: "WORKFLOW.md"),
        .init(error: .workflowMissing("/tmp/W.md"), expectedSubstring: "/tmp/W.md"),
        .init(error: .invalidPort("abc"), expectedSubstring: "abc"),
        .init(error: .missingEnvironmentKeys(["A", "B"]), expectedSubstring: "A, B"),
        .init(error: .helperUnavailable("/path"), expectedSubstring: "/path"),
        .init(error: .startupFailed("boom"), expectedSubstring: "boom"),
        .init(error: .helperExitedBeforeReady(1), expectedSubstring: "status 1"),
        .init(error: .healthTimedOut("localhost:8080"), expectedSubstring: "localhost:8080"),
        .init(error: .occupiedPort(9090), expectedSubstring: "9090"),
      ]
    }

    @Test(arguments: LaunchErrorExpectation.cases)
    fileprivate func launchErrorDescription(expectation: LaunchErrorExpectation) {
      #expect(expectation.error.localizedDescription.contains(expectation.expectedSubstring))
    }

    // MARK: - LocalServerEnvironmentEntry

    @Test func environmentEntryDefaults() {
      let entry = LocalServerEnvironmentEntry(name: "TOKEN")
      #expect(entry.value == "")
      #expect(entry.isRequired == false)
      #expect(entry.name == "TOKEN")
    }

    // MARK: - LocalServerStatusSnapshot

    @Test func statusSnapshotDefaults() {
      let snapshot = LocalServerStatusSnapshot(state: .idle, endpoint: .defaultEndpoint)
      #expect(snapshot.transcript.isEmpty)
      #expect(snapshot.failureDescription == nil)
      #expect(snapshot.processIdentifier == nil)
    }

    // MARK: - LocalServerLaunchState

    @Test func launchStateRawValues() {
      #expect(LocalServerLaunchState.idle.rawValue == "idle")
      #expect(LocalServerLaunchState.running.rawValue == "running")
      #expect(LocalServerLaunchState.failed.rawValue == "failed")
      #expect(LocalServerLaunchState.needsSetup.rawValue == "needsSetup")
      #expect(LocalServerLaunchState.validating.rawValue == "validating")
      #expect(LocalServerLaunchState.starting.rawValue == "starting")
      #expect(LocalServerLaunchState.waitingForHealth.rawValue == "waitingForHealth")
    }

    // MARK: - SymphonyServerBootstrapEnvironment

    @Test func bootstrapEnvironmentKeys() {
      #expect(SymphonyServerBootstrapEnvironment.workflowPathKey == "SYMPHONY_WORKFLOW_PATH")
      #expect(SymphonyServerBootstrapEnvironment.serverSQLitePathKey == "SYMPHONY_STORAGE_SQLITE_PATH")
    }
  }
#endif
