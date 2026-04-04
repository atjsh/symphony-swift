import Foundation

public enum ValidationCommandBuilder {
  public static func buildForTestingCommand(
    projectRoot: URL,
    subject: ValidationSubject,
    plan: ValidationPlan,
    destination: ValidationDestination,
    buildProfile: ValidationBuildProfile,
    derivedDataPath: URL,
    outputModeQuiet: Bool
  ) -> ValidationCommand {
    let subjectConfiguration = subject.configuration
    let planConfiguration = subjectConfiguration.planConfiguration(for: plan)
    var arguments = [String]()
    if shouldUseQuietOutput(outputModeQuiet: outputModeQuiet, plan: plan) {
      arguments.append("-quiet")
    }
    arguments += [
      "build-for-testing",
      "-project", subjectConfiguration.projectFileName,
      "-scheme", planConfiguration.schemeName,
      "-testPlan", planConfiguration.testPlanName,
      "-destination", destination.xcodeDestination,
      "-derivedDataPath", derivedDataPath.path,
      "-skipPackagePluginValidation",
    ]
    switch buildProfile {
    case .fast:
      arguments += [
        "-enableCodeCoverage", "NO",
        "COMPILER_INDEX_STORE_ENABLE=NO",
      ]
    case .standard:
      break
    }
    return ValidationCommand(
      executable: "xcodebuild",
      arguments: arguments,
      environment: subjectConfiguration.defaultCommandEnvironment,
      currentDirectory: projectRoot
    )
  }

  public static func testWithoutBuildingCommand(
    projectRoot: URL,
    subject: ValidationSubject,
    plan: ValidationPlan,
    xctestrunPath: URL,
    destination: ValidationDestination,
    buildProfile: ValidationBuildProfile,
    resultBundlePath: URL,
    onlyTesting: [String],
    outputModeQuiet: Bool
  ) -> ValidationCommand {
    var arguments = [String]()
    if shouldUseQuietOutput(outputModeQuiet: outputModeQuiet, plan: plan) {
      arguments.append("-quiet")
    }
    arguments += [
      "test-without-building",
      "-xctestrun", xctestrunPath.path,
      "-destination", destination.xcodeDestination,
      "-resultBundlePath", resultBundlePath.path,
      "-skipPackagePluginValidation",
    ]
    if buildProfile == .fast {
      arguments += ["-enableCodeCoverage", "NO"]
    }
    for testIdentifier in onlyTesting {
      arguments += ["-only-testing", testIdentifier]
    }
    return ValidationCommand(
      executable: "xcodebuild",
      arguments: arguments,
      environment: subject.configuration.defaultCommandEnvironment,
      currentDirectory: projectRoot
    )
  }

  private static func shouldUseQuietOutput(
    outputModeQuiet: Bool,
    plan: ValidationPlan
  ) -> Bool {
    outputModeQuiet && plan != .uiTests
  }

  public static func simulatorTerminationCommands(
    projectRoot: URL,
    destination: ValidationDestination,
    bundleIdentifiers: [String]
  ) -> [ValidationCommand] {
    guard let simulatorUDID = destination.simulatorUDID else {
      return []
    }

    return bundleIdentifiers.map { bundleIdentifier in
      ValidationCommand(
        executable: "xcrun",
        arguments: ["simctl", "terminate", simulatorUDID, bundleIdentifier],
        environment: [:],
        currentDirectory: projectRoot
      )
    }
  }

  public static func simulatorRestartCommands(
    projectRoot: URL,
    destination: ValidationDestination
  ) -> [ValidationCommand] {
    guard let simulatorUDID = destination.simulatorUDID else {
      return []
    }

    return [
      ValidationCommand(
        executable: "xcrun",
        arguments: ["simctl", "shutdown", simulatorUDID],
        environment: [:],
        currentDirectory: projectRoot
      ),
      ValidationCommand(
        executable: "xcrun",
        arguments: ["simctl", "boot", simulatorUDID],
        environment: [:],
        currentDirectory: projectRoot
      ),
      ValidationCommand(
        executable: "xcrun",
        arguments: ["simctl", "bootstatus", simulatorUDID, "-b"],
        environment: [:],
        currentDirectory: projectRoot
      ),
    ]
  }
}

public enum ValidationPathFactory {
  public static func makeContext(
    outputRoot: URL,
    phase: RunPhase,
    destination: ValidationDestination,
    plan: ValidationPlan,
    buildProfile: ValidationBuildProfile,
    runName: String
  ) -> ValidationExecutionContext {
    let artifactRoot = outputRoot
      .appendingPathComponent(destination.platformDirectoryName, isDirectory: true)
      .appendingPathComponent(plan.slug, isDirectory: true)
      .appendingPathComponent(phase.slug, isDirectory: true)
      .appendingPathComponent(runName, isDirectory: true)
    let intermediatesRoot = outputRoot
      .appendingPathComponent("intermediates", isDirectory: true)
      .appendingPathComponent(destination.platformDirectoryName, isDirectory: true)
      .appendingPathComponent(plan.slug, isDirectory: true)
      .appendingPathComponent(phase.slug, isDirectory: true)
      .appendingPathComponent(runName, isDirectory: true)
    let buildCacheRoot = outputRoot
      .appendingPathComponent("intermediates", isDirectory: true)
      .appendingPathComponent("build-cache", isDirectory: true)
      .appendingPathComponent(destination.platformDirectoryName, isDirectory: true)
      .appendingPathComponent(plan.slug, isDirectory: true)
      .appendingPathComponent(buildProfile.rawValue, isDirectory: true)
    let mediaDirectory = outputRoot
      .appendingPathComponent(destination.platformDirectoryName, isDirectory: true)
      .appendingPathComponent("media", isDirectory: true)
    let exportsRoot = outputRoot
      .appendingPathComponent("exports", isDirectory: true)
      .appendingPathComponent(destination.platformDirectoryName, isDirectory: true)
      .appendingPathComponent(plan.slug, isDirectory: true)
      .appendingPathComponent(phase.slug, isDirectory: true)
      .appendingPathComponent(runName, isDirectory: true)

    return ValidationExecutionContext(
      artifactRoot: artifactRoot,
      derivedDataPath: buildCacheRoot.appendingPathComponent("derived-data", isDirectory: true),
      resultBundlePath: intermediatesRoot.appendingPathComponent("result.xcresult", isDirectory: true),
      attachmentExportPath: exportsRoot,
      mediaDirectory: mediaDirectory,
      screenshotsDirectory: mediaDirectory.appendingPathComponent("screenshots", isDirectory: true),
      videosDirectory: mediaDirectory.appendingPathComponent("videos", isDirectory: true),
      auditDirectory: mediaDirectory.appendingPathComponent("audit", isDirectory: true)
    )
  }
}

public enum ValidationAttachmentCatalog {
  public static func mediaArtifacts(
    manifestData: Data,
    exportRoot: URL,
    run: ValidationRunRecord
  ) throws -> [MediaArtifact] {
    let manifest = try JSONDecoder().decode([AttachmentTestManifest].self, from: manifestData)
    return manifest.flatMap { testEntry in
      testEntry.attachments.compactMap { attachment in
        guard attachment.exportedFileName.lowercased().hasSuffix(".png") else {
          return nil
        }

        let metadata = AttachmentNameMetadata.parse(attachment.suggestedHumanReadableName)
        return MediaArtifact(
          platform: run.destination.platformDirectoryName,
          plan: run.plan.slug,
          test: testEntry.testIdentifier,
          checkpoint: metadata.checkpoint,
          surface: metadata.surface,
          orientation: metadata.orientation,
          variant: metadata.variant,
          artifactType: metadata.artifactType,
          file: exportRoot.appendingPathComponent(attachment.exportedFileName).path,
          sourceResultBundle: run.resultBundlePath.path
        )
      }
    }
  }
}

public enum ValidationSummaryBuilder {
  public static func makeSummary(
    outputRoot: URL,
    runRecords: [ValidationRunRecord],
    mediaArtifacts: [MediaArtifact],
    auditIssues: [AuditIssueRecord]
  ) -> ValidationSummary {
    let unresolvedBlockers = runRecords
      .filter { $0.phase == .mitigation && $0.outcome == .failed }
      .flatMap(\.summary.testFailures)
      .map(\.testIdentifier)

    let status: ValidationStatus
    if unresolvedBlockers.isEmpty == false {
      status = .blocked
    } else if runRecords.contains(where: { $0.outcome == .failed }) {
      status = .failed
    } else {
      status = .passed
    }

    return ValidationSummary(
      outputRoot: outputRoot.path,
      status: status,
      runRecords: runRecords,
      mediaArtifacts: mediaArtifacts,
      auditIssues: auditIssues,
      unresolvedBlockers: unresolvedBlockers
    )
  }
}

struct AttachmentTestManifest: Decodable {
  struct Attachment: Decodable {
    let exportedFileName: String
    let suggestedHumanReadableName: String
  }

  let attachments: [Attachment]
  let testIdentifier: String
}

struct AttachmentNameMetadata {
  let checkpoint: String
  let surface: String
  let orientation: String
  let variant: String
  let artifactType: MediaArtifactType

  static func parse(_ suggestedName: String) -> AttachmentNameMetadata {
    let trimmedName = stripXCResultSuffix(from: suggestedName)
    let segments = trimmedName.split(separator: "__")
    var fields = [String: String]()
    for segment in segments {
      let parts = segment.split(separator: "=", maxSplits: 1).map(String.init)
      guard parts.count == 2 else {
        continue
      }
      fields[parts[0]] = parts[1]
    }

    return AttachmentNameMetadata(
      checkpoint: fields["checkpoint"] ?? fields["surface"] ?? trimmedName,
      surface: fields["surface"] ?? trimmedName,
      orientation: fields["orientation"] ?? "portrait",
      variant: fields["variant"] ?? "base",
      artifactType: MediaArtifactType(rawValue: fields["artifact"] ?? "screenshot") ?? .screenshot
    )
  }

  private static func stripXCResultSuffix(from suggestedName: String) -> String {
    let noExtension = URL(fileURLWithPath: suggestedName).deletingPathExtension().lastPathComponent
    let pattern = "_\\d+_[A-F0-9-]+$"
    guard
      let expression = try? NSRegularExpression(pattern: pattern),
      let match = expression.firstMatch(
        in: noExtension,
        range: NSRange(location: 0, length: noExtension.utf16.count)
      ),
      let range = Range(match.range, in: noExtension)
    else {
      return noExtension
    }
    return String(noExtension[..<range.lowerBound])
  }
}
