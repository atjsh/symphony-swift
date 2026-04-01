#if os(macOS)
  import Foundation
  import SymphonyShared
  import Testing

  @testable import SymphonySwiftUIApp

  @Suite("Bootstrap Support – macOS", .serialized, .tags(.bootstrap, .localServer))
  struct BootstrapMacOSTests {
    @Test func builtSymphonyAppStartsAndExitsWhenRequested() throws {
      let executable = try #require(Bundle.main.executableURL)
      #expect(FileManager.default.isExecutableFile(atPath: executable.path))

      let process = Process()
      let output = Pipe()
      var environment = ProcessInfo.processInfo.environment
      environment[BootstrapKeepAlivePolicy.exitAfterStartupKey] = "1"
      environment[BootstrapEnvironment.serverSchemeKey] = "https"
      environment[BootstrapEnvironment.serverHostKey] = "app.example.com"
      environment[BootstrapEnvironment.serverPortKey] = "9443"
      process.executableURL = executable
      process.environment = environment
      process.standardOutput = output
      process.standardError = output
      try process.run()
      process.waitUntilExit()

      let transcript = String(
        decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      #expect(process.terminationStatus == 0)
      #expect(transcript.contains("[Symphony] starting"))
      #expect(transcript.contains("[Symphony] endpoint=https://app.example.com:9443"))
    }

    @Test func workflowAuthoringRendererProducesCanonicalValidContent() throws {
      var draft = WorkflowAuthoringDraft()
      draft.trackerProjectOwner = "atjsh"
      draft.trackerProjectOwnerType = "organization"
      draft.trackerProjectNumber = "42"
      draft.trackerRepositoryAllowlistText = "atjsh/symphony-swift"
      draft.agentMaxConcurrentAgentsByStateText = "In Progress: 3\nBlocked: 1"

      let preview = WorkflowAuthoringRenderer.preview(draft: draft)

      #expect(preview.validationError == nil)
      #expect(preview.content.contains("api_key: \"$GITHUB_TOKEN\""))
      #expect(preview.content.contains("repository_allowlist:"))
      #expect(preview.content.contains("max_concurrent_agents_by_state:"))

      let trackerRange = try #require(preview.content.range(of: "\ntracker:\n"))
      let pollingRange = try #require(preview.content.range(of: "\npolling:\n"))
      let workspaceRange = try #require(preview.content.range(of: "\nworkspace:\n"))
      let hooksRange = try #require(preview.content.range(of: "\nhooks:\n"))
      let agentRange = try #require(preview.content.range(of: "\nagent:\n"))
      let providersRange = try #require(preview.content.range(of: "\nproviders:\n"))
      let serverRange = try #require(preview.content.range(of: "\nserver:\n"))
      let storageRange = try #require(preview.content.range(of: "\nstorage:\n"))

      #expect(trackerRange.lowerBound < pollingRange.lowerBound)
      #expect(pollingRange.lowerBound < workspaceRange.lowerBound)
      #expect(workspaceRange.lowerBound < hooksRange.lowerBound)
      #expect(hooksRange.lowerBound < agentRange.lowerBound)
      #expect(agentRange.lowerBound < providersRange.lowerBound)
      #expect(providersRange.lowerBound < serverRange.lowerBound)
      #expect(serverRange.lowerBound < storageRange.lowerBound)
    }

    @Test func workflowAuthoringRendererOmitsBlankOptionalStringsAndKeepsEditableCollectionsExplicit() {
      let preview = WorkflowAuthoringRenderer.preview(draft: WorkflowAuthoringDraft(promptPreset: .blank))

      #expect(preview.validationError == nil)
      #expect(!preview.content.contains("project_owner:"))
      #expect(!preview.content.contains("project_owner_type:"))
      #expect(!preview.content.contains("sqlite_path:"))
      #expect(preview.content.contains("repository_allowlist: []"))
      #expect(preview.content.contains("allowed_tools: []"))
      #expect(preview.content.contains("disallowed_tools: []"))
      #expect(preview.content.contains("max_concurrent_agents_by_state: {}"))
    }

    @Test func workflowPromptPresetSeedsExpectedBodies() {
      #expect(WorkflowPromptPreset.generalIssueResolution.seededPrompt.contains("{{issue.title}}"))
      #expect(WorkflowPromptPreset.featureDelivery.seededPrompt.contains("Deliver the requested feature"))
      #expect(WorkflowPromptPreset.bugInvestigation.seededPrompt.contains("Investigate and fix the bug"))
      #expect(WorkflowPromptPreset.blank.seededPrompt.isEmpty)
    }

    @Test func localServerProfileResolvesWorkflowFromBookmarkAndFallbackPath() throws {
      let workflowURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString
      ).appendingPathComponent("WORKFLOW.md")
      try FileManager.default.createDirectory(
        at: workflowURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try "Resolve {{issue.title}}".write(to: workflowURL, atomically: true, encoding: .utf8)

      let profile = LocalServerProfile(
        workflowBookmarkData: try LocalServerProfile.bookmarkData(for: workflowURL),
        workflowPath: nil,
        host: "localhost",
        port: 8080
      )
      #expect(
        profile.resolvedWorkflowURL()?.resolvingSymlinksInPath()
          == workflowURL.resolvingSymlinksInPath()
      )

      let fallbackProfile = LocalServerProfile(
        workflowBookmarkData: nil,
        workflowPath: workflowURL.path,
        host: "localhost",
        port: 8080
      )
      #expect(
        fallbackProfile.resolvedWorkflowURL()?.resolvingSymlinksInPath()
          == workflowURL.resolvingSymlinksInPath()
      )
    }

    @Test func bundledLocalServerHelperLocatorFindsEmbeddedHelperPath() throws {
      let bundleRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      let helperURL = bundleRoot
        .appendingPathComponent("Symphony.app")
        .appendingPathComponent("Contents/Helpers/SymphonyLocalServerHelper")
      try FileManager.default.createDirectory(
        at: helperURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      FileManager.default.createFile(atPath: helperURL.path, contents: Data())
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: helperURL.path
      )

      let bundle = Bundle(url: bundleRoot.appendingPathComponent("Symphony.app"))!
      let locator = BundledLocalServerHelperLocator(bundle: bundle)
      #expect(try locator.helperURL() == helperURL)
    }

    @Test func bundledLocalServerHelperStartsAndExitsWhenRequested() throws {
      let helperURL = try BundledLocalServerHelperLocator(bundle: .main).helperURL()
      #expect(FileManager.default.isExecutableFile(atPath: helperURL.path))

      let process = Process()
      let output = Pipe()
      process.executableURL = helperURL
      var environment = ProcessInfo.processInfo.environment
      environment[BootstrapKeepAlivePolicy.exitAfterStartupKey] = "1"
      environment[BootstrapEnvironment.serverSchemeKey] = "https"
      environment[BootstrapEnvironment.serverHostKey] = "helper.example.com"
      environment[BootstrapEnvironment.serverPortKey] = "9443"
      process.environment = environment
      process.standardOutput = output
      process.standardError = output
      try process.run()
      process.waitUntilExit()

      let transcript = String(
        decoding: output.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
      )
      #expect(process.terminationStatus == 0)
      #expect(transcript.contains("[SymphonyLocalServerHelper] starting"))
      #expect(transcript.contains("[SymphonyLocalServerHelper] endpoint=https://helper.example.com:9443"))
    }
  }
#endif
