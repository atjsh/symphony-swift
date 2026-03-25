import Foundation

public struct ArtifactRecord {
    public let run: ArtifactRun
    public let anomalies: [ArtifactAnomaly]
}

public struct ArtifactManager {
    private let fileManager: FileManager
    private let processRunner: ProcessRunning
    private let enumeratorFactory: (URL) -> FileManager.DirectoryEnumerator?

    public init(fileManager: FileManager = .default, processRunner: ProcessRunning = SystemProcessRunner()) {
        self.init(fileManager: fileManager, processRunner: processRunner, enumeratorFactory: nil)
    }

    init(
        fileManager: FileManager = .default,
        processRunner: ProcessRunning = SystemProcessRunner(),
        enumeratorFactory: ((URL) -> FileManager.DirectoryEnumerator?)?
    ) {
        self.fileManager = fileManager
        self.processRunner = processRunner
        self.enumeratorFactory = enumeratorFactory ?? { url in
            fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
        }
    }

    public func recordXcodeExecution(
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
            anomalies.append(ArtifactAnomaly(code: "missing_result_bundle", message: "The Xcode action did not produce a result bundle.", phase: "xcresult"))
            try "{}\n".write(to: summaryJSONPath, atomically: true, encoding: .utf8)
        }

        let summaryLines = [
            "command: \(command.rawValue)",
            "product: \(product.rawValue)",
            "scheme: \(scheme)",
            "destination: \(destination.displayName)",
            "started_at: \(DateFormatting.iso8601(startedAt))",
            "ended_at: \(DateFormatting.iso8601(endedAt))",
            "exit_code: \(exitStatus)",
            "invocation: \(invocation)",
            "log_path: \(executionContext.logPath.path)",
            "result_bundle_path: \(executionContext.resultBundlePath.path)",
            "artifact_root: \(artifactRoot.path)",
            anomalies.isEmpty ? "anomalies: none" : "anomalies: \(anomalies.map(\.code).joined(separator: ", "))",
            "",
            "stdout_stderr:",
            combinedOutput.isEmpty ? "<empty>" : combinedOutput,
        ]
        try summaryLines.joined(separator: "\n").write(to: summaryPath, atomically: true, encoding: .utf8)

        let createdAt = DateFormatting.iso8601(endedAt)
        for name in stableInspectionNames(for: command) {
            let url = artifactRoot.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                entries.append(ArtifactIndexEntry(name: name, relativePath: name, kind: kind(for: url), createdAt: createdAt))
            } else if let anomaly = anomalies.first(where: { anomalyName($0) == name }) {
                entries.append(ArtifactIndexEntry(name: name, relativePath: name, kind: "missing", createdAt: createdAt, anomaly: anomaly))
            }
        }

        let knownNames = Set(entries.map(\.name))
        let additionalEntries = try fileManager.contentsOfDirectory(
            at: artifactRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { !knownNames.contains($0.lastPathComponent) }
        .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        .map { url in
            ArtifactIndexEntry(
                name: url.lastPathComponent,
                relativePath: url.lastPathComponent,
                kind: kind(for: url),
                createdAt: createdAt
            )
        }
        entries.append(contentsOf: additionalEntries)

        let index = ArtifactIndex(entries: entries, command: command, runID: executionContext.runID, timestamp: executionContext.timestamp, anomalies: anomalies)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexPath)

        try updateLatestLink(
            familyRoot: workspace.buildStateRoot.appendingPathComponent("artifacts/\(command.rawValue)", isDirectory: true),
            target: artifactRoot
        )

        let run = ArtifactRun(
            command: command,
            runID: executionContext.runID,
            timestamp: executionContext.timestamp,
            artifactRoot: artifactRoot,
            summaryPath: summaryPath,
            indexPath: indexPath
        )
        return ArtifactRecord(run: run, anomalies: anomalies)
    }

    public func recordSwiftPMExecution(
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

        let anomalies = extraAnomalies + [
            ArtifactAnomaly(code: "not_applicable_result_bundle", message: "SwiftPM-backed server runs do not produce an xcresult bundle.", phase: "swiftpm"),
            ArtifactAnomaly(code: "not_applicable_diagnostics", message: "SwiftPM-backed server runs do not export xcresult diagnostics.", phase: "swiftpm"),
            ArtifactAnomaly(code: "not_applicable_attachments", message: "SwiftPM-backed server runs do not export xcresult attachments.", phase: "swiftpm"),
            ArtifactAnomaly(code: "not_applicable_recording", message: "SwiftPM-backed server runs do not produce simulator recordings.", phase: "swiftpm"),
            ArtifactAnomaly(code: "not_applicable_screen_capture", message: "SwiftPM-backed server runs do not produce simulator screenshots.", phase: "swiftpm"),
            ArtifactAnomaly(code: "not_applicable_ui_tree", message: "SwiftPM-backed server runs do not produce simulator UI trees.", phase: "swiftpm"),
        ]

        let summaryLines = [
            "command: \(command.rawValue)",
            "product: \(product.rawValue)",
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
        try summaryLines.joined(separator: "\n").write(to: summaryPath, atomically: true, encoding: .utf8)

        let createdAt = DateFormatting.iso8601(endedAt)
        var entries = [ArtifactIndexEntry]()
        for name in stableInspectionNames(for: command) {
            let url = artifactRoot.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                entries.append(ArtifactIndexEntry(name: name, relativePath: name, kind: kind(for: url), createdAt: createdAt))
            } else if let anomaly = anomalies.first(where: { anomalyName($0) == name }) {
                entries.append(ArtifactIndexEntry(name: name, relativePath: name, kind: "missing", createdAt: createdAt, anomaly: anomaly))
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

        let index = ArtifactIndex(entries: entries, command: command, runID: executionContext.runID, timestamp: executionContext.timestamp, anomalies: anomalies)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexPath)

        try updateLatestLink(
            familyRoot: workspace.buildStateRoot.appendingPathComponent("artifacts/\(command.rawValue)", isDirectory: true),
            target: artifactRoot
        )

        let run = ArtifactRun(
            command: command,
            runID: executionContext.runID,
            timestamp: executionContext.timestamp,
            artifactRoot: artifactRoot,
            summaryPath: summaryPath,
            indexPath: indexPath
        )
        return ArtifactRecord(run: run, anomalies: anomalies)
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
            anomalies.isEmpty ? "anomalies: none" : "anomalies: \(anomalies.map(\.code).joined(separator: ", "))",
            "",
            summaryText,
        ]
        try summaryLines.joined(separator: "\n").write(to: summaryPath, atomically: true, encoding: .utf8)

        let createdAt = DateFormatting.iso8601(endedAt)
        var entries = [ArtifactIndexEntry]()
        for name in stableInspectionNames(for: .harness) {
            let url = artifactRoot.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                entries.append(ArtifactIndexEntry(name: name, relativePath: name, kind: kind(for: url), createdAt: createdAt))
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

        let index = ArtifactIndex(entries: entries, command: .harness, runID: executionContext.runID, timestamp: executionContext.timestamp, anomalies: anomalies)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexPath)

        try updateLatestLink(
            familyRoot: workspace.buildStateRoot.appendingPathComponent("artifacts/harness", isDirectory: true),
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

    public func resolveArtifacts(workspace: WorkspaceContext, request: ArtifactsCommandRequest) throws -> String {
        let familyRoot = workspace.buildStateRoot.appendingPathComponent("artifacts/\(request.command.rawValue)", isDirectory: true)
        let resolvedRoot: URL

        if let runID = request.runID {
            let candidates = try fileManager.contentsOfDirectory(at: familyRoot, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix("-\(runID)") }
            guard let match = candidates.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last else {
                throw SymphonyBuildError(code: "missing_artifact_run", message: "No artifact root was found for run id '\(runID)'.")
            }
            resolvedRoot = match
        } else {
            let latest = familyRoot.appendingPathComponent("latest")
            guard fileManager.fileExists(atPath: latest.path) else {
                throw SymphonyBuildError(code: "missing_artifacts", message: "No latest artifact root exists for the \(request.command.rawValue) command family.")
            }
            resolvedRoot = latest.resolvingSymlinksInPath()
        }

        let index = try loadArtifactIndexIfPresent(at: resolvedRoot.appendingPathComponent("index.json"))
        let indexedEntries = index?.entries ?? []
        let entryByName = Dictionary(uniqueKeysWithValues: indexedEntries.map { ($0.name, $0) })
        let stableNames = stableInspectionNames(for: request.command)
        let orderedNames = stableNames + indexedEntries.map(\.name).filter { !stableNames.contains($0) }
        let lines = [resolvedRoot.path] + orderedNames.map { name in
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

    private func prepareRoots(executionContext: ExecutionContext, command: BuildCommandFamily) throws {
        try fileManager.createDirectory(at: executionContext.derivedDataPath, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: executionContext.resultBundlePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: executionContext.logPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: executionContext.artifactRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: executionContext.runtimeRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: executionContext.artifactRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = command
    }

    private func exportXCResult(
        resultBundlePath: URL,
        summaryJSONPath: URL,
        diagnosticsPath: URL,
        attachmentsPath: URL,
        artifactRoot: URL
    ) throws -> [ArtifactAnomaly] {
        var anomalies = [ArtifactAnomaly]()

        let summary = try processRunner.run(
            command: "xcrun",
            arguments: ["xcresulttool", "get", "object", "--legacy", "--path", resultBundlePath.path, "--format", "json"],
            environment: [:],
            currentDirectory: nil
        )
        if summary.exitStatus == 0, !summary.stdout.isEmpty {
            try summary.stdout.write(to: summaryJSONPath, atomically: true, encoding: .utf8)
        } else {
            try "{}\n".write(to: summaryJSONPath, atomically: true, encoding: .utf8)
            anomalies.append(ArtifactAnomaly(code: "xcresult_summary_export_failed", message: summary.combinedOutput.isEmpty ? "Failed to export xcresult summary." : summary.combinedOutput, phase: "xcresult"))
        }

        let diagnostics = try processRunner.run(command: "xcrun", arguments: ["xcresulttool", "export", "diagnostics", "--path", resultBundlePath.path, "--output-path", diagnosticsPath.path], environment: [:], currentDirectory: nil)
        if diagnostics.exitStatus != 0 {
            anomalies.append(ArtifactAnomaly(code: "xcresult_diagnostics_export_failed", message: diagnostics.combinedOutput.isEmpty ? "Failed to export diagnostics." : diagnostics.combinedOutput, phase: "xcresult"))
        }

        let attachments = try processRunner.run(command: "xcrun", arguments: ["xcresulttool", "export", "attachments", "--path", resultBundlePath.path, "--output-path", attachmentsPath.path], environment: [:], currentDirectory: nil)
        if attachments.exitStatus != 0 {
            anomalies.append(ArtifactAnomaly(code: "xcresult_attachments_export_failed", message: attachments.combinedOutput.isEmpty ? "Failed to export attachments." : attachments.combinedOutput, phase: "xcresult"))
        }

        anomalies.append(contentsOf: createOptionalAliases(in: artifactRoot, diagnosticsPath: diagnosticsPath, attachmentsPath: attachmentsPath))
        return anomalies
    }

    private func createOptionalAliases(in artifactRoot: URL, diagnosticsPath: URL, attachmentsPath: URL) -> [ArtifactAnomaly] {
        var anomalies = [ArtifactAnomaly]()
        let candidates = recursiveFiles(in: [diagnosticsPath, attachmentsPath])

        let mappings: [(String, (URL) -> Bool, String)] = [
            ("recording.mp4", { $0.pathExtension.lowercased() == "mp4" }, "missing_recording"),
            ("screen.png", { $0.pathExtension.lowercased() == "png" }, "missing_screen_capture"),
            ("ui-tree.txt", {
                let name = $0.lastPathComponent.lowercased()
                return $0.pathExtension.lowercased() == "txt" && (name.contains("ui") || name.contains("tree") || name.contains("hierarchy"))
            }, "missing_ui_tree"),
        ]

        for (name, predicate, code) in mappings {
            let destination = artifactRoot.appendingPathComponent(name)
            if let source = candidates.first(where: predicate) {
                try? link(destination, to: source)
            } else {
                anomalies.append(ArtifactAnomaly(code: code, message: "No exported artifact was available for \(name).", phase: "xcresult"))
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
        try fileManager.createDirectory(at: familyRoot, withIntermediateDirectories: true)
        let latest = familyRoot.appendingPathComponent("latest")
        let temporary = familyRoot.appendingPathComponent(".latest-\(UUID().uuidString)")
        try fileManager.createSymbolicLink(at: temporary, withDestinationURL: target)
        if fileManager.fileExists(atPath: latest.path) {
            try fileManager.removeItem(at: latest)
        }
        try fileManager.moveItem(at: temporary, to: latest)
    }

    private func link(_ destination: URL, to source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
    }

    private func kind(for url: URL) -> String {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue ? "directory" : "file"
    }

    private func anomalyName(_ anomaly: ArtifactAnomaly) -> String? {
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

    private func stableInspectionNames(for command: BuildCommandFamily) -> [String] {
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
