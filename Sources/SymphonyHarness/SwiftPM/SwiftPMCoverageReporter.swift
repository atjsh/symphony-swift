import Foundation

public struct SwiftPMCoverageReporter {
  private let fileManager: FileManager

  public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

  public func renderedCoveragePathCommandLine() -> String {
    ShellQuoting.render(command: "swift", arguments: ["test", "--show-code-coverage-path"])
  }

  public func exportServerCoverage(
    coverageJSONPath: URL,
    projectRoot: URL,
    artifactRoot: URL,
    showFiles: Bool
  ) throws -> CoverageArtifacts {
    guard fileManager.fileExists(atPath: coverageJSONPath.path) else {
      throw SymphonyHarnessError(
        code: "missing_swiftpm_coverage_json",
        message: "SwiftPM did not produce a coverage JSON file at \(coverageJSONPath.path)."
      )
    }

    let data = try Data(contentsOf: coverageJSONPath)
    let export: RawPackageCoverageExport
    do {
      export = try JSONDecoder().decode(RawPackageCoverageExport.self, from: data)
    } catch {
      throw SymphonyHarnessError(
        code: "swiftpm_coverage_decode_failed",
        message: "SwiftPM coverage JSON could not be decoded.")
    }

    let resolvedRoot = projectRoot.resolvingSymlinksInPath()
    let targetRoots = [
      (
        targetName: "SymphonyServerCore",
        rootPath: resolvedRoot.appendingPathComponent(
          "Sources/SymphonyServerCore", isDirectory: true
        ).path + "/"
      ),
      (
        targetName: "SymphonyServer",
        rootPath: resolvedRoot.appendingPathComponent("Sources/SymphonyServer", isDirectory: true)
          .path + "/"
      ),
      (
        targetName: "SymphonyServer",
        rootPath: resolvedRoot.appendingPathComponent("Sources/SymphonyServerCLI", isDirectory: true)
          .path + "/"
      ),
    ]

    let orderedTargetNames = targetRoots.reduce(into: [String]()) { names, targetRoot in
      if !names.contains(targetRoot.targetName) {
        names.append(targetRoot.targetName)
      }
    }

    var groupedFiles = [String: [CoverageFileReport]]()
    for targetName in orderedTargetNames {
      groupedFiles[targetName] = []
    }

    for file in export.data.flatMap(\.files) {
      guard let targetRoot = targetRoots.first(where: { file.filename.hasPrefix($0.rootPath) }) else {
        continue
      }

      let executableLines = file.summary.lines.count
      guard executableLines > 0 else {
        continue
      }

      let relativePath = String(file.filename.dropFirst(resolvedRoot.path.count + 1))
      let coveredLines = file.summary.lines.covered
      var targetFiles = groupedFiles[targetRoot.targetName]!
      targetFiles.append(
        CoverageFileReport(
          name: URL(fileURLWithPath: relativePath).lastPathComponent,
          path: relativePath,
          coveredLines: coveredLines,
          executableLines: executableLines,
          lineCoverage: CoverageReporter.normalizedCoverage(
            coveredLines: coveredLines, executableLines: executableLines)
        )
      )
      groupedFiles[targetRoot.targetName] = targetFiles
    }

    let targets = orderedTargetNames.compactMap { targetName -> CoverageTargetReport? in
      let files = groupedFiles[targetName]!.sorted { lhs, rhs in
        return lhs.path < rhs.path
      }
      guard !files.isEmpty else {
        return nil
      }

      let coveredLines = files.reduce(0) { $0 + $1.coveredLines }
      let executableLines = files.reduce(0) { $0 + $1.executableLines }
      return CoverageTargetReport(
        name: targetName,
        buildProductPath: nil,
        coveredLines: coveredLines,
        executableLines: executableLines,
        lineCoverage: CoverageReporter.normalizedCoverage(
          coveredLines: coveredLines, executableLines: executableLines),
        files: showFiles ? files : nil
      )
    }

    guard !targets.isEmpty else {
      throw SymphonyHarnessError(
        code: "swiftpm_coverage_sources_missing",
        message:
          "SwiftPM coverage did not include any first-party server files under Sources/SymphonyServerCore, Sources/SymphonyServer, or Sources/SymphonyServerCLI."
      )
    }

    let coveredLines = targets.reduce(0) { $0 + $1.coveredLines }
    let executableLines = targets.reduce(0) { $0 + $1.executableLines }
    let report = CoverageReport(
      coveredLines: coveredLines,
      executableLines: executableLines,
      lineCoverage: CoverageReporter.normalizedCoverage(
        coveredLines: coveredLines, executableLines: executableLines),
      includeTestTargets: false,
      excludedTargets: ["SymphonyServerCoreTests", "SymphonyServerTests", "SymphonyServerCLITests"],
      targets: targets
    )

    try fileManager.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let jsonData = try encoder.encode(report)
    let jsonOutput = String(decoding: jsonData, as: UTF8.self)
    let textOutput = CoverageReporter().renderHuman(report: report)
    let jsonPath = artifactRoot.appendingPathComponent("coverage.json")
    let textPath = artifactRoot.appendingPathComponent("coverage.txt")
    try (jsonOutput + "\n").write(to: jsonPath, atomically: true, encoding: .utf8)
    try (textOutput + "\n").write(to: textPath, atomically: true, encoding: .utf8)

    return CoverageArtifacts(
      report: report,
      jsonPath: jsonPath,
      textPath: textPath,
      jsonOutput: jsonOutput,
      textOutput: textOutput
    )
  }
}

private struct RawPackageCoverageExport: Decodable {
  let data: [RawPackageCoverageChunk]
}

private struct RawPackageCoverageChunk: Decodable {
  let files: [RawPackageCoverageFile]
}

private struct RawPackageCoverageFile: Decodable {
  let filename: String
  let summary: RawPackageCoverageSummary
}

private struct RawPackageCoverageSummary: Decodable {
  let lines: RawPackageCoverageLines
}

private struct RawPackageCoverageLines: Decodable {
  let count: Int
  let covered: Int
}
