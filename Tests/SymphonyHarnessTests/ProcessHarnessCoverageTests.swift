import Foundation
import Testing

@testable import SymphonyHarness

@Test func packageCoverageReporterCoversFailureModesAndViolations() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)

    let missingPath = directory.appendingPathComponent("missing.json")
    do {
      _ = try PackageCoverageReporter().loadReport(at: missingPath, projectRoot: repoRoot)
      Issue.record("Expected missing coverage files to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_package_coverage_json")
    }

    let invalidJSONPath = directory.appendingPathComponent("invalid.json")
    try "not json".write(to: invalidJSONPath, atomically: true, encoding: .utf8)
    do {
      _ = try PackageCoverageReporter().loadReport(at: invalidJSONPath, projectRoot: repoRoot)
      Issue.record("Expected undecodable coverage exports to fail.")
    } catch let error as SymphonyHarnessError {
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
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "package_coverage_sources_missing")
    }

    let reporter = PackageCoverageReporter()
    let harness = HarnessReport(
      minimumCoveragePercent: 100,
      testsInvocation: "swift test",
      coveragePathInvocation: "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path",
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
        coveragePathInvocation: "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path",
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
        name: "SymphonyServerCore", buildProductPath: nil, coveredLines: 0, executableLines: 0,
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
    } catch let error as SymphonyHarnessError {
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
    } catch let error as SymphonyHarnessError {
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
    } catch let error as SymphonyHarnessError {
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
    } catch let error as SymphonyHarnessError {
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

