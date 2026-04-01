import Foundation

extension ArtifactManager {
  func resolveArtifacts(workspace: WorkspaceContext, request: ArtifactsCommandRequest) throws
    -> String
  {
    let familyRoot = workspace.buildStateRoot.appendingPathComponent(
      "artifacts/\(request.command.rawValue)", isDirectory: true)
    let resolvedRoot: URL

    if let runID = request.runID {
      let candidates = try fileManager.contentsOfDirectory(
        at: familyRoot, includingPropertiesForKeys: nil
      )
      .filter { $0.lastPathComponent.hasSuffix("-\(runID)") }
      guard let match = candidates.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last
      else {
        throw SymphonyHarnessError(
          code: "missing_artifact_run", message: "No artifact root was found for run id '\(runID)'."
        )
      }
      resolvedRoot = match
    } else {
      let latest = familyRoot.appendingPathComponent("latest")
      guard fileManager.fileExists(atPath: latest.path) else {
        throw SymphonyHarnessError(
          code: "missing_artifacts",
          message:
            "No latest artifact root exists for the \(request.command.rawValue) command family.")
      }
      resolvedRoot = latest.resolvingSymlinksInPath()
    }

    let index = try loadArtifactIndexIfPresent(
      at: resolvedRoot.appendingPathComponent("index.json"))
    let indexedEntries = index?.entries ?? []
    let entryByName = Dictionary(uniqueKeysWithValues: indexedEntries.map { ($0.name, $0) })
    let stableNames = stableInspectionNames(for: request.command)
    let orderedNames = stableNames + indexedEntries.map(\.name).filter { !stableNames.contains($0) }
    let lines =
      [resolvedRoot.path]
      + orderedNames.map { name in
        let relativePath = entryByName[name]?.relativePath ?? name
        let path = resolvedRoot.appendingPathComponent(relativePath).path
        if let entry = entryByName[name], entry.kind == "missing" {
          if let code = entry.anomaly?.code {
            return "\(name) [missing: \(code)] \(path)"
          }
          return "\(name) [missing] \(path)"
        }
        if fileManager.fileExists(atPath: path) {
          return "\(name) \(path)"
        }
        return "\(name) [missing] \(path)"
      }
    return lines.joined(separator: "\n")
  }

  func prepareRoots(executionContext: ExecutionContext, command: BuildCommandFamily) throws
  {
    try fileManager.createDirectory(
      at: executionContext.derivedDataPath, withIntermediateDirectories: true)
    try fileManager.createDirectory(
      at: executionContext.resultBundlePath.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try fileManager.createDirectory(
      at: executionContext.logPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(
      at: executionContext.artifactRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(
      at: executionContext.runtimeRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(
      at: executionContext.artifactRoot.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    _ = command
  }

  func additionalEntries(in artifactRoot: URL, excluding knownNames: Set<String>, createdAt: String)
    throws -> [ArtifactIndexEntry]
  {
    let urls = try fileManager.contentsOfDirectory(
      at: artifactRoot,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { !knownNames.contains($0.lastPathComponent) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var entries = [ArtifactIndexEntry]()
    for url in urls {
      entries.append(
        ArtifactIndexEntry(
          name: url.lastPathComponent, relativePath: url.lastPathComponent, kind: kind(for: url),
          createdAt: createdAt))
    }
    return entries
  }

  func exportXCResult(
    resultBundlePath: URL,
    summaryJSONPath: URL,
    diagnosticsPath: URL,
    attachmentsPath: URL,
    artifactRoot: URL
  ) throws -> [ArtifactAnomaly] {
    var anomalies = [ArtifactAnomaly]()

    let summary = try processRunner.run(
      command: "xcrun",
      arguments: [
        "xcresulttool", "get", "object", "--legacy", "--path", resultBundlePath.path, "--format",
        "json",
      ],
      environment: [:],
      currentDirectory: nil
    )
    if summary.exitStatus == 0, !summary.stdout.isEmpty {
      try summary.stdout.write(to: summaryJSONPath, atomically: true, encoding: .utf8)
    } else {
      try "{}\n".write(to: summaryJSONPath, atomically: true, encoding: .utf8)
      anomalies.append(
        ArtifactAnomaly(
          code: "xcresult_summary_export_failed",
          message: summary.combinedOutput.isEmpty
            ? "Failed to export xcresult summary." : summary.combinedOutput, phase: "xcresult"))
    }

    let diagnostics = try processRunner.run(
      command: "xcrun",
      arguments: [
        "xcresulttool", "export", "diagnostics", "--path", resultBundlePath.path, "--output-path",
        diagnosticsPath.path,
      ], environment: [:], currentDirectory: nil)
    if diagnostics.exitStatus != 0 {
      anomalies.append(
        ArtifactAnomaly(
          code: "xcresult_diagnostics_export_failed",
          message: diagnostics.combinedOutput.isEmpty
            ? "Failed to export diagnostics." : diagnostics.combinedOutput, phase: "xcresult"))
    }

    let attachments = try processRunner.run(
      command: "xcrun",
      arguments: [
        "xcresulttool", "export", "attachments", "--path", resultBundlePath.path, "--output-path",
        attachmentsPath.path,
      ], environment: [:], currentDirectory: nil)
    if attachments.exitStatus != 0 {
      anomalies.append(
        ArtifactAnomaly(
          code: "xcresult_attachments_export_failed",
          message: attachments.combinedOutput.isEmpty
            ? "Failed to export attachments." : attachments.combinedOutput, phase: "xcresult"))
    }

    anomalies.append(
      contentsOf: createOptionalAliases(
        in: artifactRoot, diagnosticsPath: diagnosticsPath, attachmentsPath: attachmentsPath))
    return anomalies
  }

  func createOptionalAliases(
    in artifactRoot: URL, diagnosticsPath: URL, attachmentsPath: URL
  ) -> [ArtifactAnomaly] {
    var anomalies = [ArtifactAnomaly]()
    let candidates = recursiveFiles(in: [diagnosticsPath, attachmentsPath])

    let mappings: [(String, (URL) -> Bool, String)] = [
      ("recording.mp4", { $0.pathExtension.lowercased() == "mp4" }, "missing_recording"),
      ("screen.png", { $0.pathExtension.lowercased() == "png" }, "missing_screen_capture"),
      (
        "ui-tree.txt",
        {
          let name = $0.lastPathComponent.lowercased()
          return $0.pathExtension.lowercased() == "txt"
            && (name.contains("ui") || name.contains("tree") || name.contains("hierarchy"))
        }, "missing_ui_tree"
      ),
    ]

    for (name, predicate, code) in mappings {
      let destination = artifactRoot.appendingPathComponent(name)
      if let source = candidates.first(where: predicate) {
        try? link(destination, to: source)
      } else {
        anomalies.append(
          ArtifactAnomaly(
            code: code, message: "No exported artifact was available for \(name).",
            phase: "xcresult"))
      }
    }

    return anomalies
  }

  func recursiveFiles(in directories: [URL]) -> [URL] {
    directories.flatMap { directory -> [URL] in
      guard let enumerator = enumeratorFactory(directory) else {
        return []
      }
      return enumerator.compactMap { $0 as? URL }
    }
  }

  func updateLatestLink(familyRoot: URL, target: URL) throws {
    Self.latestLinkLock.lock()
    defer { Self.latestLinkLock.unlock() }

    try fileManager.createDirectory(at: familyRoot, withIntermediateDirectories: true)
    let latest = familyRoot.appendingPathComponent("latest")
    let temporary = familyRoot.appendingPathComponent(".latest-\(UUID().uuidString)")
    try fileManager.createSymbolicLink(at: temporary, withDestinationURL: target)
    if fileManager.fileExists(atPath: latest.path) {
      try fileManager.removeItem(at: latest)
    }
    try fileManager.moveItem(at: temporary, to: latest)
  }

  func link(_ destination: URL, to source: URL) throws {
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
  }

  func kind(for url: URL) -> String {
    var isDirectory: ObjCBool = false
    fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
    return isDirectory.boolValue ? "directory" : "file"
  }

  func anomalyName(_ anomaly: ArtifactAnomaly) -> String? {
    switch anomaly.code {
    case "missing_result_bundle":
      return "result.xcresult"
    case "not_applicable_result_bundle":
      return "result.xcresult"
    case "not_applicable_diagnostics":
      return "diagnostics"
    case "not_applicable_attachments":
      return "attachments"
    case "missing_recording":
      return "recording.mp4"
    case "not_applicable_recording":
      return "recording.mp4"
    case "missing_screen_capture":
      return "screen.png"
    case "not_applicable_screen_capture":
      return "screen.png"
    case "missing_ui_tree":
      return "ui-tree.txt"
    case "not_applicable_ui_tree":
      return "ui-tree.txt"
    default:
      return nil
    }
  }

  func loadArtifactIndexIfPresent(at url: URL) throws -> ArtifactIndex? {
    guard fileManager.fileExists(atPath: url.path) else {
      return nil
    }

    return try JSONDecoder().decode(ArtifactIndex.self, from: Data(contentsOf: url))
  }

  func stableInspectionNames(for command: BuildCommandFamily) -> [String] {
    switch command {
    case .harness:
      [
        "summary.json",
        "summary.txt",
        "index.json",
        "package-inspection.json",
        "package-inspection.txt",
        "client-inspection.json",
        "client-inspection.txt",
        "server-inspection.json",
        "server-inspection.txt",
      ]
    case .test:
      [
        "log.txt",
        "result.xcresult",
        "summary.json",
        "summary.txt",
        "index.json",
        "coverage.json",
        "coverage.txt",
        "coverage-inspection.json",
        "coverage-inspection.txt",
        "coverage-inspection-raw.json",
        "coverage-inspection-raw.txt",
        "diagnostics",
        "attachments",
        "process-stdout-stderr.txt",
        "recording.mp4",
        "screen.png",
        "ui-tree.txt",
      ]
    case .build, .run:
      [
        "log.txt",
        "result.xcresult",
        "summary.json",
        "summary.txt",
        "index.json",
        "diagnostics",
        "attachments",
        "process-stdout-stderr.txt",
        "recording.mp4",
        "screen.png",
        "ui-tree.txt",
      ]
    }
  }
}
