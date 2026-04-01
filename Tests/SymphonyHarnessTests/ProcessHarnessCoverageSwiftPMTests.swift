import Foundation
import Testing

@testable import SymphonyHarness

@Test func swiftPMCoverageReporterCoversFailuresAndGroupedOutput() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServerCore"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServer"),
      withIntermediateDirectories: true)

    let reporter = SwiftPMCoverageReporter()
    let missingPath = directory.appendingPathComponent("missing-swiftpm.json")
    #expect(reporter.renderedCoveragePathCommandLine() == "swift test --show-code-coverage-path")

    do {
      _ = try reporter.exportServerCoverage(
        coverageJSONPath: missingPath,
        projectRoot: repoRoot,
        artifactRoot: directory.appendingPathComponent("artifacts-missing", isDirectory: true),
        showFiles: false
      )
      Issue.record("Expected missing SwiftPM coverage JSON to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_swiftpm_coverage_json")
    }

    let invalidPath = directory.appendingPathComponent("invalid-swiftpm.json")
    try "not json".write(to: invalidPath, atomically: true, encoding: .utf8)
    do {
      _ = try reporter.exportServerCoverage(
        coverageJSONPath: invalidPath,
        projectRoot: repoRoot,
        artifactRoot: directory.appendingPathComponent("artifacts-invalid", isDirectory: true),
        showFiles: false
      )
      Issue.record("Expected undecodable SwiftPM coverage JSON to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "swiftpm_coverage_decode_failed")
    }

    let noSourcesPath = directory.appendingPathComponent("swiftpm-no-sources.json")
    try #"""
    {"data":[{"files":[{"filename":"__REPO__/Tests/SymphonyServerTests/Foo.swift","summary":{"lines":{"count":10,"covered":10}}},{"filename":"__REPO__/Sources/SymphonyServerCore/Zero.swift","summary":{"lines":{"count":0,"covered":0}}}]}]}
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: noSourcesPath, atomically: true, encoding: .utf8)
    do {
      _ = try reporter.exportServerCoverage(
        coverageJSONPath: noSourcesPath,
        projectRoot: repoRoot,
        artifactRoot: directory.appendingPathComponent("artifacts-no-sources", isDirectory: true),
        showFiles: false
      )
      Issue.record("Expected missing first-party SwiftPM server coverage to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "swiftpm_coverage_sources_missing")
    }

    let successPath = directory.appendingPathComponent("swiftpm-success.json")
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyServerCore/Zeta.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyServerCore/Alpha.swift", "summary": { "lines": { "count": 3, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyServerCLI/main.swift", "summary": { "lines": { "count": 4, "covered": 3 } } },
            { "filename": "__REPO__/Sources/SymphonyServer/Zero.swift", "summary": { "lines": { "count": 0, "covered": 0 } } },
            { "filename": "__REPO__/Tests/SymphonyServerTests/Foo.swift", "summary": { "lines": { "count": 10, "covered": 10 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: successPath, atomically: true, encoding: .utf8)

    let artifactRoot = directory.appendingPathComponent("artifacts-success", isDirectory: true)
    let artifacts = try reporter.exportServerCoverage(
      coverageJSONPath: successPath,
      projectRoot: repoRoot,
      artifactRoot: artifactRoot,
      showFiles: true
    )

    #expect(artifacts.report.coveredLines == 7)
    #expect(artifacts.report.executableLines == 9)
    #expect(artifacts.report.excludedTargets == [
      "SymphonyServerCoreTests",
      "SymphonyServerTests",
      "SymphonyServerCLITests",
    ])
    #expect(artifacts.report.targets.map(\.name) == ["SymphonyServerCore", "SymphonyServer"])
    #expect(
      artifacts.report.targets[0].files?.map(\.path) == [
        "Sources/SymphonyServerCore/Alpha.swift",
        "Sources/SymphonyServerCore/Zeta.swift",
      ])
    #expect(artifacts.report.targets[1].files?.map(\.path) == ["Sources/SymphonyServerCLI/main.swift"])
    #expect(artifacts.textOutput.contains("target SymphonyServerCore 80.00% (4/5)"))
    #expect(artifacts.textOutput.contains("target SymphonyServer 75.00% (3/4)"))
    #expect(FileManager.default.fileExists(atPath: artifacts.jsonPath.path))
    #expect(FileManager.default.fileExists(atPath: artifacts.textPath.path))

    let hiddenFilesArtifacts = try reporter.exportServerCoverage(
      coverageJSONPath: successPath,
      projectRoot: repoRoot,
      artifactRoot: directory.appendingPathComponent("artifacts-hidden-files", isDirectory: true),
      showFiles: false
    )
    #expect(hiddenFilesArtifacts.report.targets.allSatisfy { $0.files == nil })
  }
}

@Test func swiftPMCoverageReporterHandlesDuplicatePathsInStableSortBranch() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServerCore"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServer"),
      withIntermediateDirectories: true)

    let coveragePath = directory.appendingPathComponent("swiftpm-duplicate-paths.json")
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyServerCore/Alpha.swift", "summary": { "lines": { "count": 1, "covered": 1 } } },
            { "filename": "__REPO__/Sources/SymphonyServerCore/Alpha.swift", "summary": { "lines": { "count": 1, "covered": 0 } } },
            { "filename": "__REPO__/Sources/SymphonyServerCLI/main.swift", "summary": { "lines": { "count": 1, "covered": 1 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let artifacts = try SwiftPMCoverageReporter().exportServerCoverage(
      coverageJSONPath: coveragePath,
      projectRoot: repoRoot,
      artifactRoot: directory.appendingPathComponent(
        "artifacts-duplicate-paths", isDirectory: true),
      showFiles: true
    )

    #expect(
      artifacts.report.targets[0].files?.map(\.path) == [
        "Sources/SymphonyServerCore/Alpha.swift",
        "Sources/SymphonyServerCore/Alpha.swift",
      ])
  }
}

@Test func swiftPMCoverageReporterAllowsSingleCoveredTargetWhenServerFilesAreMissing() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServerCore"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServer"),
      withIntermediateDirectories: true)

    let coveragePath = directory.appendingPathComponent("swiftpm-runtime-only.json")
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyServerCore/Orchestrator.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Tests/SymphonyServerTests/Foo.swift", "summary": { "lines": { "count": 10, "covered": 10 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let artifacts = try SwiftPMCoverageReporter().exportServerCoverage(
      coverageJSONPath: coveragePath,
      projectRoot: repoRoot,
      artifactRoot: directory.appendingPathComponent("artifacts-runtime-only", isDirectory: true),
      showFiles: false
    )

    #expect(artifacts.report.targets.map(\.name) == ["SymphonyServerCore"])
    #expect(artifacts.report.targets[0].files == nil)
  }
}

@Test func swiftPMCoverageScopeMapsCanonicalSwiftPMSubjectsToOwnedRoots() {
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonyShared") == .shared)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonySharedTests") == .shared)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonyServerCore") == .serverCore)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonyServerCoreTests") == .serverCore)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonyServer") == .server)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonyServerTests") == .server)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonyServerCLI") == .serverCLI)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonyServerCLITests") == .serverCLI)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonyHarness") == .harness)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonyHarnessTests") == .harness)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonyHarnessCLI") == .harnessCLI)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonyHarnessCLITests") == .harnessCLI)
  #expect(SwiftPMCoverageScope.subjectOwned(for: "SymphonySwiftUIApp") == nil)
}

@Test func swiftPMCoverageReporterExportsHarnessOwnedSourcesOnly() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyHarness"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServer"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyHarnessCLI"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/harness"),
      withIntermediateDirectories: true)

    let coveragePath = directory.appendingPathComponent("swiftpm-harness-scope.json")
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyHarness/CoverageInspection.swift", "summary": { "lines": { "count": 12, "covered": 9 } } },
            { "filename": "__REPO__/Sources/SymphonyHarness/SymphonyHarnessTool.swift", "summary": { "lines": { "count": 6, "covered": 3 } } },
            { "filename": "__REPO__/Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift", "summary": { "lines": { "count": 5, "covered": 5 } } },
            { "filename": "__REPO__/Sources/harness/main.swift", "summary": { "lines": { "count": 3, "covered": 3 } } },
            { "filename": "__REPO__/Sources/SymphonyServer/ProviderAdapter.swift", "summary": { "lines": { "count": 4, "covered": 4 } } },
            { "filename": "__REPO__/Tests/SymphonyHarnessTests/Foo.swift", "summary": { "lines": { "count": 20, "covered": 20 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let artifacts = try SwiftPMCoverageReporter().exportCoverage(
      coverageJSONPath: coveragePath,
      projectRoot: repoRoot,
      artifactRoot: directory.appendingPathComponent("artifacts-harness", isDirectory: true),
      scope: .harness,
      showFiles: true
    )

    #expect(artifacts.report.targets.map(\.name) == ["SymphonyHarness"])
    #expect(artifacts.report.coveredLines == 12)
    #expect(artifacts.report.executableLines == 18)
    #expect(artifacts.report.excludedTargets == ["SymphonyHarnessTests"])
    #expect(
      artifacts.report.targets[0].files?.map(\.path) == [
        "Sources/SymphonyHarness/CoverageInspection.swift",
        "Sources/SymphonyHarness/SymphonyHarnessTool.swift",
      ])
    #expect(!artifacts.jsonOutput.contains("Sources/SymphonyServer/ProviderAdapter.swift"))
    #expect(!artifacts.jsonOutput.contains("Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift"))
  }
}

@Test func swiftPMCoverageReporterExportsHarnessCLIOwnedSourcesOnly() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyHarnessCLI"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/harness"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyHarness"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServer"),
      withIntermediateDirectories: true)

    let coveragePath = directory.appendingPathComponent("swiftpm-harness-cli-scope.json")
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift", "summary": { "lines": { "count": 10, "covered": 8 } } },
            { "filename": "__REPO__/Sources/harness/main.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyHarness/SymphonyHarnessTool.swift", "summary": { "lines": { "count": 4, "covered": 4 } } },
            { "filename": "__REPO__/Sources/SymphonyServer/ProviderAdapter.swift", "summary": { "lines": { "count": 6, "covered": 6 } } },
            { "filename": "__REPO__/Tests/SymphonyHarnessCLITests/Foo.swift", "summary": { "lines": { "count": 20, "covered": 20 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let artifacts = try SwiftPMCoverageReporter().exportCoverage(
      coverageJSONPath: coveragePath,
      projectRoot: repoRoot,
      artifactRoot: directory.appendingPathComponent("artifacts-harness-cli", isDirectory: true),
      scope: .harnessCLI,
      showFiles: true
    )

    #expect(artifacts.report.targets.map(\.name) == ["SymphonyHarnessCLI"])
    #expect(artifacts.report.coveredLines == 10)
    #expect(artifacts.report.executableLines == 12)
    #expect(artifacts.report.excludedTargets == ["SymphonyHarnessCLITests"])
    #expect(
      artifacts.report.targets[0].files?.map(\.path) == [
        "Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift",
        "Sources/harness/main.swift",
      ])
    #expect(!artifacts.jsonOutput.contains("Sources/SymphonyServer/ProviderAdapter.swift"))
    #expect(!artifacts.jsonOutput.contains("Sources/SymphonyHarness/SymphonyHarnessTool.swift"))
  }
}

@Test func swiftPMCoverageReporterExportsAllOwnedSwiftPMScopeRoots() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    for path in [
      "Sources/SymphonyShared",
      "Sources/SymphonyServerCore",
      "Sources/SymphonyServer",
      "Sources/SymphonyServerCLI",
      "Sources/SymphonyHarness",
      "Sources/SymphonyHarnessCLI",
      "Sources/harness",
    ] {
      try FileManager.default.createDirectory(
        at: repoRoot.appendingPathComponent(path),
        withIntermediateDirectories: true
      )
    }

    let coveragePath = directory.appendingPathComponent("swiftpm-owned-scopes.json")
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyShared/SymphonyShared.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyServerCore/Orchestrator.swift", "summary": { "lines": { "count": 4, "covered": 3 } } },
            { "filename": "__REPO__/Sources/SymphonyServer/ProviderAdapter.swift", "summary": { "lines": { "count": 6, "covered": 4 } } },
            { "filename": "__REPO__/Sources/SymphonyServerCLI/main.swift", "summary": { "lines": { "count": 3, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyHarness/SymphonyHarnessTool.swift", "summary": { "lines": { "count": 5, "covered": 4 } } },
            { "filename": "__REPO__/Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift", "summary": { "lines": { "count": 7, "covered": 6 } } },
            { "filename": "__REPO__/Sources/harness/main.swift", "summary": { "lines": { "count": 2, "covered": 2 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let reporter = SwiftPMCoverageReporter()
    let scopes: [(SwiftPMCoverageScope, String, [String])] = [
      (.shared, "SymphonyShared", ["SymphonySharedTests"]),
      (.serverCore, "SymphonyServerCore", ["SymphonyServerCoreTests"]),
      (.server, "SymphonyServer", ["SymphonyServerTests"]),
      (.serverCLI, "SymphonyServerCLI", ["SymphonyServerCLITests"]),
      (.harness, "SymphonyHarness", ["SymphonyHarnessTests"]),
      (.harnessCLI, "SymphonyHarnessCLI", ["SymphonyHarnessCLITests"]),
    ]

    for (scope, targetName, excludedTargets) in scopes {
      let artifacts = try reporter.exportCoverage(
        coverageJSONPath: coveragePath,
        projectRoot: repoRoot,
        artifactRoot: directory.appendingPathComponent("artifacts-\(targetName)", isDirectory: true),
        scope: scope,
        showFiles: true
      )

      #expect(artifacts.report.targets.map(\.name) == [targetName])
      #expect(artifacts.report.excludedTargets == excludedTargets)
    }
  }
}

@Test func swiftPMCoverageReporterUsesScopeDescriptionsInMissingSourceErrors() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    let coveragePath = directory.appendingPathComponent("swiftpm-empty-scopes.json")
    try #"{"data":[{"files":[]}]}"#.write(to: coveragePath, atomically: true, encoding: .utf8)

    let expectations: [(SwiftPMCoverageScope, String)] = [
      (.shared, "SymphonyShared"),
      (.serverCore, "SymphonyServerCore"),
      (.server, "SymphonyServer"),
      (.serverCLI, "SymphonyServerCLI"),
      (.harness, "SymphonyHarness"),
      (.harnessCLI, "SymphonyHarnessCLI"),
    ]

    for (scope, subjectDescription) in expectations {
      do {
        _ = try SwiftPMCoverageReporter().exportCoverage(
          coverageJSONPath: coveragePath,
          projectRoot: repoRoot,
          artifactRoot: directory.appendingPathComponent("missing-\(subjectDescription)", isDirectory: true),
          scope: scope,
          showFiles: true
        )
        Issue.record("Expected missing \(subjectDescription) sources to fail.")
      } catch let error as SymphonyHarnessError {
        #expect(error.code == "swiftpm_coverage_sources_missing")
        #expect(error.message.contains(subjectDescription))
      }
    }
  }
}

