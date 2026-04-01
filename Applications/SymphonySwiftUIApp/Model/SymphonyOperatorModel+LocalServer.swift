import Foundation
import SymphonyServerCore
import SymphonyShared

// MARK: - Local Server

#if os(macOS)
  extension SymphonyOperatorModel {
    func testingMakeLocalServerLaunchRequest() throws -> LocalServerLaunchRequest {
      try makeLocalServerLaunchRequest()
    }

    func testingPersistLocalServerDraft() throws {
      try persistLocalServerDraft()
    }

    func testingWorkflowAuthoringPreview() -> WorkflowAuthoringPreviewState {
      workflowAuthoringPreview
    }

    func prepareLocalServerEditor(mode: ServerEditorMode) {
      guard mode == .localServer else {
        return
      }

      workflowAuthoringFailure = nil
      if let workflowURL = try? currentLocalWorkflowURL() {
        loadWorkflowAuthoringDraft(from: workflowURL)
        localWorkflowWizardStep = .localServer
      } else {
        synchronizeWorkflowAuthoringDraftFromLocalServerFields()
        localWorkflowWizardStep = .workflow
      }
    }

    func showWorkflowAuthoringStep() {
      workflowAuthoringFailure = nil
      if let workflowURL = try? currentLocalWorkflowURL() {
        loadWorkflowAuthoringDraft(from: workflowURL)
      } else {
        synchronizeWorkflowAuthoringDraftFromLocalServerFields()
      }
      localWorkflowWizardStep = .workflow
    }

    func updateWorkflowAuthoringDraft<Value>(
      _ keyPath: WritableKeyPath<WorkflowAuthoringDraft, Value>,
      value: Value
    ) {
      var updatedDraft = workflowAuthoringDraft
      updatedDraft[keyPath: keyPath] = value
      workflowAuthoringDraft = updatedDraft
      synchronizeLocalServerFieldsFromWorkflowDraft()
    }

    func applyWorkflowPromptPreset(_ preset: WorkflowPromptPreset) {
      var updatedDraft = workflowAuthoringDraft
      updatedDraft.promptPreset = preset
      updatedDraft.promptBody = preset.seededPrompt
      workflowAuthoringDraft = updatedDraft
    }

    func saveGeneratedWorkflow() {
      guard let services = localServerServices else {
        return
      }

      workflowAuthoringFailure = nil
      localServerFailure = nil
      synchronizeLocalServerFieldsFromWorkflowDraft()

      do {
        let content = try WorkflowAuthoringRenderer.validatedContent(draft: workflowAuthoringDraft)
        let suggestedDirectoryURL =
          try? currentLocalWorkflowURL().deletingLastPathComponent()
        guard
          let savedWorkflowURL = try services.workflowSaver.saveWorkflow(
            named: WorkflowAuthoringDraft.defaultWorkflowFileName,
            suggestedDirectoryURL: suggestedDirectoryURL,
            content: content
          )
        else {
          return
        }

        localServerWorkflowPath = savedWorkflowURL.path
        loadWorkflowAuthoringDraft(from: savedWorkflowURL)

        let variables = try services.variableScanner.scanVariables(at: savedWorkflowURL)
        mergeLocalEnvironmentEntries(requiredKeys: variables)
        try persistLocalServerDraft()
        localServerLaunchState = .idle
        localWorkflowWizardStep = .localServer
      } catch {
        workflowAuthoringFailure = error.localizedDescription
      }
    }

    func loadLocalServerProfile() {
      guard let services = localServerServices,
        let profile = services.profileStore.loadProfile()
      else {
        localServerLaunchState = hasLocalServerSupport ? .needsSetup : .idle
        return
      }

      if let workflowURL = profile.resolvedWorkflowURL() {
        localServerWorkflowPath = workflowURL.path
      } else {
        localServerWorkflowPath = profile.workflowPath ?? ""
      }
      host = profile.host
      portText = String(profile.port)
      localServerSQLitePath = profile.sqlitePath ?? ""
      localServerEnvironmentEntries = profile.environmentKeys.map { key in
        LocalServerEnvironmentEntry(
          name: key,
          value: services.secretStore.secret(for: key) ?? "",
          isRequired: true
        )
      }
      if let workflowURL = profile.resolvedWorkflowURL(),
        let definition = try? WorkflowParser.parse(contentsOf: workflowURL)
      {
        applyWorkflowDefinition(definition)
      }
      if localServerWorkflowPath.isEmpty {
        localServerLaunchState = .needsSetup
        localWorkflowWizardStep = .workflow
      } else {
        localWorkflowWizardStep = .localServer
      }
    }

    func chooseLocalWorkflow() {
      guard let services = localServerServices,
        let workflowURL = services.workflowSelector.selectWorkflowURL()
      else {
        return
      }

      localServerWorkflowPath = workflowURL.path
      localServerFailure = nil
      workflowAuthoringFailure = nil
      do {
        loadWorkflowAuthoringDraft(from: workflowURL)
        let variables = try services.variableScanner.scanVariables(at: workflowURL)
        mergeLocalEnvironmentEntries(requiredKeys: variables)
        try persistLocalServerDraft()
        localServerLaunchState = .idle
        localWorkflowWizardStep = .localServer
      } catch {
        localServerLaunchState = .failed
        localServerFailure = error.localizedDescription
      }
    }

    func addLocalServerEnvironmentEntry() {
      localServerEnvironmentEntries.append(LocalServerEnvironmentEntry(name: ""))
    }

    func removeLocalServerEnvironmentEntry(id: UUID) {
      localServerEnvironmentEntries.removeAll { $0.id == id }
    }

    public func startLocalServer() async {
      guard let services = localServerServices else {
        return
      }

      do {
        localServerLaunchState = .validating
        localServerFailure = nil
        let request = try makeLocalServerLaunchRequest()
        try persistLocalServerDraft()
        await services.manager.start(request: request)
        if services.manager.statusSnapshot.state == .running {
          host = request.endpoint.host
          portText = String(request.endpoint.port)
          connectionError = nil
          await connect()
        }
      } catch let error as LocalServerLaunchError {
        localServerFailure = error.localizedDescription
        localServerLaunchState =
          switch error {
          case .workflowNotConfigured, .workflowMissing, .invalidPort, .missingEnvironmentKeys:
            .needsSetup
          case .helperUnavailable, .startupFailed, .helperExitedBeforeReady, .healthTimedOut,
            .occupiedPort:
            .failed
          }
      } catch {
        localServerFailure = error.localizedDescription
        localServerLaunchState = .failed
      }
    }

    public func restartLocalServer() async {
      guard let services = localServerServices else {
        return
      }

      do {
        localServerLaunchState = .validating
        localServerFailure = nil
        let request = try makeLocalServerLaunchRequest()
        try persistLocalServerDraft()
        await services.manager.restart(request: request)
        if services.manager.statusSnapshot.state == .running {
          host = request.endpoint.host
          portText = String(request.endpoint.port)
          connectionError = nil
          await connect()
        }
      } catch {
        localServerFailure = error.localizedDescription
        localServerLaunchState = .failed
      }
    }

    public func stopLocalServer() async {
      guard let services = localServerServices else {
        return
      }

      await services.manager.stop()
      disconnectFromServer()
    }

    func configureLocalServerServices() {
      guard let localServerServices else {
        return
      }

      localServerServices.manager.onStatusChange = { [weak self] snapshot in
        self?.applyLocalServerStatus(snapshot)
      }
      applyLocalServerStatus(localServerServices.manager.statusSnapshot)
      loadLocalServerProfile()
    }

    private func applyLocalServerStatus(_ snapshot: LocalServerStatusSnapshot) {
      localServerLaunchState = snapshot.state
      localServerTranscript = snapshot.transcript
      localServerFailure = snapshot.failureDescription
      if snapshot.state == .running {
        host = snapshot.endpoint.host
        portText = String(snapshot.endpoint.port)
      }
    }

    func persistLocalServerDraft() throws {
      guard let services = localServerServices else {
        return
      }

      let workflowURL = try currentLocalWorkflowURL()
      let port = try resolvedLocalServerPort()
      let environmentEntries = sanitizedLocalEnvironmentEntries()
      let profile = LocalServerProfile(
        workflowBookmarkData: try? LocalServerProfile.bookmarkData(for: workflowURL),
        workflowPath: workflowURL.path,
        host: resolvedLocalServerHost(),
        port: port,
        sqlitePath: normalizedOptionalText(localServerSQLitePath),
        environmentKeys: environmentEntries.map(\.name)
      )

      let previousKeys = Set(services.profileStore.loadProfile()?.environmentKeys ?? [])
      let nextKeys = Set(profile.environmentKeys)
      try services.profileStore.saveProfile(profile)
      for entry in environmentEntries {
        try services.secretStore.setSecret(entry.value, for: entry.name)
      }
      for removedKey in previousKeys.subtracting(nextKeys) {
        try services.secretStore.removeSecret(for: removedKey)
      }
    }

    func makeLocalServerLaunchRequest() throws -> LocalServerLaunchRequest {
      guard let services = localServerServices else {
        throw LocalServerLaunchError.startupFailed("Local server support is unavailable.")
      }

      let workflowURL = try currentLocalWorkflowURL()
      let helperURL = try services.helperLocator.helperURL()
      let port = try resolvedLocalServerPort()
      let host = resolvedLocalServerHost()
      let endpoint = BootstrapServerEndpoint(scheme: "http", host: host, port: port)
      let environmentEntries = sanitizedLocalEnvironmentEntries()
      let missingKeys = environmentEntries.filter {
        $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
          && $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }.map(\.name)

      if !missingKeys.isEmpty {
        throw LocalServerLaunchError.missingEnvironmentKeys(missingKeys)
      }

      var environment = services.environmentProvider()
      for entry in environmentEntries {
        environment[entry.name] = entry.value
      }
      environment[BootstrapEnvironment.serverHostKey] = host
      environment[BootstrapEnvironment.serverPortKey] = String(port)
      environment[SymphonyServerBootstrapEnvironment.workflowPathKey] = workflowURL.path
      if let sqlitePath = normalizedOptionalText(localServerSQLitePath) {
        environment[SymphonyServerBootstrapEnvironment.serverSQLitePathKey] = sqlitePath
      }

      return LocalServerLaunchRequest(
        helperURL: helperURL,
        workflowURL: workflowURL,
        currentDirectoryURL: workflowURL.deletingLastPathComponent(),
        endpoint: endpoint,
        environment: environment
      )
    }

    private func currentLocalWorkflowURL() throws -> URL {
      let trimmedPath = localServerWorkflowPath.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedPath.isEmpty else {
        throw LocalServerLaunchError.workflowNotConfigured
      }

      let workflowURL = URL(fileURLWithPath: NSString(string: trimmedPath).expandingTildeInPath)
      guard FileManager.default.fileExists(atPath: workflowURL.path) else {
        throw LocalServerLaunchError.workflowMissing(workflowURL.path)
      }
      return workflowURL
    }

    private func sanitizedLocalEnvironmentEntries() -> [LocalServerEnvironmentEntry] {
      var ordered = [LocalServerEnvironmentEntry]()
      var seen = Set<String>()

      for entry in localServerEnvironmentEntries {
        let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !seen.contains(trimmedName) else {
          continue
        }
        seen.insert(trimmedName)
        ordered.append(
          LocalServerEnvironmentEntry(
            id: entry.id,
            name: trimmedName,
            value: entry.value.trimmingCharacters(in: .whitespacesAndNewlines),
            isRequired: entry.isRequired
          )
        )
      }
      return ordered
    }

    private func mergeLocalEnvironmentEntries(requiredKeys: [String]) {
      let existingByName = Dictionary(uniqueKeysWithValues: localServerEnvironmentEntries.map {
        ($0.name, $0)
      })
      var merged = [LocalServerEnvironmentEntry]()
      for key in requiredKeys {
        if var existing = existingByName[key] {
          existing.isRequired = true
          merged.append(existing)
        } else {
          merged.append(LocalServerEnvironmentEntry(name: key, isRequired: true))
        }
      }

      for entry in localServerEnvironmentEntries {
        let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !requiredKeys.contains(trimmedName) else {
          continue
        }
        merged.append(
          LocalServerEnvironmentEntry(
            id: entry.id,
            name: trimmedName,
            value: entry.value,
            isRequired: false
          )
        )
      }
      localServerEnvironmentEntries = merged
    }

    private func resolvedLocalServerPort() throws -> Int {
      let trimmedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let port = Int(trimmedPort), (1...65535).contains(port) else {
        throw LocalServerLaunchError.invalidPort(trimmedPort)
      }
      return port
    }

    private func resolvedLocalServerHost() -> String {
      let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmedHost.isEmpty ? BootstrapServerEndpoint.defaultEndpoint.host : trimmedHost
    }

    private func normalizedOptionalText(_ value: String) -> String? {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    private func synchronizeLocalServerFieldsFromWorkflowDraft() {
      host = workflowAuthoringDraft.serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
      portText = workflowAuthoringDraft.serverPort.trimmingCharacters(in: .whitespacesAndNewlines)
      localServerSQLitePath = workflowAuthoringDraft.storageSQLitePath
    }

    private func synchronizeWorkflowAuthoringDraftFromLocalServerFields() {
      var updatedDraft = workflowAuthoringDraft
      updatedDraft.serverHost = resolvedLocalServerHost()
      updatedDraft.serverPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
      updatedDraft.storageSQLitePath = localServerSQLitePath
      workflowAuthoringDraft = updatedDraft
    }

    private func loadWorkflowAuthoringDraft(from workflowURL: URL) {
      guard let definition = try? WorkflowParser.parse(contentsOf: workflowURL) else {
        synchronizeWorkflowAuthoringDraftFromLocalServerFields()
        return
      }
      applyWorkflowDefinition(definition)
    }

    private func applyWorkflowDefinition(_ definition: WorkflowDefinition) {
      var updatedDraft = WorkflowAuthoringDraft(definition: definition)
      updatedDraft.serverHost = resolvedLocalServerHost()
      updatedDraft.serverPort =
        portText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? String(definition.config.server.port) : portText.trimmingCharacters(in: .whitespacesAndNewlines)
      updatedDraft.storageSQLitePath = localServerSQLitePath
      workflowAuthoringDraft = updatedDraft
    }

    private func disconnectFromServer() {
      health = nil
      issues = []
      selectedIssueID = nil
      issueDetail = nil
      selectedRunID = nil
      runDetail = nil
      connectionError = nil
      clearLogs()
    }
  }
#endif
