import Foundation

public struct ArtifactRecord {
  public let run: ArtifactRun
  public let anomalies: [ArtifactAnomaly]
}

public struct ArtifactManager {
  static let latestLinkLock = NSLock()
  let fileManager: FileManager
  let processRunner: ProcessRunning
  let enumeratorFactory: (URL) -> FileManager.DirectoryEnumerator?

  public init(
    fileManager: FileManager = .default, processRunner: ProcessRunning = SystemProcessRunner()
  ) {
    self.init(fileManager: fileManager, processRunner: processRunner, enumeratorFactory: nil)
  }

  init(
    fileManager: FileManager = .default,
    processRunner: ProcessRunning = SystemProcessRunner(),
    enumeratorFactory: ((URL) -> FileManager.DirectoryEnumerator?)?
  ) {
    self.fileManager = fileManager
    self.processRunner = processRunner
    self.enumeratorFactory =
      enumeratorFactory ?? { url in
        fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
      }
  }

  func recordXcodeExecution(
    workspace: WorkspaceContext,
    executionContext: ExecutionContext,
    command: BuildCommandFamily,
    product: ProductKind,
    scheme: String,
    destination: ResolvedDestination,
    invocation: String,
    exitStatus: Int32,
    combinedOutput: String,
    startedAt: Date,
    endedAt: Date,
    subjectName: String? = nil,
    extraAnomalies: [ArtifactAnomaly] = []
  ) throws -> ArtifactRecord {
    try prepareRoots(executionContext: executionContext, command: command)

    let artifactRoot = executionContext.artifactRoot
    let summaryPath = artifactRoot.appendingPathComponent("summary.txt")
    let indexPath = artifactRoot.appendingPathComponent("index.json")
    let summaryJSONPath = artifactRoot.appendingPathComponent("summary.json")
    let processLogPath = artifactRoot.appendingPathComponent("process-stdout-stderr.txt")
    let logAliasPath = artifactRoot.appendingPathComponent("log.txt")
    let diagnosticsPath = artifactRoot.appendingPathComponent("diagnostics", isDirectory: true)
    let attachmentsPath = artifactRoot.appendingPathComponent("attachments", isDirectory: true)
    let resultAliasPath = artifactRoot.appendingPathComponent("result.xcresult", isDirectory: true)

    try combinedOutput.write(to: executionContext.logPath, atomically: true, encoding: .utf8)
    try combinedOutput.write(to: processLogPath, atomically: true, encoding: .utf8)
    try fileManager.createDirectory(at: diagnosticsPath, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: attachmentsPath, withIntermediateDirectories: true)
    try link(logAliasPath, to: executionContext.logPath)

    var anomalies = extraAnomalies
    var entries = [ArtifactIndexEntry]()

    if fileManager.fileExists(atPath: executionContext.resultBundlePath.path) {
      try link(resultAliasPath, to: executionContext.resultBundlePath)
      let exportAnomalies = try exportXCResult(
        resultBundlePath: executionContext.resultBundlePath,
        summaryJSONPath: summaryJSONPath,
        diagnosticsPath: diagnosticsPath,
        attachmentsPath: attachmentsPath,
        artifactRoot: artifactRoot
      )
      anomalies.append(contentsOf: exportAnomalies)
    } else {
      anomalies.append(
        ArtifactAnomaly(
          code: "missing_result_bundle",
          message: "The Xcode action did not produce a result bundle.", phase: "xcresult"))
      try "{}\n".write(to: summaryJSONPath, atomically: true, encoding: .utf8)
    }

    let summaryLines =
      [
        "command: \(command.rawValue)"
      ]
      + identitySummaryLines(subjectName: subjectName, product: product)
      + [
        "scheme: \(scheme)",
        "destination: \(destination.displayName)",
        "started_at: \(DateFormatting.iso8601(startedAt))",
        "ended_at: \(DateFormatting.iso8601(endedAt))",
        "exit_code: \(exitStatus)",
        "invocation: \(invocation)",
        "log_path: \(executionContext.logPath.path)",
        "result_bundle_path: \(executionContext.resultBundlePath.path)",
        "artifact_root: \(artifactRoot.path)",
        anomalies.isEmpty
          ? "anomalies: none" : "anomalies: \(anomalies.map(\.code).joined(separator: ", "))",
        "",
        "stdout_stderr:",
        combinedOutput.isEmpty ? "<empty>" : combinedOutput,
      ]
    try summaryLines.joined(separator: "\n").write(
      to: summaryPath, atomically: true, encoding: .utf8)

    let createdAt = DateFormatting.iso8601(endedAt)
    for name in stableInspectionNames(for: command) {
      let url = artifactRoot.appendingPathComponent(name)
      if fileManager.fileExists(atPath: url.path) {
        entries.append(
          ArtifactIndexEntry(
            name: name, relativePath: name, kind: kind(for: url), createdAt: createdAt))
      } else if let anomaly = anomalies.first(where: { anomalyName($0) == name }) {
        entries.append(
          ArtifactIndexEntry(
            name: name, relativePath: name, kind: "missing", createdAt: createdAt, anomaly: anomaly)
        )
      }
    }

    let knownNames = Set(entries.map(\.name))
    entries.append(
      contentsOf: try additionalEntries(
        in: artifactRoot, excluding: knownNames, createdAt: createdAt))

    let index = ArtifactIndex(
      entries: entries, command: command.artifactCommand, runID: executionContext.runID,
      timestamp: executionContext.timestamp, anomalies: anomalies)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(index).write(to: indexPath)

    try updateLatestLink(
      familyRoot: workspace.buildStateRoot.appendingPathComponent(
        "artifacts/\(command.rawValue)", isDirectory: true),
      target: artifactRoot
    )

    let run = ArtifactRun(
      command: command.artifactCommand,
      runID: executionContext.runID,
      timestamp: executionContext.timestamp,
      artifactRoot: artifactRoot,
      summaryPath: summaryPath,
      indexPath: indexPath
    )
    return ArtifactRecord(run: run, anomalies: anomalies)
  }

  func recordSwiftPMExecution(
    workspace: WorkspaceContext,
    executionContext: ExecutionContext,
    command: BuildCommandFamily,
    product: ProductKind,
    scheme: String,
    destination: ResolvedDestination,
    invocation: String,
    exitStatus: Int32,
    combinedOutput: String,
    startedAt: Date,
    endedAt: Date,
    subjectName: String? = nil,
    extraAnomalies: [ArtifactAnomaly] = []
  ) throws -> ArtifactRecord {
    try prepareRoots(executionContext: executionContext, command: command)

    let artifactRoot = executionContext.artifactRoot
    let summaryPath = artifactRoot.appendingPathComponent("summary.txt")
    let indexPath = artifactRoot.appendingPathComponent("index.json")
    let summaryJSONPath = artifactRoot.appendingPathComponent("summary.json")
    let processLogPath = artifactRoot.appendingPathComponent("process-stdout-stderr.txt")
    let logAliasPath = artifactRoot.appendingPathComponent("log.txt")

    try combinedOutput.write(to: executionContext.logPath, atomically: true, encoding: .utf8)
    try combinedOutput.write(to: processLogPath, atomically: true, encoding: .utf8)
    try link(logAliasPath, to: executionContext.logPath)
    try "{}\n".write(to: summaryJSONPath, atomically: true, encoding: .utf8)

    let anomalies =
      extraAnomalies + [
        ArtifactAnomaly(
          code: "not_applicable_result_bundle",
          message: "SwiftPM-backed runs do not produce an xcresult bundle.", phase: "swiftpm"
        ),
        ArtifactAnomaly(
          code: "not_applicable_diagnostics",
          message: "SwiftPM-backed runs do not export xcresult diagnostics.",
          phase: "swiftpm"),
        ArtifactAnomaly(
          code: "not_applicable_attachments",
          message: "SwiftPM-backed runs do not export xcresult attachments.",
          phase: "swiftpm"),
        ArtifactAnomaly(
          code: "not_applicable_recording",
          message: "SwiftPM-backed runs do not produce simulator recordings.",
          phase: "swiftpm"),
        ArtifactAnomaly(
          code: "not_applicable_screen_capture",
          message: "SwiftPM-backed runs do not produce simulator screenshots.",
          phase: "swiftpm"),
        ArtifactAnomaly(
          code: "not_applicable_ui_tree",
          message: "SwiftPM-backed runs do not produce simulator UI trees.", phase: "swiftpm"
        ),
      ]

    let summaryLines =
      [
        "command: \(command.rawValue)"
      ]
      + identitySummaryLines(subjectName: subjectName, product: product)
      + [
        "scheme: \(scheme)",
        "destination: \(destination.displayName)",
        "backend: swiftpm",
        "started_at: \(DateFormatting.iso8601(startedAt))",
        "ended_at: \(DateFormatting.iso8601(endedAt))",
        "exit_code: \(exitStatus)",
        "invocation: \(invocation)",
        "log_path: \(executionContext.logPath.path)",
        "result_bundle_path: <not_applicable>",
        "artifact_root: \(artifactRoot.path)",
        "anomalies: \(anomalies.map(\.code).joined(separator: ", "))",
        "",
        "stdout_stderr:",
        combinedOutput.isEmpty ? "<empty>" : combinedOutput,
      ]
    try summaryLines.joined(separator: "\n").write(
      to: summaryPath, atomically: true, encoding: .utf8)

    let createdAt = DateFormatting.iso8601(endedAt)
    var entries = [ArtifactIndexEntry]()
    for name in stableInspectionNames(for: command) {
      let url = artifactRoot.appendingPathComponent(name)
      if fileManager.fileExists(atPath: url.path) {
        entries.append(
          ArtifactIndexEntry(
            name: name, relativePath: name, kind: kind(for: url), createdAt: createdAt))
      } else if let anomaly = anomalies.first(where: { anomalyName($0) == name }) {
        entries.append(
          ArtifactIndexEntry(
            name: name, relativePath: name, kind: "missing", createdAt: createdAt, anomaly: anomaly)
        )
      }
    }

    let knownNames = Set(entries.map(\.name))
    entries.append(
      contentsOf: try additionalEntries(
        in: artifactRoot, excluding: knownNames, createdAt: createdAt))

    let index = ArtifactIndex(
      entries: entries, command: command.artifactCommand, runID: executionContext.runID,
      timestamp: executionContext.timestamp, anomalies: anomalies)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(index).write(to: indexPath)

    try updateLatestLink(
      familyRoot: workspace.buildStateRoot.appendingPathComponent(
        "artifacts/\(command.rawValue)", isDirectory: true),
      target: artifactRoot
    )

    let run = ArtifactRun(
      command: command.artifactCommand,
      runID: executionContext.runID,
      timestamp: executionContext.timestamp,
      artifactRoot: artifactRoot,
      summaryPath: summaryPath,
      indexPath: indexPath
    )
    return ArtifactRecord(run: run, anomalies: anomalies)
  }

  func identitySummaryLines(subjectName: String?, product: ProductKind) -> [String] {
    if let subjectName {
      return ["subject: \(subjectName)"]
    }
    return ["product: \(product.rawValue)"]
  }

  public func recordHarnessExecution(
    workspace: WorkspaceContext,
    executionContext: ExecutionContext,
    invocation: String,
    exitStatus: Int32,
    summaryJSON: String,
    summaryText: String,
    startedAt: Date,
    endedAt: Date,
    anomalies: [ArtifactAnomaly] = []
  ) throws -> ArtifactRecord {
    try prepareRoots(executionContext: executionContext, command: .harness)

    let artifactRoot = executionContext.artifactRoot
    let summaryPath = artifactRoot.appendingPathComponent("summary.txt")
    let indexPath = artifactRoot.appendingPathComponent("index.json")
    let summaryJSONPath = artifactRoot.appendingPathComponent("summary.json")

    let normalizedSummaryJSON = summaryJSON.hasSuffix("\n") ? summaryJSON : summaryJSON + "\n"
    try normalizedSummaryJSON.write(to: summaryJSONPath, atomically: true, encoding: .utf8)

    let summaryLines = [
      "command: harness",
      "started_at: \(DateFormatting.iso8601(startedAt))",
      "ended_at: \(DateFormatting.iso8601(endedAt))",
      "exit_code: \(exitStatus)",
      "invocation: \(invocation)",
      "artifact_root: \(artifactRoot.path)",
      anomalies.isEmpty
        ? "anomalies: none" : "anomalies: \(anomalies.map(\.code).joined(separator: ", "))",
      "",
      summaryText,
    ]
    try summaryLines.joined(separator: "\n").write(
      to: summaryPath, atomically: true, encoding: .utf8)

    let createdAt = DateFormatting.iso8601(endedAt)
    var entries = [ArtifactIndexEntry]()
    for name in stableInspectionNames(for: .harness) {
      let url = artifactRoot.appendingPathComponent(name)
      if fileManager.fileExists(atPath: url.path) {
        entries.append(
          ArtifactIndexEntry(
            name: name, relativePath: name, kind: kind(for: url), createdAt: createdAt))
      }
    }

    let knownNames = Set(entries.map(\.name))
    let additionalEntries = try fileManager.contentsOfDirectory(
      at: artifactRoot,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { !knownNames.contains($0.lastPathComponent) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    .map { url in
      ArtifactIndexEntry(
        name: url.lastPathComponent,
        relativePath: url.lastPathComponent,
        kind: kind(for: url),
        createdAt: createdAt
      )
    }
    entries.append(contentsOf: additionalEntries)

    let index = ArtifactIndex(
      entries: entries, command: .harness, runID: executionContext.runID,
      timestamp: executionContext.timestamp, anomalies: anomalies)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(index).write(to: indexPath)

    try updateLatestLink(
      familyRoot: workspace.buildStateRoot.appendingPathComponent(
        "artifacts/harness", isDirectory: true),
      target: artifactRoot
    )

    return ArtifactRecord(
      run: ArtifactRun(
        command: .harness,
        runID: executionContext.runID,
        timestamp: executionContext.timestamp,
        artifactRoot: artifactRoot,
        summaryPath: summaryPath,
        indexPath: indexPath
      ),
      anomalies: anomalies
    )
  }
}
