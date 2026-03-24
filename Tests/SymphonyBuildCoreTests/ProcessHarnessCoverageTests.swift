import Foundation
import Testing
@testable import SymphonyBuildCore

@Test func packageCoverageReporterCoversFailureModesAndViolations() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)

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
                    PackageCoverageFileReport(path: "Sources/Low.swift", coveredLines: 1, executableLines: 2, lineCoverage: 0.5),
                    PackageCoverageFileReport(path: "Sources/High.swift", coveredLines: 1, executableLines: 2, lineCoverage: 0.5),
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
                            CoverageFileReport(name: "ContentView.swift", path: "/tmp/ContentView.swift", coveredLines: 1, executableLines: 2, lineCoverage: 0.5)
                        ]
                    )
                ]
            ),
            serverCoverageInvocation: "server",
            serverCoverage: CoverageReport(
                coveredLines: 2,
                executableLines: 2,
                lineCoverage: 1,
                includeTestTargets: false,
                excludedTargets: [],
                targets: []
            ),
            packageFileViolations: [HarnessCoverageViolation(suite: "package", kind: "file", name: "Sources/Low.swift", coveredLines: 1, executableLines: 2, lineCoverage: 0.5)],
            clientTargetViolations: [HarnessCoverageViolation(suite: "client", kind: "target", name: "Symphony.app", coveredLines: 1, executableLines: 2, lineCoverage: 0.5)],
            clientFileViolations: [HarnessCoverageViolation(suite: "client", kind: "file", name: "/tmp/ContentView.swift", coveredLines: 1, executableLines: 2, lineCoverage: 0.5)],
            serverTargetViolations: [],
            serverFileViolations: []
        )

        let human = reporter.renderHuman(report: harness)
        #expect(human.contains("violations"))
        #expect(human.contains("client file /tmp/ContentView.swift 50.00% (1/2)"))
        #expect(reporter.makePackageFileViolations(report: harness.packageCoverage, minimumLineCoverage: 1).count == 2)
        #expect(reporter.makeTargetViolations(report: harness.clientCoverage, suite: "client", minimumLineCoverage: 1).count == 1)
        #expect(reporter.makeFileViolations(report: harness.clientCoverage, suite: "client", minimumLineCoverage: 1).count == 1)
        #expect(reporter.makeFileViolations(report: harness.serverCoverage, suite: "server", minimumLineCoverage: 1).isEmpty)
        #expect(PackageCoverageReporter.normalizedCoverage(coveredLines: 0, executableLines: 0) == 0)
    }
}

@Test func packageCoverageReporterSortsFilesAndSkipsFullyCoveredFileViolations() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
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
        try json.replacingOccurrences(of: "__REPO__", with: repoRoot.path).write(to: coveragePath, atomically: true, encoding: .utf8)

        let reporter = PackageCoverageReporter()
        let report = try reporter.loadReport(at: coveragePath, projectRoot: repoRoot)
        #expect(report.files.map(\.path) == ["Sources/Low.swift", "Sources/Alpha.swift", "Sources/Beta.swift"])

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
                            CoverageFileReport(name: "Covered.swift", path: "/tmp/Covered.swift", coveredLines: 2, executableLines: 2, lineCoverage: 1),
                            CoverageFileReport(name: "Partial.swift", path: "/tmp/Partial.swift", coveredLines: 1, executableLines: 2, lineCoverage: 0.5),
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
            CoverageTargetReport(name: "Symphony.app", buildProductPath: nil, coveredLines: 10, executableLines: 10, lineCoverage: 1, files: nil),
            CoverageTargetReport(name: "SymphonyRuntime", buildProductPath: nil, coveredLines: 0, executableLines: 0, lineCoverage: 0, files: nil),
        ]
    )

    #expect(reporter.makeTargetViolations(report: report, suite: "client", minimumLineCoverage: 1).map(\.name) == [])
}

@Test func coverageReporterCoversErrorModesAndTestTargetInclusion() throws {
    try withTemporaryDirectory { directory in
        let resultBundlePath = directory.appendingPathComponent("result.xcresult")
        let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)

        do {
            _ = try CoverageReporter(processRunner: StubProcessRunner(results: [
                "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.failure("xccov broke"),
            ])).export(resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, includeTestTargets: false, showFiles: false)
            Issue.record("Expected xccov failures to surface.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "coverage_export_failed")
        }

        do {
            _ = try CoverageReporter(processRunner: StubProcessRunner(results: [
                "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success("not json"),
            ])).export(resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, includeTestTargets: false, showFiles: false)
            Issue.record("Expected invalid xccov JSON to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "coverage_report_decode_failed")
        }

        let onlyTestsJSON = #"""
        {"targets":[{"buildProductPath":"/tmp/FooTests.xctest/Contents/MacOS/FooTests","coveredLines":2,"executableLines":2,"files":[{"coveredLines":2,"executableLines":2,"name":"FooTests.swift","path":"/tmp/FooTests.swift"}],"name":"FooTests.xctest"}]}
        """#
        do {
            _ = try CoverageReporter(processRunner: StubProcessRunner(results: [
                "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(onlyTestsJSON),
            ])).export(resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, includeTestTargets: false, showFiles: false)
            Issue.record("Expected missing non-test targets to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "coverage_targets_missing")
            #expect(error.message.contains("non-test"))
        }

        let included = try CoverageReporter(processRunner: StubProcessRunner(results: [
            "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(onlyTestsJSON),
        ])).export(resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, includeTestTargets: true, showFiles: false)
        #expect(included.report.includeTestTargets)
        #expect(included.report.excludedTargets.isEmpty)
        #expect(included.textOutput.contains("scope including_test_targets"))
        #expect(CoverageReporter.normalizedCoverage(coveredLines: 0, executableLines: 0) == 0)
    }
}

@Test func coverageReporterTreatsPathBasedTestBundlesAsExcludedTests() throws {
    try withTemporaryDirectory { directory in
        let resultBundlePath = directory.appendingPathComponent("result.xcresult")
        let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
        let pathOnlyTestsJSON = #"""
        {"targets":[{"buildProductPath":"/tmp/Runner.xctest/Contents/MacOS/Runner","coveredLines":2,"executableLines":2,"files":[{"coveredLines":2,"executableLines":2,"name":"Runner.swift","path":"/tmp/Runner.swift"}],"name":"Runner"}]}
        """#

        do {
            _ = try CoverageReporter(processRunner: StubProcessRunner(results: [
                "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(pathOnlyTestsJSON),
            ])).export(resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, includeTestTargets: false, showFiles: false)
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

        let artifacts = try CoverageReporter(processRunner: StubProcessRunner(results: [
            "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(nonTestJSON),
        ])).export(resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, includeTestTargets: false, showFiles: false)

        #expect(artifacts.report.targets.map { $0.name } == ["SymphonyServer"])
    }
}

@Test func coverageReporterRendersCommandsAndFallbackMessages() throws {
    try withTemporaryDirectory { directory in
        let resultBundlePath = directory.appendingPathComponent("result.xcresult")
        let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
        let reporter = CoverageReporter(processRunner: StubProcessRunner(results: [
            "xcrun xccov view --report --json \(resultBundlePath.path)": CommandResult(exitStatus: 0, stdout: "", stderr: ""),
        ]))

        #expect(reporter.renderedCommandLine(resultBundlePath: resultBundlePath) == "xcrun xccov view --report --json \(resultBundlePath.path)")

        do {
            _ = try reporter.export(resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, includeTestTargets: false, showFiles: false)
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

        let artifacts = try CoverageReporter(processRunner: StubProcessRunner(results: [
            "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(json),
        ])).export(resultBundlePath: resultBundlePath, artifactRoot: artifactRoot, includeTestTargets: false, showFiles: true)

        #expect(artifacts.report.excludedTargets == ["SymphonyTests.xctest"])
        #expect(artifacts.report.targets.count == 1)
        #expect(artifacts.report.targets[0].files?.map(\.name) == ["Beta.swift", "Alpha.swift"])
        #expect(artifacts.textOutput.contains("excluded_targets SymphonyTests.xctest"))
        #expect(artifacts.textOutput.contains("file Symphony Alpha.swift 100.00% (2/2)"))
        #expect(artifacts.textOutput.contains("file Symphony Beta.swift 50.00% (1/2)"))
    }
}

@Test func swiftPMCoverageReporterCoversFailuresAndGroupedOutput() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources/SymphonyRuntime"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources/SymphonyServer"), withIntermediateDirectories: true)

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
        #expect(artifacts.report.targets[0].files?.map(\.path) == [
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
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources/SymphonyRuntime"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources/SymphonyServer"), withIntermediateDirectories: true)

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
            artifactRoot: directory.appendingPathComponent("artifacts-duplicate-paths", isDirectory: true),
            showFiles: true
        )

        #expect(artifacts.report.targets[0].files?.map(\.path) == [
            "Sources/SymphonyRuntime/Alpha.swift",
            "Sources/SymphonyRuntime/Alpha.swift",
        ])
    }
}

@Test func swiftPMCoverageReporterAllowsSingleCoveredTargetWhenServerFilesAreMissing() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources/SymphonyRuntime"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources/SymphonyServer"), withIntermediateDirectories: true)

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
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        let coveragePath = repoRoot.appendingPathComponent(".build/package.json")
        try FileManager.default.createDirectory(at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}"#
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
                request: HarnessCommandRequest(minimumCoveragePercent: 101, json: false, currentDirectory: repoRoot)
            )
            Issue.record("Expected invalid coverage thresholds to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "invalid_coverage_threshold")
        }

        do {
            _ = try CommitHarness(processRunner: StubProcessRunner(results: [
                "swift test --enable-code-coverage": StubProcessRunner.failure("tests failed"),
            ])).run(
                workspace: workspace,
                request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
            )
            Issue.record("Expected failing swift test runs to fail the harness.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message.contains("swift test --enable-code-coverage"))
        }

        do {
            _ = try CommitHarness(processRunner: StubProcessRunner(results: [
                "swift test --enable-code-coverage": StubProcessRunner.success(),
                "swift test --show-code-coverage-path": StubProcessRunner.failure("no path"),
            ])).run(
                workspace: workspace,
                request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
            )
            Issue.record("Expected coverage-path lookup failures to fail the harness.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message.contains("coverage JSON path"))
        }

        do {
            _ = try CommitHarness(processRunner: StubProcessRunner(results: [
                "swift test --enable-code-coverage": StubProcessRunner.success(),
                "swift test --show-code-coverage-path": StubProcessRunner.success("\n"),
            ])).run(
                workspace: workspace,
                request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
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
            _ = try CommitHarness(processRunner: failingCoverageRunner, statusSink: { status.append($0) }).run(
                workspace: workspace,
                request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
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
                request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
            )
            Issue.record("Expected empty coverage JSON output to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "missing_bootstrap_coverage_json")
        }

        let invalidCoverageRunner = CoverageCommandProcessRunner(
            packageCoveragePath: coveragePath.path,
            coverageResult: CommandResult(exitStatus: 0, stdout: "not json", stderr: "")
        )
        do {
            _ = try CommitHarness(processRunner: invalidCoverageRunner).run(
                workspace: workspace,
                request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
            )
            Issue.record("Expected undecodable coverage JSON output to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "bootstrap_coverage_decode_failed")
        }

        let undercoveredCoverageJSON = #"""
        {"coveredLines":1,"executableLines":2,"lineCoverage":0.5,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"Suite","buildProductPath":null,"coveredLines":1,"executableLines":2,"lineCoverage":0.5,"files":[{"name":"Foo.swift","path":"/tmp/Foo.swift","coveredLines":1,"executableLines":2,"lineCoverage":0.5}]}]}
        """#
        let thresholdFailureRunner = CoverageCommandProcessRunner(
            packageCoveragePath: coveragePath.path,
            coverageResult: CommandResult(exitStatus: 0, stdout: undercoveredCoverageJSON, stderr: "")
        )
        do {
            _ = try CommitHarness(processRunner: thresholdFailureRunner).run(
                workspace: workspace,
                request: HarnessCommandRequest(minimumCoveragePercent: 100, json: false, currentDirectory: repoRoot)
            )
            Issue.record("Expected below-threshold coverage to fail the harness.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message.contains("below the required threshold"))
            #expect(error.message.contains("client coverage 50.00% (1/2)"))
        }

        #expect(CommitHarness.resolvedExecutablePath(raw: "/tmp/symphony-build", workingDirectory: repoRoot) == "/tmp/symphony-build")
        #expect(CommitHarness.resolvedExecutablePath(raw: "./.build/debug/symphony-build", workingDirectory: repoRoot).hasSuffix(".build/debug/symphony-build"))
    }
}

@Test func commitHarnessUsesDefaultCoverageLoadersForBothClientAndServer() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        let coveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
        try FileManager.default.createDirectory(at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}"#
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
        let runner = DualCoverageProcessRunner(packageCoveragePath: coveragePath.path, coverageJSON: coverageJSON)

        let report = try CommitHarness(processRunner: runner, statusSink: { _ in }).run(
            workspace: workspace,
            request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
        )

        #expect(report.clientCoverage.targets.map { $0.name } == ["Suite"])
        #expect(report.serverCoverage.targets.map { $0.name } == ["Suite"])
    }
}

@Test func commitHarnessExecuteDecodesInspectionWrappersAndRequestsInspectionFlags() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        let coveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
        try FileManager.default.createDirectory(at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}"#
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
                CoverageTargetReport(name: "Suite", buildProductPath: nil, coveredLines: 1, executableLines: 2, lineCoverage: 0.5, files: [
                    CoverageFileReport(name: "Foo.swift", path: "/tmp/Foo.swift", coveredLines: 1, executableLines: 2, lineCoverage: 0.5),
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
        let wrapperJSON = String(
            decoding: try JSONEncoder().encode(CoverageInspectionResponse(coverage: coverageReport, inspection: .normalized(inspectionReport))),
            as: UTF8.self
        )
        let runner = RecordingCoverageInspectionProcessRunner(packageCoveragePath: coveragePath.path, wrappedCoverageJSON: wrapperJSON)

        let execution = try CommitHarness(processRunner: runner, statusSink: { _ in }).execute(
            workspace: workspace,
            request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
        )

        #expect(execution.report.clientCoverage == coverageReport)
        #expect(execution.report.serverCoverage == coverageReport)
        #expect(execution.clientInspection == inspectionReport)
        #expect(execution.serverInspection == inspectionReport)
        #expect(runner.commands.contains(where: { $0.contains("--show-functions") && $0.contains("--show-missing-lines") }))

        let rawInspection = CoverageInspectionRawReport(
            backend: .swiftPM,
            product: .server,
            commands: [
                CoverageInspectionRawCommand(
                    commandLine: "xcrun llvm-cov show",
                    scope: "missing-lines",
                    filePath: "/tmp/Foo.swift",
                    format: "text",
                    output: "raw output"
                )
            ]
        )
        let rawWrapperJSON = String(
            decoding: try JSONEncoder().encode(CoverageInspectionResponse(coverage: coverageReport, inspection: .raw(rawInspection))),
            as: UTF8.self
        )
        let rawRunner = RecordingCoverageInspectionProcessRunner(packageCoveragePath: coveragePath.path, wrappedCoverageJSON: rawWrapperJSON)
        let rawExecution = try CommitHarness(processRunner: rawRunner, statusSink: { _ in }).execute(
            workspace: workspace,
            request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
        )
        #expect(rawExecution.clientInspection == nil)
        #expect(rawExecution.serverInspection == nil)
    }
}

@Test func commitHarnessHelperClosuresForwardSignalsAndFilterCoverageOutput() throws {
    let status = SignalBox()
    let harness = CommitHarness(processRunner: StubProcessRunner(), statusSink: { status.append($0) })
    let observation = harness.forwardingObservation(label: "swift test")
    observation.onStaleSignal?("stale-signal")
    observation.onLine?(.stdout, "   ")
    observation.onLine?(.stderr, "observed line")
    #expect(status.values == ["stale-signal", "observed line"])

    let coverageJSON = #"""
    {"coveredLines":4,"executableLines":4,"lineCoverage":1,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"SymphonyServer","buildProductPath":"/tmp/SymphonyServer","coveredLines":4,"executableLines":4,"lineCoverage":1,"files":[]}]}
    """#
    let runner = ObservationCoverageRunner(json: coverageJSON) { observation in
        observation?.onStaleSignal?("coverage stale")
        observation?.onLine?(.stdout, "ignore stdout")
        observation?.onLine?(.stderr, " ")
        observation?.onLine?(.stderr, "stderr line")
    }
    let report = try CommitHarness.runCoverageSuite(
        processRunner: runner,
        executablePath: "/tmp/symphony-build",
        arguments: ["coverage", "--product", "server"],
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
            _ = try GitHookInstaller(processRunner: StubProcessRunner(results: [
                "git config core.hooksPath .githooks": StubProcessRunner.failure("git broke"),
            ])).install(workspace: workspace)
            Issue.record("Expected git hook install failures to surface.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "git_hooks_install_failed")
        }

        do {
            _ = try GitHookInstaller(processRunner: StubProcessRunner(results: [
                "git config core.hooksPath .githooks": CommandResult(exitStatus: 1, stdout: "", stderr: ""),
            ])).install(workspace: workspace)
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
        _ = try protocolRunner.run(command: "echo", arguments: [], environment: [:], currentDirectory: directory)
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
            if let contents = try? String(contentsOf: detachedOutput, encoding: .utf8), contents.contains("detached") {
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

@Test func processHelpersCoverLineEmitterRemaindersAndIdleStaleSignals() {
    let silentEmitter = LineEmitter(stream: .stdout, observation: nil)
    silentEmitter.append(Data())
    silentEmitter.append(Data("ignored\n".utf8))
    silentEmitter.finish()

    let lines = SignalBox()
    let observedEmitter = LineEmitter(
        stream: .stderr,
        observation: ProcessObservation(label: "emitter", onLine: { stream, line in
            lines.append("\(stream.rawValue):\(line)")
        })
    )
    observedEmitter.append(Data("line-1\npartial".utf8))
    observedEmitter.finish()

    #expect(lines.values == ["stderr:line-1", "stderr:partial"])

    let collector = DataCollector()
    let staleSignals = SignalBox()
    let controller = StaleSignalController(
        observation: ProcessObservation(label: "idle", staleInterval: 60, onStaleSignal: { staleSignals.append($0) }),
        collector: collector
    )
    controller.signalIfNeeded()

    #expect(collector.data.isEmpty)
    #expect(staleSignals.values.isEmpty)
}

@Test func artifactManagerRecursiveFilesSkipsPlainFilesWhenEnumerationIsUnavailable() throws {
    let manager = ArtifactManager(processRunner: StubProcessRunner(), enumeratorFactory: { _ in nil })
    #expect(manager.recursiveFiles(in: [URL(fileURLWithPath: "/tmp/missing", isDirectory: true)]).isEmpty)
}

private struct CoverageCommandProcessRunner: ProcessRunning {
    let packageCoveragePath: String
    let coverageResult: CommandResult

    func run(command: String, arguments: [String], environment: [String : String], currentDirectory: URL?, observation: ProcessObservation?) throws -> CommandResult {
        if command == "swift", arguments == ["test", "--enable-code-coverage"] {
            observation?.onLine?(.stdout, "swift test passed")
            observation?.onStaleSignal?("[symphony-build] swift test still running")
            return StubProcessRunner.success()
        }
        if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
            return StubProcessRunner.success(packageCoveragePath + "\n")
        }
        if arguments.prefix(3) == ["coverage", "--product", "client"] || arguments.prefix(3) == ["coverage", "--product", "server"] {
            observation?.onLine?(.stderr, "coverage stderr")
            return coverageResult
        }
        return StubProcessRunner.success()
    }

    func startDetached(executablePath: String, arguments: [String], environment: [String : String], currentDirectory: URL?, output: URL) throws -> Int32 {
        0
    }
}

private final class ProtocolExtensionRunner: ProcessRunning, @unchecked Sendable {
    private(set) var lastObservationWasNil = false

    func run(command: String, arguments: [String], environment: [String : String], currentDirectory: URL?, observation: ProcessObservation?) throws -> CommandResult {
        lastObservationWasNil = observation == nil
        return StubProcessRunner.success()
    }

    func startDetached(executablePath: String, arguments: [String], environment: [String : String], currentDirectory: URL?, output: URL) throws -> Int32 {
        0
    }
}

private struct ObservationCoverageRunner: ProcessRunning {
    let json: String
    let observe: @Sendable (ProcessObservation?) -> Void

    func run(command: String, arguments: [String], environment: [String : String], currentDirectory: URL?, observation: ProcessObservation?) throws -> CommandResult {
        observe(observation)
        return StubProcessRunner.success(json)
    }

    func startDetached(executablePath: String, arguments: [String], environment: [String : String], currentDirectory: URL?, output: URL) throws -> Int32 {
        0
    }
}

private struct DualCoverageProcessRunner: ProcessRunning {
    let packageCoveragePath: String
    let coverageJSON: String

    func run(command: String, arguments: [String], environment: [String : String], currentDirectory: URL?, observation: ProcessObservation?) throws -> CommandResult {
        if command == "swift", arguments == ["test", "--enable-code-coverage"] {
            return StubProcessRunner.success()
        }
        if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
            return StubProcessRunner.success(packageCoveragePath + "\n")
        }
        if arguments.prefix(3) == ["coverage", "--product", "client"] || arguments.prefix(3) == ["coverage", "--product", "server"] {
            return StubProcessRunner.success(coverageJSON)
        }
        return StubProcessRunner.success()
    }

    func startDetached(executablePath: String, arguments: [String], environment: [String : String], currentDirectory: URL?, output: URL) throws -> Int32 {
        0
    }
}

private final class RecordingCoverageInspectionProcessRunner: ProcessRunning, @unchecked Sendable {
    let packageCoveragePath: String
    let wrappedCoverageJSON: String
    private let lock = NSLock()
    private var storage = [String]()

    init(packageCoveragePath: String, wrappedCoverageJSON: String) {
        self.packageCoveragePath = packageCoveragePath
        self.wrappedCoverageJSON = wrappedCoverageJSON
    }

    var commands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func run(command: String, arguments: [String], environment: [String : String], currentDirectory: URL?, observation: ProcessObservation?) throws -> CommandResult {
        let rendered = ([command] + arguments).joined(separator: " ")
        lock.lock()
        storage.append(rendered)
        lock.unlock()

        if command == "swift", arguments == ["test", "--enable-code-coverage"] {
            return StubProcessRunner.success()
        }
        if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
            return StubProcessRunner.success(packageCoveragePath + "\n")
        }
        if arguments.prefix(3) == ["coverage", "--product", "client"] || arguments.prefix(3) == ["coverage", "--product", "server"] {
            return StubProcessRunner.success(wrappedCoverageJSON)
        }
        return StubProcessRunner.success()
    }

    func startDetached(executablePath: String, arguments: [String], environment: [String : String], currentDirectory: URL?, output: URL) throws -> Int32 {
        0
    }
}
