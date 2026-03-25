import Foundation
import Testing

@testable import SymphonyBuildCore

@Test func packageCoverageReporterCoversFailureModesAndViolations() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)

    let missingPath = directory.appendingPathComponent("missing.json")
    do {
      _ = try PackageCoverageReporter().loadReport(at: missingPath, projectRoot: repoRoot)
      Issue.record("Expected missing coverage files to fail.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "missing_package_coverage_json")
    }

    let invalidJSONPath = directory.appendingPathComponent("invalid.json")
    try "not json".write(to: invalidJSONPath, atomically: true, encoding: .utf8)
    do {
      _ = try PackageCoverageReporter().loadReport(at: invalidJSONPath, projectRoot: repoRoot)
      Issue.record("Expected undecodable coverage exports to fail.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "package_coverage_decode_failed")
    }

    let emptySourcesPath = directory.appendingPathComponent("empty.json")
    let emptySourcesJSON = #"""
      {"data":[{"files":[{"filename":"__REPO__/Tests/FooTests.swift","summary":{"lines":{"count":10,"covered":10}}},{"filename":"__REPO__/Sources/Zero.swift","summary":{"lines":{"count":0,"covered":0}}}]}]}
      """#.replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    try emptySourcesJSON.write(to: emptySourcesPath, atomically: true, encoding: .utf8)
    do {
      _ = try PackageCoverageReporter().loadReport(at: emptySourcesPath, projectRoot: repoRoot)
      Issue.record("Expected missing first-party source coverage to fail.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "package_coverage_sources_missing")
    }

    let reporter = PackageCoverageReporter()
    let harness = HarnessReport(
      minimumCoveragePercent: 100,
      testsInvocation: "swift test",
      coveragePathInvocation: "swift test --show-code-coverage-path",
      packageCoverage: PackageCoverageReport(
        scope: "scope",
        coveredLines: 2,
        executableLines: 4,
        lineCoverage: 0.5,
        coverageJSONPath: "/tmp/coverage.json",
        files: [
          PackageCoverageFileReport(
            path: "Sources/Low.swift", coveredLines: 1, executableLines: 2, lineCoverage: 0.5),
          PackageCoverageFileReport(
            path: "Sources/High.swift", coveredLines: 1, executableLines: 2, lineCoverage: 0.5),
        ]
      ),
      clientCoverageInvocation: "client",
      clientCoverage: CoverageReport(
        coveredLines: 1,
        executableLines: 2,
        lineCoverage: 0.5,
        includeTestTargets: false,
        excludedTargets: [],
        targets: [
          CoverageTargetReport(
            name: "Symphony.app",
            buildProductPath: nil,
            coveredLines: 1,
            executableLines: 2,
            lineCoverage: 0.5,
            files: [
              CoverageFileReport(
                name: "ContentView.swift", path: "/tmp/ContentView.swift", coveredLines: 1,
                executableLines: 2, lineCoverage: 0.5)
            ]
          )
        ]
      ),
      clientCoverageSkipReason: nil,
      serverCoverageInvocation: "server",
      serverCoverage: CoverageReport(
        coveredLines: 2,
        executableLines: 2,
        lineCoverage: 1,
        includeTestTargets: false,
        excludedTargets: [],
        targets: []
      ),
      packageFileViolations: [
        HarnessCoverageViolation(
          suite: "package", kind: "file", name: "Sources/Low.swift", coveredLines: 1,
          executableLines: 2, lineCoverage: 0.5)
      ],
      clientTargetViolations: [
        HarnessCoverageViolation(
          suite: "client", kind: "target", name: "Symphony.app", coveredLines: 1,
          executableLines: 2, lineCoverage: 0.5)
      ],
      clientFileViolations: [
        HarnessCoverageViolation(
          suite: "client", kind: "file", name: "/tmp/ContentView.swift", coveredLines: 1,
          executableLines: 2, lineCoverage: 0.5)
      ],
      serverTargetViolations: [],
      serverFileViolations: []
    )

    let human = reporter.renderHuman(report: harness)
    #expect(human.contains("violations"))
    #expect(human.contains("client file /tmp/ContentView.swift 50.00% (1/2)"))
    #expect(
      reporter.makePackageFileViolations(report: harness.packageCoverage, minimumLineCoverage: 1)
        .count == 2)
    let clientCoverage = try #require(harness.clientCoverage)
    #expect(
      reporter.makeTargetViolations(report: clientCoverage, suite: "client", minimumLineCoverage: 1)
        .count == 1)
    #expect(
      reporter.makeFileViolations(report: clientCoverage, suite: "client", minimumLineCoverage: 1)
        .count == 1)
    #expect(
      reporter.makeFileViolations(
        report: harness.serverCoverage, suite: "server", minimumLineCoverage: 1
      ).isEmpty)
    #expect(PackageCoverageReporter.normalizedCoverage(coveredLines: 0, executableLines: 0) == 0)

    let skippedHuman = reporter.renderHuman(
      report: HarnessReport(
        minimumCoveragePercent: 100,
        testsInvocation: "swift test",
        coveragePathInvocation: "swift test --show-code-coverage-path",
        packageCoverage: harness.packageCoverage,
        clientCoverageInvocation: nil,
        clientCoverage: nil,
        clientCoverageSkipReason:
          "not supported because the current environment has no Xcode available; Editing those sources is not encouraged",
        serverCoverageInvocation: "server",
        serverCoverage: harness.serverCoverage,
        packageFileViolations: [],
        clientTargetViolations: [],
        clientFileViolations: [],
        serverTargetViolations: [],
        serverFileViolations: []
      )
    )
    #expect(
      skippedHuman.contains(
        "client coverage skipped: not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
      ))
  }
}

@Test func packageCoverageReporterSortsFilesAndSkipsFullyCoveredFileViolations() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let coveragePath = directory.appendingPathComponent("package-coverage.json")
    let json = #"""
      {
        "data": [
          {
            "files": [
              { "filename": "__REPO__/Sources/Beta.swift", "summary": { "lines": { "count": 10, "covered": 5 } } },
              { "filename": "__REPO__/Sources/Low.swift", "summary": { "lines": { "count": 10, "covered": 1 } } },
              { "filename": "__REPO__/Sources/Alpha.swift", "summary": { "lines": { "count": 10, "covered": 5 } } }
            ]
          }
        ]
      }
      """#
    try json.replacingOccurrences(of: "__REPO__", with: repoRoot.path).write(
      to: coveragePath, atomically: true, encoding: .utf8)

    let reporter = PackageCoverageReporter()
    let report = try reporter.loadReport(at: coveragePath, projectRoot: repoRoot)
    #expect(
      report.files.map(\.path) == [
        "Sources/Low.swift", "Sources/Alpha.swift", "Sources/Beta.swift",
      ])

    let violations = reporter.makeFileViolations(
      report: CoverageReport(
        coveredLines: 3,
        executableLines: 4,
        lineCoverage: 0.75,
        includeTestTargets: false,
        excludedTargets: [],
        targets: [
          CoverageTargetReport(
            name: "Symphony.app",
            buildProductPath: nil,
            coveredLines: 3,
            executableLines: 4,
            lineCoverage: 0.75,
            files: [
              CoverageFileReport(
                name: "Covered.swift", path: "/tmp/Covered.swift", coveredLines: 2,
                executableLines: 2, lineCoverage: 1),
              CoverageFileReport(
                name: "Partial.swift", path: "/tmp/Partial.swift", coveredLines: 1,
                executableLines: 2, lineCoverage: 0.5),
            ]
          )
        ]
      ),
      suite: "client",
      minimumLineCoverage: 1
    )
    #expect(violations.map(\.name) == ["/tmp/Partial.swift"])
  }
}

@Test func packageCoverageReporterSkipsZeroExecutableTargetViolations() {
  let reporter = PackageCoverageReporter()
  let report = CoverageReport(
    coveredLines: 10,
    executableLines: 10,
    lineCoverage: 1,
    includeTestTargets: false,
    excludedTargets: [],
    targets: [
      CoverageTargetReport(
        name: "Symphony.app", buildProductPath: nil, coveredLines: 10, executableLines: 10,
        lineCoverage: 1, files: nil),
      CoverageTargetReport(
        name: "SymphonyRuntime", buildProductPath: nil, coveredLines: 0, executableLines: 0,
        lineCoverage: 0, files: nil),
    ]
  )

  #expect(
    reporter.makeTargetViolations(report: report, suite: "client", minimumLineCoverage: 1).map(
      \.name) == [])
}

@Test func coverageReporterCoversErrorModesAndTestTargetInclusion() throws {
  try withTemporaryDirectory { directory in
    let resultBundlePath = directory.appendingPathComponent("result.xcresult")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)

    do {
      _ = try CoverageReporter(
        processRunner: StubProcessRunner(results: [
          "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.failure(
            "xccov broke")
        ])
      ).export(
        resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, product: .client,
        includeTestTargets: false, showFiles: false)
      Issue.record("Expected xccov failures to surface.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "coverage_export_failed")
    }

    do {
      _ = try CoverageReporter(
        processRunner: StubProcessRunner(results: [
          "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(
            "not json")
        ])
      ).export(
        resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, product: .client,
        includeTestTargets: false, showFiles: false)
      Issue.record("Expected invalid xccov JSON to fail.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "coverage_report_decode_failed")
    }

    let onlyTestsJSON = #"""
      {"targets":[{"buildProductPath":"/tmp/FooTests.xctest/Contents/MacOS/FooTests","coveredLines":2,"executableLines":2,"files":[{"coveredLines":2,"executableLines":2,"name":"FooTests.swift","path":"/tmp/FooTests.swift"}],"name":"FooTests.xctest"}]}
      """#
    do {
      _ = try CoverageReporter(
        processRunner: StubProcessRunner(results: [
          "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(
            onlyTestsJSON)
        ])
      ).export(
        resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, product: .client,
        includeTestTargets: false, showFiles: false)
      Issue.record("Expected missing non-test targets to fail.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "coverage_targets_missing")
      #expect(error.message.contains("non-test"))
    }

    let included = try CoverageReporter(
      processRunner: StubProcessRunner(results: [
        "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(
          onlyTestsJSON)
      ])
    ).export(
      resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, product: .client,
      includeTestTargets: true, showFiles: false)
    #expect(included.report.includeTestTargets)
    #expect(included.report.excludedTargets.isEmpty)
    #expect(included.textOutput.contains("scope including_test_targets"))
    #expect(CoverageReporter.normalizedCoverage(coveredLines: 0, executableLines: 0) == 0)

    let noTargetsJSON = #"{"targets":[]}"#
    do {
      _ = try CoverageReporter(
        processRunner: StubProcessRunner(results: [
          "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(
            noTargetsJSON)
        ])
      ).export(
        resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, product: .client,
        includeTestTargets: true, showFiles: false)
      Issue.record("Expected missing targets to fail even when test targets are included.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "coverage_targets_missing")
      #expect(error.message == "The xcresult bundle did not contain any coverage targets.")
    }
  }
}

@Test func coverageReporterDefaultInitializerAndArtifactsValueRemainUsable() {
  let reporter = CoverageReporter()
  let resultBundlePath = URL(fileURLWithPath: "/tmp/Result Bundle.xcresult")
  #expect(
    reporter.renderedCommandLine(resultBundlePath: resultBundlePath)
      == "xcrun xccov view --report --json '/tmp/Result Bundle.xcresult'")

  let report = CoverageReport(
    coveredLines: 1,
    executableLines: 1,
    lineCoverage: 1,
    includeTestTargets: false,
    excludedTargets: [],
    targets: []
  )
  let artifacts = CoverageArtifacts(
    report: report,
    jsonPath: URL(fileURLWithPath: "/tmp/coverage.json"),
    textPath: URL(fileURLWithPath: "/tmp/coverage.txt"),
    jsonOutput: "{}",
    textOutput: "overall 100.00% (1/1)"
  )
  #expect(artifacts.report.coveredLines == 1)
  #expect(artifacts.jsonPath.lastPathComponent == "coverage.json")
  #expect(artifacts.textPath.lastPathComponent == "coverage.txt")
}

@Test func coverageReporterTreatsPathBasedTestBundlesAsExcludedTests() throws {
  try withTemporaryDirectory { directory in
    let resultBundlePath = directory.appendingPathComponent("result.xcresult")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let pathOnlyTestsJSON = #"""
      {"targets":[{"buildProductPath":"/tmp/Runner.xctest/Contents/MacOS/Runner","coveredLines":2,"executableLines":2,"files":[{"coveredLines":2,"executableLines":2,"name":"Runner.swift","path":"/tmp/Runner.swift"}],"name":"Runner"}]}
      """#

    do {
      _ = try CoverageReporter(
        processRunner: StubProcessRunner(results: [
          "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(
            pathOnlyTestsJSON)
        ])
      ).export(
        resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, product: .client,
        includeTestTargets: false, showFiles: false)
      Issue.record("Expected path-based test bundles to be excluded.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "coverage_targets_missing")
    }
  }
}

@Test func coverageReporterTreatsNilBuildProductPathsAsNonTests() throws {
  try withTemporaryDirectory { directory in
    let resultBundlePath = directory.appendingPathComponent("result.xcresult")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let nonTestJSON = #"""
      {"targets":[{"buildProductPath":null,"coveredLines":3,"executableLines":3,"files":[{"coveredLines":3,"executableLines":3,"name":"Main.swift","path":"/tmp/Main.swift"}],"name":"SymphonyServer"}]}
      """#

    let artifacts = try CoverageReporter(
      processRunner: StubProcessRunner(results: [
        "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(
          nonTestJSON)
      ])
    ).export(
      resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, product: .server,
      includeTestTargets: false, showFiles: false)

    #expect(artifacts.report.targets.map { $0.name } == ["SymphonyServer"])
  }
}

@Test func coverageReporterRendersCommandsAndFallbackMessages() throws {
  try withTemporaryDirectory { directory in
    let resultBundlePath = directory.appendingPathComponent("result.xcresult")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let reporter = CoverageReporter(
      processRunner: StubProcessRunner(results: [
        "xcrun xccov view --report --json \(resultBundlePath.path)": CommandResult(
          exitStatus: 0, stdout: "", stderr: "")
      ]))

    #expect(
      reporter.renderedCommandLine(resultBundlePath: resultBundlePath)
        == "xcrun xccov view --report --json \(resultBundlePath.path)")

    do {
      _ = try reporter.export(
        resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, product: .client,
        includeTestTargets: false, showFiles: false)
      Issue.record("Expected empty xccov output to use the fallback coverage-export message.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "coverage_export_failed")
      #expect(error.message == "Failed to export coverage from the xcresult bundle.")
    }
  }
}

@Test func coverageReporterIncludesFileListingsWhenRequested() throws {
  try withTemporaryDirectory { directory in
    let resultBundlePath = directory.appendingPathComponent("result.xcresult")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let json = #"""
      {
        "targets": [
          {
            "buildProductPath": "/tmp/Symphony.app",
            "coveredLines": 3,
            "executableLines": 4,
            "files": [
              { "coveredLines": 1, "executableLines": 2, "name": "Beta.swift", "path": "/tmp/Beta.swift" },
              { "coveredLines": 2, "executableLines": 2, "name": "Alpha.swift", "path": "/tmp/Alpha.swift" }
            ],
            "name": "Symphony"
          },
          {
            "buildProductPath": "/tmp/SymphonyTests.xctest/Contents/MacOS/SymphonyTests",
            "coveredLines": 2,
            "executableLines": 2,
            "files": [
              { "coveredLines": 2, "executableLines": 2, "name": "Ignored.swift", "path": "/tmp/Ignored.swift" }
            ],
            "name": "SymphonyTests.xctest"
          }
        ]
      }
      """#

    let artifacts = try CoverageReporter(
      processRunner: StubProcessRunner(results: [
        "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(json)
      ])
    ).export(
      resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, product: .client,
      includeTestTargets: false, showFiles: true)

    #expect(artifacts.report.excludedTargets == ["SymphonyTests.xctest"])
    #expect(artifacts.report.targets.count == 1)
    #expect(artifacts.report.targets[0].files?.map(\.name) == ["Beta.swift", "Alpha.swift"])
    #expect(artifacts.textOutput.contains("excluded_targets SymphonyTests.xctest"))
    #expect(artifacts.textOutput.contains("file Symphony Alpha.swift 100.00% (2/2)"))
    #expect(artifacts.textOutput.contains("file Symphony Beta.swift 50.00% (1/2)"))
  }
}

@Test func coverageReporterExcludesSwiftPackageFrameworkTargetsForClientCoverage() throws {
  try withTemporaryDirectory { directory in
    let resultBundlePath = directory.appendingPathComponent("result.xcresult")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let json = #"""
      {
        "targets": [
          {
            "buildProductPath": "/tmp/Build/Products/Debug/Symphony.app/Contents/MacOS/Symphony",
            "coveredLines": 5,
            "executableLines": 5,
            "files": [
              { "coveredLines": 5, "executableLines": 5, "name": "ContentView.swift", "path": "/tmp/ContentView.swift" }
            ],
            "name": "Symphony.app"
          },
          {
            "buildProductPath": "/tmp/Build/Products/Debug/PackageFrameworks/SymphonyShared_ABC123_PackageProduct.framework/SymphonyShared_ABC123_PackageProduct",
            "coveredLines": 1,
            "executableLines": 4,
            "files": [
              { "coveredLines": 1, "executableLines": 4, "name": "SymphonyShared.swift", "path": "/tmp/SymphonyShared.swift" }
            ],
            "name": "SymphonyShared"
          }
        ]
      }
      """#

    let artifacts = try CoverageReporter(
      processRunner: StubProcessRunner(results: [
        "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(json)
      ])
    ).export(
      resultBundlePath: resultBundlePath,
      artifactRoot: artifactRoot,
      product: .client,
      includeTestTargets: false,
      showFiles: true
    )

    #expect(artifacts.report.targets.map(\.name) == ["Symphony.app"])
    #expect(artifacts.report.excludedTargets == ["SymphonyShared"])
    #expect(artifacts.report.coveredLines == 5)
    #expect(artifacts.report.executableLines == 5)
  }
}

@Test func swiftPMCoverageReporterCoversFailuresAndGroupedOutput() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyRuntime"),
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
    } catch let error as SymphonyBuildError {
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
    } catch let error as SymphonyBuildError {
      #expect(error.code == "swiftpm_coverage_decode_failed")
    }

    let noSourcesPath = directory.appendingPathComponent("swiftpm-no-sources.json")
    try #"""
    {"data":[{"files":[{"filename":"__REPO__/Tests/SymphonyServerTests/Foo.swift","summary":{"lines":{"count":10,"covered":10}}},{"filename":"__REPO__/Sources/SymphonyRuntime/Zero.swift","summary":{"lines":{"count":0,"covered":0}}}]}]}
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
    } catch let error as SymphonyBuildError {
      #expect(error.code == "swiftpm_coverage_sources_missing")
    }

    let successPath = directory.appendingPathComponent("swiftpm-success.json")
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyRuntime/Zeta.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyRuntime/Alpha.swift", "summary": { "lines": { "count": 3, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyServer/main.swift", "summary": { "lines": { "count": 4, "covered": 3 } } },
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
    #expect(artifacts.report.excludedTargets == ["SymphonyServerTests"])
    #expect(artifacts.report.targets.map(\.name) == ["SymphonyRuntime", "SymphonyServer"])
    #expect(
      artifacts.report.targets[0].files?.map(\.path) == [
        "Sources/SymphonyRuntime/Alpha.swift",
        "Sources/SymphonyRuntime/Zeta.swift",
      ])
    #expect(artifacts.report.targets[1].files?.map(\.path) == ["Sources/SymphonyServer/main.swift"])
    #expect(artifacts.textOutput.contains("target SymphonyRuntime 80.00% (4/5)"))
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
      at: repoRoot.appendingPathComponent("Sources/SymphonyRuntime"),
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
            { "filename": "__REPO__/Sources/SymphonyRuntime/Alpha.swift", "summary": { "lines": { "count": 1, "covered": 1 } } },
            { "filename": "__REPO__/Sources/SymphonyRuntime/Alpha.swift", "summary": { "lines": { "count": 1, "covered": 0 } } },
            { "filename": "__REPO__/Sources/SymphonyServer/main.swift", "summary": { "lines": { "count": 1, "covered": 1 } } }
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
        "Sources/SymphonyRuntime/Alpha.swift",
        "Sources/SymphonyRuntime/Alpha.swift",
      ])
  }
}

@Test func swiftPMCoverageReporterAllowsSingleCoveredTargetWhenServerFilesAreMissing() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyRuntime"),
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
            { "filename": "__REPO__/Sources/SymphonyRuntime/BootstrapSupport.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
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

    #expect(artifacts.report.targets.map(\.name) == ["SymphonyRuntime"])
    #expect(artifacts.report.targets[0].files == nil)
  }
}

@Test func commitHarnessCoversValidationFailuresAndCoverageCommandFailures() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let coveragePath = repoRoot.appendingPathComponent(".build/package.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try
      #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}"#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: coveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )

    do {
      _ = try CommitHarness(processRunner: StubProcessRunner()).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 101, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected invalid coverage thresholds to fail.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "invalid_coverage_threshold")
    }

    do {
      _ = try CommitHarness(
        processRunner: StubProcessRunner(results: [
          "swift test --enable-code-coverage": StubProcessRunner.failure("tests failed")
        ])
      ).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected failing swift test runs to fail the harness.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message.contains("swift test --enable-code-coverage"))
    }

    do {
      _ = try CommitHarness(
        processRunner: StubProcessRunner(results: [
          "swift test --enable-code-coverage": StubProcessRunner.success(),
          "swift test --show-code-coverage-path": StubProcessRunner.failure("no path"),
        ])
      ).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected coverage-path lookup failures to fail the harness.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message.contains("coverage JSON path"))
    }

    do {
      _ = try CommitHarness(
        processRunner: StubProcessRunner(results: [
          "swift test --enable-code-coverage": StubProcessRunner.success(),
          "swift test --show-code-coverage-path": StubProcessRunner.success("\n"),
        ])
      ).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected empty coverage paths to fail.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "missing_package_coverage_path")
    }

    let status = SignalBox()
    let failingCoverageRunner = CoverageCommandProcessRunner(
      packageCoveragePath: coveragePath.path,
      coverageResult: CommandResult(exitStatus: 1, stdout: "", stderr: "coverage failed")
    )
    do {
      _ = try CommitHarness(processRunner: failingCoverageRunner, statusSink: { status.append($0) })
        .run(
          workspace: workspace,
          request: HarnessCommandRequest(
            minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
        )
      Issue.record("Expected failing coverage commands to fail the harness.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message.contains("did not pass"))
    }
    #expect(status.values.contains(where: { $0.contains("running commit harness tests") }))

    let emptyCoverageRunner = CoverageCommandProcessRunner(
      packageCoveragePath: coveragePath.path,
      coverageResult: CommandResult(exitStatus: 0, stdout: "", stderr: "")
    )
    do {
      _ = try CommitHarness(processRunner: emptyCoverageRunner).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected empty test artifact root to fail.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "missing_test_artifact_root")
    }

    let invalidCoverageRunner = CoverageCommandProcessRunner(
      packageCoveragePath: coveragePath.path,
      coverageResult: CommandResult(exitStatus: 0, stdout: "/nonexistent/path", stderr: "")
    )
    do {
      _ = try CommitHarness(processRunner: invalidCoverageRunner).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected missing coverage.json at artifact root to fail.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "missing_bootstrap_coverage_json")
    }

    let undercoveredCoverageJSON = #"""
      {"coveredLines":1,"executableLines":2,"lineCoverage":0.5,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"Suite","buildProductPath":null,"coveredLines":1,"executableLines":2,"lineCoverage":0.5,"files":[{"name":"Foo.swift","path":"/tmp/Foo.swift","coveredLines":1,"executableLines":2,"lineCoverage":0.5}]}]}
      """#
    let thresholdArtifactRoot = directory.appendingPathComponent(
      "threshold-artifacts", isDirectory: true)
    try FileManager.default.createDirectory(
      at: thresholdArtifactRoot, withIntermediateDirectories: true)
    try undercoveredCoverageJSON.write(
      to: thresholdArtifactRoot.appendingPathComponent("coverage.json"), atomically: true,
      encoding: .utf8)
    let thresholdFailureRunner = CoverageCommandProcessRunner(
      packageCoveragePath: coveragePath.path,
      coverageResult: CommandResult(exitStatus: 0, stdout: thresholdArtifactRoot.path, stderr: "")
    )
    do {
      _ = try CommitHarness(processRunner: thresholdFailureRunner).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 100, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected below-threshold coverage to fail the harness.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message.contains("below the required threshold"))
      #expect(error.message.contains("client coverage 50.00% (1/2)"))
    }

    #expect(
      CommitHarness.resolvedExecutablePath(raw: "/tmp/symphony-build", workingDirectory: repoRoot)
        == "/tmp/symphony-build")
    #expect(
      CommitHarness.resolvedExecutablePath(
        raw: "./.build/debug/symphony-build", workingDirectory: repoRoot
      ).hasSuffix(".build/debug/symphony-build"))
  }
}

@Test func commitHarnessUsesDefaultCoverageLoadersForBothClientAndServer() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let coveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try
      #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}"#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: coveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let coverageJSON = #"""
      {"coveredLines":1,"executableLines":1,"lineCoverage":1,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"Suite","buildProductPath":null,"coveredLines":1,"executableLines":1,"lineCoverage":1,"files":[]}]}
      """#
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    try coverageJSON.write(
      to: artifactRoot.appendingPathComponent("coverage.json"), atomically: true, encoding: .utf8)
    let runner = DualCoverageProcessRunner(
      packageCoveragePath: coveragePath.path, artifactRoot: artifactRoot.path)

    let report = try CommitHarness(
      processRunner: runner,
      statusSink: { _ in },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).run(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )

    #expect(try #require(report.clientCoverage).targets.map { $0.name } == ["Suite"])
    #expect(report.serverCoverage.targets.map { $0.name } == ["Suite"])
  }
}

@Test func commitHarnessExecuteDecodesInspectionFromArtifactFiles() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let coveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try
      #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}"#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: coveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let coverageReport = CoverageReport(
      coveredLines: 1,
      executableLines: 2,
      lineCoverage: 0.5,
      includeTestTargets: false,
      excludedTargets: [],
      targets: [
        CoverageTargetReport(
          name: "Suite", buildProductPath: nil, coveredLines: 1, executableLines: 2,
          lineCoverage: 0.5,
          files: [
            CoverageFileReport(
              name: "Foo.swift", path: "/tmp/Foo.swift", coveredLines: 1, executableLines: 2,
              lineCoverage: 0.5)
          ])
      ]
    )
    let inspectionReport = CoverageInspectionReport(
      backend: .swiftPM,
      product: .server,
      generatedAt: "2026-03-25T00:00:00Z",
      files: [
        CoverageInspectionFileReport(
          targetName: "Suite",
          path: "/tmp/Foo.swift",
          coveredLines: 1,
          executableLines: 2,
          lineCoverage: 0.5,
          missingLineRanges: [CoverageLineRange(startLine: 10, endLine: 10)],
          functions: []
        )
      ]
    )

    // Create artifact directories with coverage files on disk
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    try JSONEncoder().encode(coverageReport).write(
      to: artifactRoot.appendingPathComponent("coverage.json"))
    try JSONEncoder().encode(inspectionReport).write(
      to: artifactRoot.appendingPathComponent("coverage-inspection.json"))

    let runner = ArtifactPathProcessRunner(
      packageCoveragePath: coveragePath.path, artifactRoot: artifactRoot.path)

    let execution = try CommitHarness(
      processRunner: runner,
      statusSink: { _ in },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).execute(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )

    #expect(execution.report.clientCoverage == coverageReport)
    #expect(execution.report.serverCoverage == coverageReport)
    #expect(execution.clientInspection == inspectionReport)
    #expect(execution.serverInspection == inspectionReport)

    // Test without inspection file — harness should still succeed with nil inspection
    let noInspectionArtifactRoot = directory.appendingPathComponent(
      "artifacts-no-inspection", isDirectory: true)
    try FileManager.default.createDirectory(
      at: noInspectionArtifactRoot, withIntermediateDirectories: true)
    try JSONEncoder().encode(coverageReport).write(
      to: noInspectionArtifactRoot.appendingPathComponent("coverage.json"))

    let noInspectionRunner = ArtifactPathProcessRunner(
      packageCoveragePath: coveragePath.path, artifactRoot: noInspectionArtifactRoot.path)
    let noInspectionExecution = try CommitHarness(
      processRunner: noInspectionRunner,
      statusSink: { _ in },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).execute(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )
    #expect(noInspectionExecution.clientInspection == nil)
    #expect(noInspectionExecution.serverInspection == nil)
  }
}

@Test func commitHarnessCachesToolchainCapabilitiesAcrossExecution() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let coveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try
      #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":10,"covered":9}}}]}]}"#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: coveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let resolver = CountingToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)

    let report = try CommitHarness(
      processRunner: CoverageCommandProcessRunner(
        packageCoveragePath: coveragePath.path,
        coverageResult: StubProcessRunner.success()
      ),
      statusSink: { _ in },
      serverCoverageLoader: { _ in
        CoverageReport(
          coveredLines: 1,
          executableLines: 1,
          lineCoverage: 1,
          includeTestTargets: false,
          excludedTargets: [],
          targets: [
            CoverageTargetReport(
              name: "Suite", buildProductPath: nil, coveredLines: 1, executableLines: 1,
              lineCoverage: 1, files: [])
          ]
        )
      },
      toolchainCapabilitiesResolver: resolver
    ).run(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 100, json: false, currentDirectory: repoRoot)
    )

    #expect(report.packageFileViolations.map(\.name) == ["Sources/Foo.swift"])
    #expect(resolver.resolveCount == 1)
  }
}

@Test func commitHarnessSkipsClientCoverageWhenXcodeIsUnavailable() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let coveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try
      #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}"#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: coveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let coverageJSON = #"""
      {"coveredLines":1,"executableLines":1,"lineCoverage":1,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"Suite","buildProductPath":null,"coveredLines":1,"executableLines":1,"lineCoverage":1,"files":[]}]}
      """#
    let noXcodeArtifactRoot = directory.appendingPathComponent(
      "artifacts-noxcode", isDirectory: true)
    try FileManager.default.createDirectory(
      at: noXcodeArtifactRoot, withIntermediateDirectories: true)
    try coverageJSON.write(
      to: noXcodeArtifactRoot.appendingPathComponent("coverage.json"), atomically: true,
      encoding: .utf8)
    let runner = DualCoverageProcessRunner(
      packageCoveragePath: coveragePath.path, artifactRoot: noXcodeArtifactRoot.path)

    let report = try CommitHarness(
      processRunner: runner,
      statusSink: { _ in },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .noXcodeForTests)
    ).run(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )

    #expect(report.clientCoverageInvocation == nil)
    #expect(report.clientCoverage == nil)
    #expect(
      report.clientCoverageSkipReason
        == "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
    )
    #expect(report.serverCoverage.targets.map(\.name) == ["Suite"])
  }
}

@Test func commitHarnessOverlapsCoveragePathLookupWithCoverageSuites() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let packageCoveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
    try FileManager.default.createDirectory(
      at: packageCoveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try
      #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}"#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: packageCoveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let coverageJSON = #"""
      {"coveredLines":1,"executableLines":1,"lineCoverage":1,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"Suite","buildProductPath":null,"coveredLines":1,"executableLines":1,"lineCoverage":1,"files":[]}]}
      """#
    let clientArtifactRoot = directory.appendingPathComponent("client-artifacts", isDirectory: true)
    let serverArtifactRoot = directory.appendingPathComponent("server-artifacts", isDirectory: true)
    try FileManager.default.createDirectory(
      at: clientArtifactRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: serverArtifactRoot, withIntermediateDirectories: true)
    try coverageJSON.write(
      to: clientArtifactRoot.appendingPathComponent("coverage.json"), atomically: true,
      encoding: .utf8)
    try coverageJSON.write(
      to: serverArtifactRoot.appendingPathComponent("coverage.json"), atomically: true,
      encoding: .utf8)

    let runner = ParallelCoverageHarnessProcessRunner(
      packageCoveragePath: packageCoveragePath.path,
      clientArtifactRoot: clientArtifactRoot.path,
      serverArtifactRoot: serverArtifactRoot.path
    )

    let execution = try CommitHarness(
      processRunner: runner,
      statusSink: { _ in },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).execute(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )

    #expect(execution.report.clientCoverage?.targets.map(\.name) == ["Suite"])
    #expect(execution.report.serverCoverage.targets.map(\.name) == ["Suite"])
  }
}

@Test func commitHarnessFiltersSwiftTestCompileNoiseAndPropagatesOutputModeToCoverageCommands()
  throws
{
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let packageCoveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
    try FileManager.default.createDirectory(
      at: packageCoveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/Foo.swift", "summary": { "lines": { "count": 1, "covered": 1 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: packageCoveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let coverageJSON = #"""
      {"coveredLines":1,"executableLines":1,"lineCoverage":1,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"Suite","buildProductPath":null,"coveredLines":1,"executableLines":1,"lineCoverage":1,"files":[]}]}
      """#

    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    try coverageJSON.write(
      to: artifactRoot.appendingPathComponent("coverage.json"), atomically: true, encoding: .utf8)

    let filteredStatus = SignalBox()
    let filteredRunner = HarnessOutputControlProcessRunner(
      packageCoveragePath: packageCoveragePath.path,
      artifactRoot: artifactRoot.path
    )
    _ = try CommitHarness(
      processRunner: filteredRunner,
      statusSink: { filteredStatus.append($0) },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).run(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )

    #expect(
      filteredStatus.values.contains(where: { $0.contains("warning: important harness warning") }))
    #expect(
      !filteredStatus.values.contains(where: { $0.contains("Compiling NIOCore AsyncChannel.swift") }
      ))
    #expect(filteredStatus.values.contains(where: { $0.contains("suppressed 1 low-signal lines") }))

    let quietStatus = SignalBox()
    let quietRunner = HarnessOutputControlProcessRunner(
      packageCoveragePath: packageCoveragePath.path,
      artifactRoot: artifactRoot.path
    )
    _ = try CommitHarness(
      processRunner: quietRunner,
      statusSink: { quietStatus.append($0) },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).run(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, outputMode: .quiet, currentDirectory: repoRoot)
    )

    #expect(
      !quietStatus.values.contains(where: { $0.contains("warning: important harness warning") }))
    #expect(
      !quietStatus.values.contains(where: { $0.contains("Compiling NIOCore AsyncChannel.swift") }))
    #expect(
      quietRunner.commands.contains(where: {
        $0.contains("test --product client") && $0.contains("--xcode-output-mode quiet")
      }))
    #expect(
      quietRunner.commands.contains(where: {
        $0.contains("test --product server") && $0.contains("--xcode-output-mode quiet")
      }))
  }
}

@Test func commitHarnessHelperClosuresForwardSignalsAndFilterCoverageOutput() throws {
  let status = SignalBox()
  let observation = ProcessObservation(
    label: "swift test",
    onStaleSignal: { message in
      status.append(message)
    },
    onLine: { stream, line in
      guard stream == .stderr else {
        return
      }
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        return
      }
      status.append(trimmed)
    }
  )
  observation.onStaleSignal?("stale-signal")
  observation.onLine?(.stdout, "   ")
  observation.onLine?(.stderr, "observed line")
  #expect(status.values == ["stale-signal", "observed line"])

  let coverageJSON = #"""
    {"coveredLines":4,"executableLines":4,"lineCoverage":1,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"SymphonyServer","buildProductPath":"/tmp/SymphonyServer","coveredLines":4,"executableLines":4,"lineCoverage":1,"files":[]}]}
    """#
  let artifactDir = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: artifactDir) }
  try coverageJSON.write(
    to: artifactDir.appendingPathComponent("coverage.json"), atomically: true, encoding: .utf8)
  let runner = ObservationCoverageRunner(stdout: artifactDir.path + "\n") { observation in
    observation?.onStaleSignal?("coverage stale")
    observation?.onLine?(.stdout, "ignore stdout")
    observation?.onLine?(.stderr, " ")
    observation?.onLine?(.stderr, "stderr line")
  }
  let report = try CommitHarness.runCoverageSuite(
    processRunner: runner,
    executablePath: "/tmp/symphony-build",
    arguments: ["test", "--product", "server"],
    currentDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true),
    statusSink: { status.append($0) }
  )
  #expect(report.targets.map { $0.name } == ["SymphonyServer"])
  #expect(status.values.contains("coverage stale"))
  #expect(status.values.contains("stderr line"))
  #expect(!status.values.contains("ignore stdout"))
}

@Test func gitHookInstallerAndProcessRunnersCoverDetachedAndObservationPaths() throws {
  try withTemporaryDirectory { directory in
    let workspace = WorkspaceContext(
      projectRoot: directory,
      buildStateRoot: directory.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )

    do {
      _ = try GitHookInstaller(
        processRunner: StubProcessRunner(results: [
          "git config core.hooksPath .githooks": StubProcessRunner.failure("git broke")
        ])
      ).install(workspace: workspace)
      Issue.record("Expected git hook install failures to surface.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "git_hooks_install_failed")
    }

    do {
      _ = try GitHookInstaller(
        processRunner: StubProcessRunner(results: [
          "git config core.hooksPath .githooks": CommandResult(
            exitStatus: 1, stdout: "", stderr: "")
        ])
      ).install(workspace: workspace)
      Issue.record("Expected empty-output git hook install failures to use the fallback message.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "git_hooks_install_failed")
      #expect(error.message == "Failed to configure core.hooksPath.")
    }

    let combined = CommandResult(exitStatus: 0, stdout: "one", stderr: "two")
    #expect(combined.combinedOutput == "one\ntwo")
    #expect(CommandResult(exitStatus: 0, stdout: "one", stderr: "").combinedOutput == "one")
    #expect(CommandResult(exitStatus: 0, stdout: "", stderr: "two").combinedOutput == "two")

    let protocolRunner = ProtocolExtensionRunner()
    _ = try protocolRunner.run(
      command: "echo", arguments: [], environment: [:], currentDirectory: directory)
    #expect(protocolRunner.lastObservationWasNil)

    let systemRunner = SystemProcessRunner()
    let noObservation = try systemRunner.run(
      command: "sh",
      arguments: ["-c", "printf 'plain-output\n'"],
      environment: [:],
      currentDirectory: directory
    )
    #expect(noObservation.stdout == "plain-output\n")

    let lines = SignalBox()
    let result = try systemRunner.run(
      command: "/bin/sh",
      arguments: ["-c", "printf 'hello\\n'; printf 'problem\\n' >&2"],
      environment: ["FOO": "bar"],
      currentDirectory: directory,
      observation: ProcessObservation(
        label: "shell",
        onLine: { stream, line in lines.append("\(stream.rawValue):\(line)") }
      )
    )
    #expect(result.stdout == "hello\n")
    #expect(result.stderr == "problem\n")
    #expect(lines.values.contains("stdout:hello"))
    #expect(lines.values.contains("stderr:problem"))

    let detachedOutput = directory.appendingPathComponent("detached/output.txt")
    let pid = try systemRunner.startDetached(
      executablePath: "/bin/sh",
      arguments: ["-c", "echo $DETACHED_VALUE"],
      environment: ["DETACHED_VALUE": "detached"],
      currentDirectory: directory,
      output: detachedOutput
    )
    #expect(pid > 0)

    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
      if let contents = try? String(contentsOf: detachedOutput, encoding: .utf8),
        contents.contains("detached")
      {
        break
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    #expect((try String(contentsOf: detachedOutput, encoding: .utf8)).contains("detached"))

    _ = try systemRunner.run(
      command: "sh",
      arguments: ["-c", "sleep 0.12"],
      environment: [:],
      currentDirectory: nil,
      observation: ProcessObservation(label: "stderr-heartbeat", staleInterval: 0.05)
    )
  }
}

@Test func systemProcessRunnerDefaultArgumentsAndEmptyCombinedOutputRemainUsable() throws {
  try withTemporaryDirectory { directory in
    #expect(CommandResult(exitStatus: 0, stdout: "", stderr: "").combinedOutput.isEmpty)

    let runner = SystemProcessRunner()
    let result = try runner.run(
      command: "/bin/sh",
      arguments: ["-c", "printf 'defaults-covered'"]
    )
    #expect(result.stdout == "defaults-covered")
    #expect(result.stderr.isEmpty)

    let output = directory.appendingPathComponent("detached-existing.txt")
    try "stale".write(to: output, atomically: true, encoding: .utf8)

    let pid = try runner.startDetached(
      executablePath: "/bin/sh",
      arguments: ["-c", "printf 'existing-file-covered'"],
      output: output
    )
    #expect(pid > 0)

    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
      if let contents = try? String(contentsOf: output, encoding: .utf8),
        contents.contains("existing-file-covered")
      {
        break
      }
      Thread.sleep(forTimeInterval: 0.05)
    }

    let contents = try String(contentsOf: output, encoding: .utf8)
    #expect(contents.contains("existing-file-covered"))
    #expect(!contents.contains("stale"))
  }
}

@Test func processHelpersCoverLineEmitterRemaindersAndIdleStaleSignals() {
  let silentEmitter = LineEmitter(stream: .stdout, observation: nil)
  silentEmitter.append(Data())
  silentEmitter.append(Data("ignored\n".utf8))
  silentEmitter.finish()

  let lines = SignalBox()
  let observedEmitter = LineEmitter(
    stream: .stderr,
    observation: ProcessObservation(
      label: "emitter",
      onLine: { stream, line in
        lines.append("\(stream.rawValue):\(line)")
      })
  )
  observedEmitter.append(Data("line-1\npartial".utf8))
  observedEmitter.finish()

  #expect(lines.values == ["stderr:line-1", "stderr:partial"])

  let collector = DataCollector()
  let staleSignals = SignalBox()
  let controller = StaleSignalController(
    observation: ProcessObservation(
      label: "idle", staleInterval: 60, onStaleSignal: { staleSignals.append($0) }),
    collector: collector
  )
  controller.signalIfNeeded()

  #expect(collector.data.isEmpty)
  #expect(staleSignals.values.isEmpty)
}

@Test func staleSignalControllerWritesHeartbeatWhenNoCallbackIsConfigured() {
  let collector = DataCollector()
  let controller = StaleSignalController(
    observation: ProcessObservation(label: "heartbeat", staleInterval: 0.01),
    collector: collector
  )

  Thread.sleep(forTimeInterval: 0.02)
  controller.signalIfNeeded()

  let message = String(decoding: collector.data, as: UTF8.self)
  #expect(message.contains("heartbeat still running"))
}

@Test func artifactManagerRecursiveFilesSkipsPlainFilesWhenEnumerationIsUnavailable() throws {
  let manager = ArtifactManager(processRunner: StubProcessRunner(), enumeratorFactory: { _ in nil })
  #expect(
    manager.recursiveFiles(in: [URL(fileURLWithPath: "/tmp/missing", isDirectory: true)]).isEmpty)
}

@Test func renderHumanIncludesUncoveredFunctionNamesInViolations() {
  let reporter = PackageCoverageReporter()
  let packageReport = PackageCoverageReport(
    scope: "first_party_sources", coveredLines: 9, executableLines: 10, lineCoverage: 0.9,
    coverageJSONPath: "/tmp/coverage.json", files: [])
  let serverCoverage = CoverageReport(
    coveredLines: 10, executableLines: 10, lineCoverage: 1,
    includeTestTargets: false, excludedTargets: [], targets: [])
  let human = reporter.renderHuman(
    report: HarnessReport(
      minimumCoveragePercent: 100,
      testsInvocation: "swift test",
      coveragePathInvocation: "swift test --show-code-coverage-path",
      packageCoverage: packageReport,
      clientCoverageInvocation: nil,
      clientCoverage: nil,
      serverCoverageInvocation: "server",
      serverCoverage: serverCoverage,
      packageFileViolations: [
        HarnessCoverageViolation(
          suite: "package", kind: "file", name: "Sources/Foo.swift",
          coveredLines: 9, executableLines: 10, lineCoverage: 0.9,
          uncoveredFunctions: ["reconcile()", "tick()"])
      ],
      clientTargetViolations: [],
      clientFileViolations: [],
      serverTargetViolations: [],
      serverFileViolations: []
    )
  )
  #expect(human.contains("package file Sources/Foo.swift 90.00% (9/10)"))
  #expect(human.contains("  function reconcile()"))
  #expect(human.contains("  function tick()"))
}

@Test func renderHumanOmitsFunctionsWhenNilOrEmpty() {
  let reporter = PackageCoverageReporter()
  let packageReport = PackageCoverageReport(
    scope: "first_party_sources", coveredLines: 9, executableLines: 10, lineCoverage: 0.9,
    coverageJSONPath: "/tmp/coverage.json", files: [])
  let serverCoverage = CoverageReport(
    coveredLines: 10, executableLines: 10, lineCoverage: 1,
    includeTestTargets: false, excludedTargets: [], targets: [])
  let humanNil = reporter.renderHuman(
    report: HarnessReport(
      minimumCoveragePercent: 100,
      testsInvocation: "swift test",
      coveragePathInvocation: "swift test --show-code-coverage-path",
      packageCoverage: packageReport,
      clientCoverageInvocation: nil,
      clientCoverage: nil,
      serverCoverageInvocation: "server",
      serverCoverage: serverCoverage,
      packageFileViolations: [
        HarnessCoverageViolation(
          suite: "package", kind: "file", name: "Sources/Foo.swift",
          coveredLines: 9, executableLines: 10, lineCoverage: 0.9)
      ],
      clientTargetViolations: [],
      clientFileViolations: [],
      serverTargetViolations: [],
      serverFileViolations: []
    )
  )
  #expect(!humanNil.contains("function"))
}

@Test func harnessCoverageViolationDecodesWithoutUncoveredFunctions() throws {
  let json = #"{"suite":"package","kind":"file","name":"Foo.swift","coveredLines":9,"executableLines":10,"lineCoverage":0.9}"#
  let data = Data(json.utf8)
  let violation = try JSONDecoder().decode(HarnessCoverageViolation.self, from: data)
  #expect(violation.suite == "package")
  #expect(violation.uncoveredFunctions == nil)
}

@Test func harnessCoverageViolationDecodesWithUncoveredFunctions() throws {
  let json = #"{"suite":"package","kind":"file","name":"Foo.swift","coveredLines":9,"executableLines":10,"lineCoverage":0.9,"uncoveredFunctions":["bar()"]}"#
  let data = Data(json.utf8)
  let violation = try JSONDecoder().decode(HarnessCoverageViolation.self, from: data)
  #expect(violation.uncoveredFunctions == ["bar()"])
}

@Test func enrichViolationsWithFunctionsReturnsEnrichedViolations() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/Foo", isDirectory: true),
      withIntermediateDirectories: true)
    let sourceFile = repoRoot.appendingPathComponent("Sources/Foo/Bar.swift")
    try "func bar() {}".write(to: sourceFile, atomically: true, encoding: .utf8)

    let coveragePath = directory.appendingPathComponent("coverage.json")
    try "{}".write(to: coveragePath, atomically: true, encoding: .utf8)

    let violations = [
      HarnessCoverageViolation(
        suite: "package", kind: "file", name: "Sources/Foo/Bar.swift",
        coveredLines: 9, executableLines: 10, lineCoverage: 0.9)
    ]

    let resolver = StubToolchainCapabilitiesResolver(
      capabilities: ToolchainCapabilities(
        swiftAvailable: true, xcodebuildAvailable: false, xcrunAvailable: false,
        simctlAvailable: false, xcresulttoolAvailable: false, llvmCovCommand: nil))

    do {
      _ = try CommitHarness.enrichViolationsWithFunctions(
        violations: violations,
        coverageJSONPath: coveragePath,
        projectRoot: repoRoot,
        processRunner: StubProcessRunner(),
        toolchainCapabilitiesResolver: resolver
      )
      Issue.record("Expected enrichment to throw when llvm-cov is unavailable.")
    } catch {
      // Expected: no llvm-cov available
    }
  }
}

private struct CoverageCommandProcessRunner: ProcessRunning {
  let packageCoveragePath: String
  let coverageResult: CommandResult

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      observation?.onLine?(.stdout, "swift test passed")
      observation?.onStaleSignal?("[symphony-build] swift test still running")
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if arguments.prefix(3) == ["test", "--product", "client"]
      || arguments.prefix(3) == ["test", "--product", "server"]
    {
      observation?.onLine?(.stderr, "coverage stderr")
      return coverageResult
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

private final class HarnessOutputControlProcessRunner: ProcessRunning, @unchecked Sendable {
  let packageCoveragePath: String
  let artifactRoot: String
  private let lock = NSLock()
  private var storage = [String]()

  init(packageCoveragePath: String, artifactRoot: String) {
    self.packageCoveragePath = packageCoveragePath
    self.artifactRoot = artifactRoot
  }

  var commands: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    let rendered = ([command] + arguments).joined(separator: " ")
    lock.lock()
    storage.append(rendered)
    lock.unlock()

    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      observation?.onLine?(.stdout, "Compiling NIOCore AsyncChannel.swift")
      observation?.onLine?(.stderr, "warning: important harness warning")
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if arguments.prefix(3) == ["test", "--product", "client"]
      || arguments.prefix(3) == ["test", "--product", "server"]
    {
      return StubProcessRunner.success(artifactRoot + "\n")
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

private final class ProtocolExtensionRunner: ProcessRunning, @unchecked Sendable {
  private(set) var lastObservationWasNil = false

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    lastObservationWasNil = observation == nil
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

private struct ObservationCoverageRunner: ProcessRunning {
  let stdout: String
  let observe: @Sendable (ProcessObservation?) -> Void

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    observe(observation)
    return StubProcessRunner.success(stdout)
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

private struct DualCoverageProcessRunner: ProcessRunning {
  let packageCoveragePath: String
  let artifactRoot: String

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if arguments.prefix(3) == ["test", "--product", "client"]
      || arguments.prefix(3) == ["test", "--product", "server"]
    {
      return StubProcessRunner.success(artifactRoot + "\n")
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

private struct ArtifactPathProcessRunner: ProcessRunning {
  let packageCoveragePath: String
  let artifactRoot: String

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if arguments.prefix(3) == ["test", "--product", "client"]
      || arguments.prefix(3) == ["test", "--product", "server"]
    {
      return StubProcessRunner.success(artifactRoot + "\n")
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

private final class CountingToolchainCapabilitiesResolver: ToolchainCapabilitiesResolving,
  @unchecked Sendable
{
  let capabilities: ToolchainCapabilities
  private let lock = NSLock()
  private var storage = 0

  init(capabilities: ToolchainCapabilities) {
    self.capabilities = capabilities
  }

  var resolveCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func resolve() throws -> ToolchainCapabilities {
    lock.lock()
    storage += 1
    lock.unlock()
    return capabilities
  }
}

private enum ParallelCoverageHarnessError: Error {
  case coveragePathDidNotOverlapSuites
  case clientSuiteDidNotOverlapServer
  case serverSuiteDidNotOverlapClient
}

private final class ParallelCoverageHarnessProcessRunner: ProcessRunning, @unchecked Sendable {
  let packageCoveragePath: String
  let clientArtifactRoot: String
  let serverArtifactRoot: String
  private let suiteStarted = DispatchSemaphore(value: 0)
  private let clientStarted = DispatchSemaphore(value: 0)
  private let serverStarted = DispatchSemaphore(value: 0)

  init(packageCoveragePath: String, clientArtifactRoot: String, serverArtifactRoot: String) {
    self.packageCoveragePath = packageCoveragePath
    self.clientArtifactRoot = clientArtifactRoot
    self.serverArtifactRoot = serverArtifactRoot
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      guard suiteStarted.wait(timeout: .now() + 1) == .success else {
        throw ParallelCoverageHarnessError.coveragePathDidNotOverlapSuites
      }
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if arguments.prefix(3) == ["test", "--product", "client"] {
      suiteStarted.signal()
      clientStarted.signal()
      guard serverStarted.wait(timeout: .now() + 1) == .success else {
        throw ParallelCoverageHarnessError.clientSuiteDidNotOverlapServer
      }
      return StubProcessRunner.success(clientArtifactRoot + "\n")
    }
    if arguments.prefix(3) == ["test", "--product", "server"] {
      suiteStarted.signal()
      serverStarted.signal()
      guard clientStarted.wait(timeout: .now() + 1) == .success else {
        throw ParallelCoverageHarnessError.serverSuiteDidNotOverlapClient
      }
      return StubProcessRunner.success(serverArtifactRoot + "\n")
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}
