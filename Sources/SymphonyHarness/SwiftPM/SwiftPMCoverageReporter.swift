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
    try exportCoverage(
      coverageJSONPath: coverageJSONPath,
      projectRoot: projectRoot,
      artifactRoot: artifactRoot,
      scope: .serverAggregate,
      showFiles: showFiles
    )
  }

  func exportCoverage(
    coverageJSONPath: URL,
    projectRoot: URL,
    artifactRoot: URL,
    scope: SwiftPMCoverageScope,
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
    let targetRoots = scope.targetScopes.map { targetScope in
      (
        targetName: targetScope.targetName,
        rootPaths: targetScope.relativeRoots.map {
          resolvedRoot.appendingPathComponent($0, isDirectory: true).path + "/"
        }
      )
    }

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
      guard
        let targetRoot = targetRoots.first(where: { targetRoot in
          targetRoot.rootPaths.contains { file.filename.hasPrefix($0) }
        })
      else { continue }

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
          "SwiftPM coverage did not include any first-party \(scope.subjectDescription) files under \(scope.relativeRootsDescription)."
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
      excludedTargets: scope.excludedTargets,
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

enum SwiftPMCoverageScope: String, CaseIterable, Sendable {
  case serverAggregate
  case shared
  case serverCore
  case server
  case serverCLI
  case harness
  case harnessCLI

  static func subjectOwned(for subjectName: String) -> Self? {
    switch subjectName {
    case "SymphonyShared", "SymphonySharedTests":
      return .shared
    case "SymphonyServerCore", "SymphonyServerCoreTests":
      return .serverCore
    case "SymphonyServer", "SymphonyServerTests":
      return .server
    case "SymphonyServerCLI", "SymphonyServerCLITests":
      return .serverCLI
    case "SymphonyHarness", "SymphonyHarnessTests":
      return .harness
    case "SymphonyHarnessCLI", "SymphonyHarnessCLITests":
      return .harnessCLI
    default:
      return nil
    }
  }

  fileprivate var targetScopes: [SwiftPMCoverageTargetScope] {
    switch self {
    case .serverAggregate:
      return [
        SwiftPMCoverageTargetScope(
          targetName: "SymphonyServerCore",
          relativeRoots: ["Sources/SymphonyServerCore"]
        ),
        SwiftPMCoverageTargetScope(
          targetName: "SymphonyServer",
          relativeRoots: ["Sources/SymphonyServer", "Sources/SymphonyServerCLI"]
        ),
      ]
    case .shared:
      return [SwiftPMCoverageTargetScope(targetName: "SymphonyShared", relativeRoots: ["Sources/SymphonyShared"])]
    case .serverCore:
      return [SwiftPMCoverageTargetScope(targetName: "SymphonyServerCore", relativeRoots: ["Sources/SymphonyServerCore"])]
    case .server:
      return [SwiftPMCoverageTargetScope(targetName: "SymphonyServer", relativeRoots: ["Sources/SymphonyServer"])]
    case .serverCLI:
      return [SwiftPMCoverageTargetScope(targetName: "SymphonyServerCLI", relativeRoots: ["Sources/SymphonyServerCLI"])]
    case .harness:
      return [SwiftPMCoverageTargetScope(targetName: "SymphonyHarness", relativeRoots: ["Sources/SymphonyHarness"])]
    case .harnessCLI:
      return [
        SwiftPMCoverageTargetScope(
          targetName: "SymphonyHarnessCLI",
          relativeRoots: ["Sources/SymphonyHarnessCLI", "Sources/harness"]
        )
      ]
    }
  }

  fileprivate var excludedTargets: [String] {
    switch self {
    case .serverAggregate:
      return ["SymphonyServerCoreTests", "SymphonyServerTests", "SymphonyServerCLITests"]
    case .shared:
      return ["SymphonySharedTests"]
    case .serverCore:
      return ["SymphonyServerCoreTests"]
    case .server:
      return ["SymphonyServerTests"]
    case .serverCLI:
      return ["SymphonyServerCLITests"]
    case .harness:
      return ["SymphonyHarnessTests"]
    case .harnessCLI:
      return ["SymphonyHarnessCLITests"]
    }
  }

  fileprivate var subjectDescription: String {
    switch self {
    case .serverAggregate:
      return "server"
    case .shared:
      return "SymphonyShared"
    case .serverCore:
      return "SymphonyServerCore"
    case .server:
      return "SymphonyServer"
    case .serverCLI:
      return "SymphonyServerCLI"
    case .harness:
      return "SymphonyHarness"
    case .harnessCLI:
      return "SymphonyHarnessCLI"
    }
  }

  fileprivate var relativeRootsDescription: String {
    targetScopes.flatMap(\.relativeRoots).joined(separator: ", ")
  }
}

fileprivate struct SwiftPMCoverageTargetScope: Sendable {
  let targetName: String
  let relativeRoots: [String]
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
