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
        ]), llvmCovCommand: .xcrun)

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

        let inspector = SwiftPMCoverageInspector(processRunner: StubProcessRunner(), llvmCovCommand: .xcrun)
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
        ]), llvmCovCommand: .xcrun)

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

@Test func swiftPMCoverageInspectorSupportsLinuxStyleTestBinariesAndDirectLLVMCov() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        let codecovRoot = repoRoot.appendingPathComponent(".build/x86_64-unknown-linux-gnu/debug/codecov", isDirectory: true)
        let debugRoot = repoRoot.appendingPathComponent(".build/x86_64-unknown-linux-gnu/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources/SymphonyServer"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: debugRoot, withIntermediateDirectories: true)

        let coverageJSONPath = codecovRoot.appendingPathComponent("symphony-swift.json")
        let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
        let testBinaryPath = debugRoot.appendingPathComponent("symphony-swiftPackageTests.xctest")
        try "{}".write(to: coverageJSONPath, atomically: true, encoding: .utf8)
        try Data().write(to: profdataPath)
        try Data().write(to: testBinaryPath)

        let filePath = repoRoot.appendingPathComponent("Sources/SymphonyServer/main.swift").path
        let showCommand = "llvm-cov show -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(filePath)"
        let functionsCommand = "llvm-cov report --show-functions -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(filePath)"
        let inspector = SwiftPMCoverageInspector(processRunner: StubProcessRunner(results: [
            showCommand: StubProcessRunner.success(
                """
                    1|      1|func main() {
                    2|      0|    uncovered()
                    3|      1|}
                """
            ),
            functionsCommand: StubProcessRunner.success(
                """
                File '\(filePath)':
                Name                                     Regions    Miss   Cover     Lines    Miss   Cover  Branches    Miss   Cover
                --------------------------------------------------------------------------------------------------------------------------------
                main()                                        2       1  50.00%         2       1  50.00%         0       0   0.00%
                --------------------------------------------------------------------------------------------------------------------------------
                TOTAL                                         2       1  50.00%         2       1  50.00%         0       0   0.00%
                """
            ),
        ]), llvmCovCommand: .direct)

        let context = try inspector.resolveContext(coverageJSONPath: coverageJSONPath)
        #expect(context.profileDataPath == profdataPath)
        #expect(context.testBinaryPath == testBinaryPath)

        let result = try inspector.inspect(
            coverageJSONPath: coverageJSONPath,
            projectRoot: repoRoot,
            candidates: [
                CoverageInspectionFileCandidate(
                    targetName: "SymphonyServer",
                    path: "Sources/SymphonyServer/main.swift",
                    coveredLines: 1,
                    executableLines: 2,
                    lineCoverage: 0.5
                )
            ],
            includeFunctions: true,
            includeMissingLines: true
        )

        #expect(result.rawCommands.map(\.commandLine) == [showCommand, functionsCommand])
        #expect(result.files.first?.missingLineRanges == [CoverageLineRange(startLine: 2, endLine: 2)])
        #expect(result.files.first?.functions == [
            CoverageInspectionFunctionReport(name: "main()", coveredLines: 1, executableLines: 2, lineCoverage: 0.5)
        ])
    }
}

@Test func swiftPMCoverageInspectorSupportsDirectPackageTestsBinaryPath() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        let codecovRoot = repoRoot.appendingPathComponent(".build/x86_64-unknown-linux-gnu/debug/codecov", isDirectory: true)
        let debugRoot = repoRoot.appendingPathComponent(".build/x86_64-unknown-linux-gnu/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: debugRoot, withIntermediateDirectories: true)

        let coverageJSONPath = codecovRoot.appendingPathComponent("symphony-swift.json")
        let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
        let directBinaryPath = debugRoot.appendingPathComponent("symphony-swiftPackageTests")
        try "{}".write(to: coverageJSONPath, atomically: true, encoding: .utf8)
        try Data().write(to: profdataPath)
        try Data().write(to: directBinaryPath)

        let context = try SwiftPMCoverageInspector(processRunner: StubProcessRunner(), llvmCovCommand: .direct)
            .resolveContext(coverageJSONPath: coverageJSONPath)

        #expect(context.profileDataPath == profdataPath)
        #expect(context.testBinaryPath == directBinaryPath)
    }
}

@Test func swiftPMCoverageInspectorTreatsExistingNonFileURLPathsAsRegularFiles() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        let codecovRoot = repoRoot.appendingPathComponent(".build/x86_64-unknown-linux-gnu/debug/codecov", isDirectory: true)
        let debugRoot = repoRoot.appendingPathComponent(".build/x86_64-unknown-linux-gnu/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: debugRoot, withIntermediateDirectories: true)

        let coverageJSONPath = try #require(
            URL(string: "https://example.com\(codecovRoot.path)/symphony-swift.json")
        )
        let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
        let directBinaryPath = debugRoot.appendingPathComponent("symphony-swiftPackageTests")
        try "{}".write(to: codecovRoot.appendingPathComponent("symphony-swift.json"), atomically: true, encoding: .utf8)
        try Data().write(to: profdataPath)
        try Data().write(to: directBinaryPath)

        let context = try SwiftPMCoverageInspector(processRunner: StubProcessRunner(), llvmCovCommand: .direct)
            .resolveContext(coverageJSONPath: coverageJSONPath)

        #expect(context.profileDataPath.path == profdataPath.path)
        #expect(context.testBinaryPath.path == directBinaryPath.path)
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

@Test func coverageInspectionHelpersCoverFormattingAndEmptyXcodeInspectionBranches() throws {
    let candidate = CoverageInspectionFileCandidate(
        targetName: "SymphonyRuntime",
        path: "/tmp/BootstrapSupport.swift",
        coveredLines: 1,
        executableLines: 2,
        lineCoverage: 0.5
    )
    #expect(candidate.targetName == "SymphonyRuntime")

    let context = SwiftPMCoverageContext(
        profileDataPath: URL(fileURLWithPath: "/tmp/default.profdata"),
        testBinaryPath: URL(fileURLWithPath: "/tmp/SymphonyPackageTests")
    )
    #expect(context.testBinaryPath.lastPathComponent == "SymphonyPackageTests")

    let emptyResult = CoverageInspectionResult(files: [], rawCommands: [])
    #expect(emptyResult.files.isEmpty)

    let skippedArtifact = HarnessCoverageInspectionArtifact(
        suite: "client",
        backend: .xcode,
        generatedAt: "2026-03-25T00:00:00Z",
        files: [],
        skippedReason: "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
    )
    let skippedHuman = renderHarnessInspectionHuman(artifact: skippedArtifact)
    #expect(skippedHuman.contains("client inspection backend xcode"))
    #expect(skippedHuman.contains("skipped not supported because the current environment has no Xcode available; Editing those sources is not encouraged"))

    #expect(SwiftPMCoverageInspector.collapsedRanges(for: [7, 8, 10, 10, 11]) == [
        CoverageLineRange(startLine: 7, endLine: 8),
        CoverageLineRange(startLine: 10, endLine: 11),
    ])

    let xcodeInspector = XcodeCoverageInspector(processRunner: StubProcessRunner())
    let emptyXcodeInspection = try xcodeInspector.inspect(
        resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
        candidates: [],
        includeFunctions: true,
        includeMissingLines: true
    )
    #expect(emptyXcodeInspection == CoverageInspectionResult(files: [], rawCommands: []))
    #expect(xcodeInspector.renderedMissingLinesCommandLine(
        resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
        filePath: "/tmp/ContentView.swift"
    ).contains("xccov view --archive --file /tmp/ContentView.swift /tmp/result.xcresult"))
    #expect(xcodeInspector.renderedFunctionsCommandLine(
        resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
        filePath: "/tmp/ContentView.swift"
    ).contains("xccov view --report --functions-for-file /tmp/ContentView.swift /tmp/result.xcresult"))

    #expect(XcodeCoverageInspector.parseXcodeFunctions(
        output: """
        /tmp/ContentView.swift:
        ID Name                                  Range   Coverage
        -- ------------------------------------- ------- ---------------
        0  fullyCovered()                        {1, 1} 100.00% (1/1)
        1  zeroLines()                           {2, 0} 0.00% (0/0)
        """
    ).isEmpty)

    let stripped = strippedCoverageReport(CoverageReport(
        coveredLines: 2,
        executableLines: 4,
        lineCoverage: 0.5,
        includeTestTargets: false,
        excludedTargets: [],
        targets: [
            CoverageTargetReport(
                name: "SymphonyRuntime",
                buildProductPath: "/tmp/SymphonyRuntime",
                coveredLines: 2,
                executableLines: 4,
                lineCoverage: 0.5,
                files: [
                    CoverageFileReport(
                        name: "BootstrapSupport.swift",
                        path: "/tmp/BootstrapSupport.swift",
                        coveredLines: 2,
                        executableLines: 4,
                        lineCoverage: 0.5
                    )
                ]
            )
        ]
    ))
    #expect(stripped.targets.first?.files == nil)
    #expect(inspectionCandidates(from: CoverageReport(
        coveredLines: 2,
        executableLines: 2,
        lineCoverage: 1,
        includeTestTargets: false,
        excludedTargets: [],
        targets: [
            CoverageTargetReport(
                name: "SymphonyRuntime",
                buildProductPath: nil,
                coveredLines: 2,
                executableLines: 2,
                lineCoverage: 1,
                files: [
                    CoverageFileReport(
                        name: "BootstrapSupport.swift",
                        path: "/tmp/BootstrapSupport.swift",
                        coveredLines: 2,
                        executableLines: 2,
                        lineCoverage: 1
                    ),
                    CoverageFileReport(
                        name: "Generated.swift",
                        path: "/tmp/Generated.swift",
                        coveredLines: 0,
                        executableLines: 0,
                        lineCoverage: 0
                    )
                ]
            )
        ]
    )).isEmpty)

    let inspectionHuman = renderInspectionHuman(report: CoverageInspectionReport(
        backend: .swiftPM,
        product: .server,
        generatedAt: "2026-03-25T00:00:00Z",
        files: [
            CoverageInspectionFileReport(
                targetName: "SymphonyRuntime",
                path: "Sources/SymphonyRuntime/BootstrapSupport.swift",
                coveredLines: 2,
                executableLines: 4,
                lineCoverage: 0.5,
                missingLineRanges: [],
                functions: []
            )
        ]
    ))
    #expect(inspectionHuman.contains("inspection backend swiftPM"))
    #expect(try encodePrettyJSON(skippedArtifact).contains("\n"))
}

@Test func coverageInspectionRenderingCoversFunctionAndMissingLineBranches() {
    let fileReport = CoverageInspectionFileReport(
        targetName: "SymphonyRuntime",
        path: "Sources/SymphonyRuntime/BootstrapSupport.swift",
        coveredLines: 2,
        executableLines: 4,
        lineCoverage: 0.5,
        missingLineRanges: [CoverageLineRange(startLine: 3, endLine: 4)],
        functions: [
            CoverageInspectionFunctionReport(
                name: "bootstrap()",
                coveredLines: 2,
                executableLines: 4,
                lineCoverage: 0.5
            )
        ]
    )

    let inspectionHuman = renderInspectionHuman(report: CoverageInspectionReport(
        backend: .swiftPM,
        product: .server,
        generatedAt: "2026-03-25T00:00:00Z",
        files: [fileReport]
    ))
    #expect(inspectionHuman.contains("missing_lines 3-4"))
    #expect(inspectionHuman.contains("function bootstrap() 50.00% (2/4)"))

    let harnessHuman = renderHarnessInspectionHuman(artifact: HarnessCoverageInspectionArtifact(
        suite: "server",
        backend: .swiftPM,
        generatedAt: "2026-03-25T00:00:00Z",
        files: [fileReport]
    ))
    #expect(harnessHuman.contains("server inspection backend swiftPM"))
    #expect(harnessHuman.contains("missing_lines 3-4"))
    #expect(harnessHuman.contains("function bootstrap() 50.00% (2/4)"))

    let rawHuman = renderRawInspectionHuman(report: CoverageInspectionRawReport(
        backend: .swiftPM,
        product: .server,
        commands: [
            CoverageInspectionRawCommand(
                commandLine: "llvm-cov show",
                scope: "missing-lines",
                filePath: "Sources/SymphonyRuntime/BootstrapSupport.swift",
                format: "text",
                output: "annotated output"
            )
        ]
    ))
    #expect(rawHuman.contains("annotated output"))
}

@Test func swiftPMCoverageInspectorRequiresAvailableLLVMCovCommandWhenInspectionIsRequested() throws {
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

        let inspector = SwiftPMCoverageInspector(processRunner: StubProcessRunner(results: [
            "which xcrun": StubProcessRunner.failure(""),
            "which llvm-cov": StubProcessRunner.failure(""),
        ]))
        do {
            _ = try inspector.inspect(
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
            Issue.record("Expected missing llvm-cov tooling to fail SwiftPM inspection.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "missing_llvm_cov")
        }
    }
}
