import Foundation
import Testing
@testable import SymphonyBuildCore

@Test func swiftPMCoverageInspectorResolvesContextAndParsesFunctionsAndMissingLines() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        let codecovRoot = repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/codecov", isDirectory: true)
        let testBundleRoot = repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/symphony-swiftPackageTests.xctest/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources/SymphonyRuntime"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: testBundleRoot, withIntermediateDirectories: true)

        let coverageJSONPath = codecovRoot.appendingPathComponent("symphony-swift.json")
        let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
        let testBinaryPath = testBundleRoot.appendingPathComponent("symphony-swiftPackageTests")
        try "{}".write(to: coverageJSONPath, atomically: true, encoding: .utf8)
        try Data().write(to: profdataPath)
        try Data().write(to: testBinaryPath)

        let filePath = repoRoot.appendingPathComponent("Sources/SymphonyRuntime/BootstrapSupport.swift").path
        let showCommand = "xcrun llvm-cov show -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(filePath)"
        let functionsCommand = "xcrun llvm-cov report --show-functions -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(filePath)"
        let inspector = SwiftPMCoverageInspector(processRunner: StubProcessRunner(results: [
            showCommand: StubProcessRunner.success(
                """
                    1|       |import Foundation
                    2|      1|func bootstrap() {
                    3|      0|    start()
                    4|      0|    finish()
                    5|      1|}
                """
            ),
            functionsCommand: StubProcessRunner.success(
                """
                File '\(filePath)':
                Name                                     Regions    Miss   Cover     Lines    Miss   Cover  Branches    Miss   Cover
                --------------------------------------------------------------------------------------------------------------------------------
                bootstrap()                                   2       1  50.00%         4       2  50.00%         0       0   0.00%
                helper()                                      1       0 100.00%         2       0 100.00%         0       0   0.00%
                --------------------------------------------------------------------------------------------------------------------------------
                TOTAL                                         3       1  66.67%         6       2  66.67%         0       0   0.00%
                """
            ),
        ]))

        let context = try inspector.resolveContext(coverageJSONPath: coverageJSONPath)
        #expect(context.profileDataPath == profdataPath)
        #expect(context.testBinaryPath == testBinaryPath)

        let result = try inspector.inspect(
            coverageJSONPath: coverageJSONPath,
            projectRoot: repoRoot,
            candidates: [
                CoverageInspectionFileCandidate(
                    targetName: "SymphonyRuntime",
                    path: "Sources/SymphonyRuntime/BootstrapSupport.swift",
                    coveredLines: 2,
                    executableLines: 4,
                    lineCoverage: 0.5
                )
            ],
            includeFunctions: true,
            includeMissingLines: true
        )

        #expect(result.files == [
            CoverageInspectionFileReport(
                targetName: "SymphonyRuntime",
                path: "Sources/SymphonyRuntime/BootstrapSupport.swift",
                coveredLines: 2,
                executableLines: 4,
                lineCoverage: 0.5,
                missingLineRanges: [CoverageLineRange(startLine: 3, endLine: 4)],
                functions: [
                    CoverageInspectionFunctionReport(name: "bootstrap()", coveredLines: 2, executableLines: 4, lineCoverage: 0.5)
                ]
            )
        ])
        #expect(result.rawCommands.map(\.scope) == ["missing-lines", "functions"])
        #expect(result.rawCommands.map(\.filePath) == ["Sources/SymphonyRuntime/BootstrapSupport.swift", "Sources/SymphonyRuntime/BootstrapSupport.swift"])
    }
}

@Test func swiftPMCoverageInspectorSurfacesContextAndCommandFailures() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        let codecovRoot = repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/codecov", isDirectory: true)
        let testBundleRoot = repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/symphony-swiftPackageTests.xctest/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources/SymphonyRuntime"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: testBundleRoot, withIntermediateDirectories: true)

        let coverageJSONPath = codecovRoot.appendingPathComponent("symphony-swift.json")
        let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
        let testBinaryPath = testBundleRoot.appendingPathComponent("symphony-swiftPackageTests")
        try "{}".write(to: coverageJSONPath, atomically: true, encoding: .utf8)

        let inspector = SwiftPMCoverageInspector(processRunner: StubProcessRunner())
        do {
            _ = try inspector.resolveContext(coverageJSONPath: coverageJSONPath)
            Issue.record("Expected missing SwiftPM profdata to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "missing_swiftpm_profdata")
        }

        try Data().write(to: profdataPath)
        do {
            _ = try inspector.resolveContext(coverageJSONPath: coverageJSONPath)
            Issue.record("Expected missing SwiftPM test binary to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "missing_swiftpm_test_binary")
        }

        try Data().write(to: testBinaryPath)
        let filePath = repoRoot.appendingPathComponent("Sources/SymphonyRuntime/BootstrapSupport.swift").path
        let failingShowCommand = "xcrun llvm-cov show -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(filePath)"
        let failingInspector = SwiftPMCoverageInspector(processRunner: StubProcessRunner(results: [
            failingShowCommand: StubProcessRunner.failure("llvm-cov failed"),
        ]))

        do {
            _ = try failingInspector.inspect(
                coverageJSONPath: coverageJSONPath,
                projectRoot: repoRoot,
                candidates: [
                    CoverageInspectionFileCandidate(
                        targetName: "SymphonyRuntime",
                        path: "Sources/SymphonyRuntime/BootstrapSupport.swift",
                        coveredLines: 1,
                        executableLines: 2,
                        lineCoverage: 0.5
                    )
                ],
                includeFunctions: false,
                includeMissingLines: true
            )
            Issue.record("Expected llvm-cov inspection failures to surface.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "swiftpm_coverage_inspection_failed")
            #expect(error.message.contains("llvm-cov failed"))
        }
    }
}

@Test func xcodeCoverageInspectorParsesFunctionsAndMissingLines() throws {
    let resultBundlePath = URL(fileURLWithPath: "/tmp/result.xcresult")
    let filePath = "/tmp/ContentView.swift"
    let archiveCommand = "xcrun xccov view --archive --file \(filePath) \(resultBundlePath.path)"
    let functionsCommand = "xcrun xccov view --report --functions-for-file \(filePath) \(resultBundlePath.path)"
    let inspector = XcodeCoverageInspector(processRunner: StubProcessRunner(results: [
        archiveCommand: StubProcessRunner.success(
            """
             1: *
             2: 3
             3: 0
             4: 0
             5: 1
             6: 0
            """
        ),
        functionsCommand: StubProcessRunner.success(
            """
            \(filePath):
            ID Name                                  Range   Coverage
            -- ------------------------------------- ------- ---------------
            0  ContentView.body.getter               {7, 19} 100.00% (19/19)
            1  closure #1 in ContentView.body.getter {8, 15} 50.00% (3/6)
            """
        ),
    ]))

    let result = try inspector.inspect(
        resultBundlePath: resultBundlePath,
        candidates: [
            CoverageInspectionFileCandidate(
                targetName: "Symphony",
                path: filePath,
                coveredLines: 4,
                executableLines: 7,
                lineCoverage: 4.0 / 7.0
            )
        ],
        includeFunctions: true,
        includeMissingLines: true
    )

    #expect(result.files == [
        CoverageInspectionFileReport(
            targetName: "Symphony",
            path: filePath,
            coveredLines: 4,
            executableLines: 7,
            lineCoverage: 4.0 / 7.0,
            missingLineRanges: [
                CoverageLineRange(startLine: 3, endLine: 4),
                CoverageLineRange(startLine: 6, endLine: 6),
            ],
            functions: [
                CoverageInspectionFunctionReport(
                    name: "closure #1 in ContentView.body.getter",
                    coveredLines: 3,
                    executableLines: 6,
                    lineCoverage: 0.5
                )
            ]
        )
    ])
    #expect(result.rawCommands.map(\.scope) == ["missing-lines", "functions"])
}

@Test func xcodeCoverageInspectorSurfacesArchiveFailures() throws {
    let resultBundlePath = URL(fileURLWithPath: "/tmp/result.xcresult")
    let filePath = "/tmp/ContentView.swift"
    let archiveCommand = "xcrun xccov view --archive --file \(filePath) \(resultBundlePath.path)"
    let inspector = XcodeCoverageInspector(processRunner: StubProcessRunner(results: [
        archiveCommand: StubProcessRunner.failure("xccov archive failed"),
    ]))

    do {
        _ = try inspector.inspect(
            resultBundlePath: resultBundlePath,
            candidates: [
                CoverageInspectionFileCandidate(
                    targetName: "Symphony",
                    path: filePath,
                    coveredLines: 1,
                    executableLines: 2,
                    lineCoverage: 0.5
                )
            ],
            includeFunctions: false,
            includeMissingLines: true
        )
        Issue.record("Expected xccov archive failures to surface.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "xcode_coverage_archive_failed")
        #expect(error.message.contains("xccov archive failed"))
    }
}

@Test func coverageInspectionUtilitiesCoverFallbackBranchesAndRenderingHelpers() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        let codecovRoot = repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/codecov", isDirectory: true)
        let fallbackBundleRoot = repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/FallbackPackageTests.xctest/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources/SymphonyRuntime"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fallbackBundleRoot, withIntermediateDirectories: true)

        let coverageJSONPath = codecovRoot.appendingPathComponent("symphony-swift.json")
        let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
        let fallbackBinaryPath = fallbackBundleRoot.appendingPathComponent("FallbackPackageTests")
        try "{}".write(to: coverageJSONPath, atomically: true, encoding: .utf8)
        try Data().write(to: profdataPath)
        try Data().write(to: fallbackBinaryPath)

        let resolvedRepoRoot = repoRoot.resolvingSymlinksInPath()
        let inspector = SwiftPMCoverageInspector(processRunner: StubProcessRunner())
        let context = try inspector.resolveContext(coverageJSONPath: coverageJSONPath)
        #expect(context.testBinaryPath.lastPathComponent == fallbackBinaryPath.lastPathComponent)

        let emptyInspection = try inspector.inspect(
            coverageJSONPath: coverageJSONPath,
            projectRoot: repoRoot,
            candidates: [],
            includeFunctions: true,
            includeMissingLines: true
        )
        #expect(emptyInspection.files.isEmpty)
        #expect(emptyInspection.rawCommands.isEmpty)

        let absolutePath = directory.appendingPathComponent("External.swift").path
        let noDetails = try inspector.inspect(
            coverageJSONPath: coverageJSONPath,
            projectRoot: repoRoot,
            candidates: [
                CoverageInspectionFileCandidate(
                    targetName: "External",
                    path: absolutePath,
                    coveredLines: 1,
                    executableLines: 2,
                    lineCoverage: 0.5
                )
            ],
            includeFunctions: false,
            includeMissingLines: false
        )
        #expect(noDetails.files == [
            CoverageInspectionFileReport(
                targetName: "External",
                path: absolutePath,
                coveredLines: 1,
                executableLines: 2,
                lineCoverage: 0.5,
                missingLineRanges: [],
                functions: []
            )
        ])
        #expect(noDetails.rawCommands.isEmpty)

        let relativePath = "Sources/SymphonyRuntime/BootstrapSupport.swift"
        let resolvedRelativePath = resolvedRepoRoot.appendingPathComponent(relativePath).path
        let failingShowCommand = "xcrun llvm-cov show -instr-profile \(context.profileDataPath.path) \(context.testBinaryPath.path) \(resolvedRelativePath)"
        do {
            _ = try SwiftPMCoverageInspector(processRunner: StubProcessRunner(results: [
                failingShowCommand: CommandResult(exitStatus: 1, stdout: "", stderr: ""),
            ])).inspect(
                coverageJSONPath: coverageJSONPath,
                projectRoot: repoRoot,
                candidates: [
                    CoverageInspectionFileCandidate(
                        targetName: "SymphonyRuntime",
                        path: relativePath,
                        coveredLines: 1,
                        executableLines: 2,
                        lineCoverage: 0.5
                    )
                ],
                includeFunctions: false,
                includeMissingLines: true
            )
            Issue.record("Expected empty llvm-cov missing-line failures to use the fallback message.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "swiftpm_coverage_inspection_failed")
            #expect(error.message == "Failed to inspect SwiftPM missing lines for Sources/SymphonyRuntime/BootstrapSupport.swift.")
        }

        let failingFunctionsCommand = "xcrun llvm-cov report --show-functions -instr-profile \(context.profileDataPath.path) \(context.testBinaryPath.path) \(resolvedRelativePath)"
        do {
            _ = try SwiftPMCoverageInspector(processRunner: StubProcessRunner(results: [
                failingFunctionsCommand: StubProcessRunner.failure("llvm-cov report failed"),
            ])).inspect(
                coverageJSONPath: coverageJSONPath,
                projectRoot: repoRoot,
                candidates: [
                    CoverageInspectionFileCandidate(
                        targetName: "SymphonyRuntime",
                        path: relativePath,
                        coveredLines: 1,
                        executableLines: 2,
                        lineCoverage: 0.5
                    )
                ],
                includeFunctions: true,
                includeMissingLines: false
            )
            Issue.record("Expected llvm-cov function failures to surface.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "swiftpm_coverage_inspection_failed")
            #expect(error.message.contains("llvm-cov report failed"))
        }

        do {
            _ = try SwiftPMCoverageInspector(processRunner: StubProcessRunner(results: [
                failingFunctionsCommand: CommandResult(exitStatus: 1, stdout: "", stderr: ""),
            ])).inspect(
                coverageJSONPath: coverageJSONPath,
                projectRoot: repoRoot,
                candidates: [
                    CoverageInspectionFileCandidate(
                        targetName: "SymphonyRuntime",
                        path: relativePath,
                        coveredLines: 1,
                        executableLines: 2,
                        lineCoverage: 0.5
                    )
                ],
                includeFunctions: true,
                includeMissingLines: false
            )
            Issue.record("Expected empty llvm-cov function failures to use the fallback message.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "swiftpm_coverage_inspection_failed")
            #expect(error.message == "Failed to inspect SwiftPM functions for Sources/SymphonyRuntime/BootstrapSupport.swift.")
        }
    }

    let xcodeInspector = XcodeCoverageInspector(processRunner: StubProcessRunner())
    let emptyXcodeInspection = try xcodeInspector.inspect(
        resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
        candidates: [],
        includeFunctions: true,
        includeMissingLines: true
    )
    #expect(emptyXcodeInspection.files.isEmpty)
    #expect(emptyXcodeInspection.rawCommands.isEmpty)

    let noDetailXcodeInspection = try xcodeInspector.inspect(
        resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
        candidates: [
            CoverageInspectionFileCandidate(
                targetName: "Symphony",
                path: "/tmp/ContentView.swift",
                coveredLines: 2,
                executableLines: 4,
                lineCoverage: 0.5
            )
        ],
        includeFunctions: false,
        includeMissingLines: false
    )
    #expect(noDetailXcodeInspection.files == [
        CoverageInspectionFileReport(
            targetName: "Symphony",
            path: "/tmp/ContentView.swift",
            coveredLines: 2,
            executableLines: 4,
            lineCoverage: 0.5,
            missingLineRanges: [],
            functions: []
        )
    ])

    let xcodeFunctionsCommand = "xcrun xccov view --report --functions-for-file /tmp/ContentView.swift /tmp/result.xcresult"
    do {
        _ = try XcodeCoverageInspector(processRunner: StubProcessRunner(results: [
            xcodeFunctionsCommand: CommandResult(exitStatus: 1, stdout: "", stderr: ""),
        ])).inspect(
            resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
            candidates: [
                CoverageInspectionFileCandidate(
                    targetName: "Symphony",
                    path: "/tmp/ContentView.swift",
                    coveredLines: 1,
                    executableLines: 2,
                    lineCoverage: 0.5
                )
            ],
            includeFunctions: true,
            includeMissingLines: false
        )
        Issue.record("Expected empty xccov function failures to use the fallback message.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "xcode_coverage_functions_failed")
        #expect(error.message == "Failed to inspect Xcode functions for /tmp/ContentView.swift.")
    }

    do {
        _ = try XcodeCoverageInspector(processRunner: StubProcessRunner(results: [
            xcodeFunctionsCommand: StubProcessRunner.failure("xccov functions failed"),
        ])).inspect(
            resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
            candidates: [
                CoverageInspectionFileCandidate(
                    targetName: "Symphony",
                    path: "/tmp/ContentView.swift",
                    coveredLines: 1,
                    executableLines: 2,
                    lineCoverage: 0.5
                )
            ],
            includeFunctions: true,
            includeMissingLines: false
        )
        Issue.record("Expected non-empty xccov function failures to surface.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "xcode_coverage_functions_failed")
        #expect(error.message.contains("xccov functions failed"))
    }

    let xcodeArchiveCommand = "xcrun xccov view --archive --file /tmp/ContentView.swift /tmp/result.xcresult"
    do {
        _ = try XcodeCoverageInspector(processRunner: StubProcessRunner(results: [
            xcodeArchiveCommand: CommandResult(exitStatus: 1, stdout: "", stderr: ""),
        ])).inspect(
            resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
            candidates: [
                CoverageInspectionFileCandidate(
                    targetName: "Symphony",
                    path: "/tmp/ContentView.swift",
                    coveredLines: 1,
                    executableLines: 2,
                    lineCoverage: 0.5
                )
            ],
            includeFunctions: false,
            includeMissingLines: true
        )
        Issue.record("Expected empty xccov archive failures to use the fallback message.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "xcode_coverage_archive_failed")
        #expect(error.message == "Failed to inspect Xcode missing lines for /tmp/ContentView.swift.")
    }

    let candidateReport = CoverageReport(
        coveredLines: 3,
        executableLines: 6,
        lineCoverage: 0.5,
        includeTestTargets: false,
        excludedTargets: [],
        targets: [
            CoverageTargetReport(name: "NoFiles", buildProductPath: nil, coveredLines: 0, executableLines: 0, lineCoverage: 0, files: nil),
            CoverageTargetReport(
                name: "SymphonyRuntime",
                buildProductPath: nil,
                coveredLines: 3,
                executableLines: 6,
                lineCoverage: 0.5,
                files: [
                    CoverageFileReport(name: "Covered.swift", path: "/tmp/Covered.swift", coveredLines: 2, executableLines: 2, lineCoverage: 1),
                    CoverageFileReport(name: "Partial.swift", path: "/tmp/Partial.swift", coveredLines: 1, executableLines: 4, lineCoverage: 0.25),
                ]
            ),
        ]
    )
    #expect(inspectionCandidates(from: candidateReport) == [
        CoverageInspectionFileCandidate(
            targetName: "SymphonyRuntime",
            path: "/tmp/Partial.swift",
            coveredLines: 1,
            executableLines: 4,
            lineCoverage: 0.25
        )
    ])
    #expect(SwiftPMCoverageInspector.parseAnnotatedMissingLineRanges(output: "ignored", separator: "?").isEmpty)
    #expect(SwiftPMCoverageInspector.collapsedRanges(for: []).isEmpty)
    #expect(renderRawInspectionHuman(report: CoverageInspectionRawReport(
        backend: .swiftPM,
        product: .server,
        commands: [
            CoverageInspectionRawCommand(
                commandLine: "xcrun llvm-cov show",
                scope: "missing-lines",
                filePath: nil,
                format: "text",
                output: ""
            )
        ]
    )).contains("<all-files>"))
    #expect(renderRawInspectionHuman(report: CoverageInspectionRawReport(
        backend: .swiftPM,
        product: .server,
        commands: [
            CoverageInspectionRawCommand(
                commandLine: "xcrun llvm-cov show",
                scope: "missing-lines",
                filePath: nil,
                format: "text",
                output: ""
            )
        ]
    )).contains("<empty>"))
    #expect(renderMissingLineRanges([
        CoverageLineRange(startLine: 3, endLine: 3),
        CoverageLineRange(startLine: 5, endLine: 6),
    ]) == "3,5-6")
}
