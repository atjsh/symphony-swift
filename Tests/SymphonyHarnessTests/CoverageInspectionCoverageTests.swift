import Foundation
import Testing

@testable import SymphonyHarness

@Test func swiftPMCoverageInspectorResolvesContextAndParsesFunctionsAndMissingLines() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let codecovRoot = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov", isDirectory: true)
    let testBundleRoot = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/symphony-swiftPackageTests.xctest/Contents/MacOS",
      isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServerCore"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: testBundleRoot, withIntermediateDirectories: true)

    let coverageJSONPath = codecovRoot.appendingPathComponent("symphony-swift.json")
    let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
    let testBinaryPath = testBundleRoot.appendingPathComponent("symphony-swiftPackageTests")
    try "{}".write(to: coverageJSONPath, atomically: true, encoding: .utf8)
    try Data().write(to: profdataPath)
    try Data().write(to: testBinaryPath)

    let filePath = repoRoot.appendingPathComponent("Sources/SymphonyServerCore/Orchestrator.swift")
      .path
    let showCommand =
      "xcrun llvm-cov show -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(filePath)"
    let functionsCommand =
      "xcrun llvm-cov report --show-functions -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(filePath)"
    let inspector = SwiftPMCoverageInspector(
      processRunner: StubProcessRunner(results: [
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
          targetName: "SymphonyServerCore",
          path: "Sources/SymphonyServerCore/Orchestrator.swift",
          coveredLines: 2,
          executableLines: 4,
          lineCoverage: 0.5
        )
      ],
      includeFunctions: true,
      includeMissingLines: true
    )

    #expect(
      result.files == [
        CoverageInspectionFileReport(
          targetName: "SymphonyServerCore",
          path: "Sources/SymphonyServerCore/Orchestrator.swift",
          coveredLines: 2,
          executableLines: 4,
          lineCoverage: 0.5,
          missingLineRanges: [CoverageLineRange(startLine: 3, endLine: 4)],
          functions: [
            CoverageInspectionFunctionReport(
              name: "bootstrap()", coveredLines: 2, executableLines: 4, lineCoverage: 0.5)
          ]
        )
      ])
    #expect(result.rawCommands.map(\.scope) == ["missing-lines", "functions"])
    #expect(
      result.rawCommands.map(\.filePath) == [
        "Sources/SymphonyServerCore/Orchestrator.swift",
        "Sources/SymphonyServerCore/Orchestrator.swift",
      ])
  }
}

@Test func swiftPMCoverageInspectorSurfacesContextAndCommandFailures() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let codecovRoot = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov", isDirectory: true)
    let testBundleRoot = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/symphony-swiftPackageTests.xctest/Contents/MacOS",
      isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServerCore"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: testBundleRoot, withIntermediateDirectories: true)

    let coverageJSONPath = codecovRoot.appendingPathComponent("symphony-swift.json")
    let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
    let testBinaryPath = testBundleRoot.appendingPathComponent("symphony-swiftPackageTests")
    try "{}".write(to: coverageJSONPath, atomically: true, encoding: .utf8)

    let inspector = SwiftPMCoverageInspector(
      processRunner: StubProcessRunner(), llvmCovCommand: .xcrun)
    do {
      _ = try inspector.resolveContext(coverageJSONPath: coverageJSONPath)
      Issue.record("Expected missing SwiftPM profdata to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_swiftpm_profdata")
    }

    try Data().write(to: profdataPath)
    do {
      _ = try inspector.resolveContext(coverageJSONPath: coverageJSONPath)
      Issue.record("Expected missing SwiftPM test binary to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_swiftpm_test_binary")
    }

    try Data().write(to: testBinaryPath)
    let filePath = repoRoot.appendingPathComponent("Sources/SymphonyServerCore/Orchestrator.swift")
      .path
    let failingShowCommand =
      "xcrun llvm-cov show -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(filePath)"
    let failingInspector = SwiftPMCoverageInspector(
      processRunner: StubProcessRunner(results: [
        failingShowCommand: StubProcessRunner.failure("llvm-cov failed")
      ]), llvmCovCommand: .xcrun)

    do {
      _ = try failingInspector.inspect(
        coverageJSONPath: coverageJSONPath,
        projectRoot: repoRoot,
        candidates: [
          CoverageInspectionFileCandidate(
            targetName: "SymphonyServerCore",
            path: "Sources/SymphonyServerCore/Orchestrator.swift",
            coveredLines: 1,
            executableLines: 2,
            lineCoverage: 0.5
          )
        ],
        includeFunctions: false,
        includeMissingLines: true
      )
      Issue.record("Expected llvm-cov inspection failures to surface.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "swiftpm_coverage_inspection_failed")
      #expect(error.message.contains("llvm-cov failed"))
    }
  }
}

@Test func swiftPMCoverageInspectorSupportsLinuxStyleTestBinariesAndDirectLLVMCov() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let codecovRoot = repoRoot.appendingPathComponent(
      ".build/x86_64-unknown-linux-gnu/debug/codecov", isDirectory: true)
    let debugRoot = repoRoot.appendingPathComponent(
      ".build/x86_64-unknown-linux-gnu/debug", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServer"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: debugRoot, withIntermediateDirectories: true)

    let coverageJSONPath = codecovRoot.appendingPathComponent("symphony-swift.json")
    let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
    let testBinaryPath = debugRoot.appendingPathComponent("symphony-swiftPackageTests.xctest")
    try "{}".write(to: coverageJSONPath, atomically: true, encoding: .utf8)
    try Data().write(to: profdataPath)
    try Data().write(to: testBinaryPath)

    let filePath = repoRoot.appendingPathComponent("Sources/SymphonyServerCLI/main.swift").path
    let showCommand =
      "llvm-cov show -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(filePath)"
    let functionsCommand =
      "llvm-cov report --show-functions -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(filePath)"
    let inspector = SwiftPMCoverageInspector(
      processRunner: StubProcessRunner(results: [
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
          path: "Sources/SymphonyServerCLI/main.swift",
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
    #expect(
      result.files.first?.functions == [
        CoverageInspectionFunctionReport(
          name: "main()", coveredLines: 1, executableLines: 2, lineCoverage: 0.5)
      ])
  }
}

@Test func swiftPMCoverageInspectorSupportsDirectPackageTestsBinaryPath() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let codecovRoot = repoRoot.appendingPathComponent(
      ".build/x86_64-unknown-linux-gnu/debug/codecov", isDirectory: true)
    let debugRoot = repoRoot.appendingPathComponent(
      ".build/x86_64-unknown-linux-gnu/debug", isDirectory: true)
    try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: debugRoot, withIntermediateDirectories: true)

    let coverageJSONPath = codecovRoot.appendingPathComponent("symphony-swift.json")
    let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
    let directBinaryPath = debugRoot.appendingPathComponent("symphony-swiftPackageTests")
    try "{}".write(to: coverageJSONPath, atomically: true, encoding: .utf8)
    try Data().write(to: profdataPath)
    try Data().write(to: directBinaryPath)

    let context = try SwiftPMCoverageInspector(
      processRunner: StubProcessRunner(), llvmCovCommand: .direct
    )
    .resolveContext(coverageJSONPath: coverageJSONPath)

    #expect(context.profileDataPath == profdataPath)
    #expect(context.testBinaryPath == directBinaryPath)
  }
}

@Test func swiftPMCoverageInspectorTreatsExistingNonFileURLPathsAsRegularFiles() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let codecovRoot = repoRoot.appendingPathComponent(
      ".build/x86_64-unknown-linux-gnu/debug/codecov", isDirectory: true)
    let debugRoot = repoRoot.appendingPathComponent(
      ".build/x86_64-unknown-linux-gnu/debug", isDirectory: true)
    try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: debugRoot, withIntermediateDirectories: true)

    let coverageJSONPath = try #require(
      URL(string: "https://example.com\(codecovRoot.path)/symphony-swift.json")
    )
    let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
    let directBinaryPath = debugRoot.appendingPathComponent("symphony-swiftPackageTests")
    try "{}".write(
      to: codecovRoot.appendingPathComponent("symphony-swift.json"), atomically: true,
      encoding: .utf8)
    try Data().write(to: profdataPath)
    try Data().write(to: directBinaryPath)

    let context = try SwiftPMCoverageInspector(
      processRunner: StubProcessRunner(), llvmCovCommand: .direct
    )
    .resolveContext(coverageJSONPath: coverageJSONPath)

    #expect(context.profileDataPath.path == profdataPath.path)
    #expect(context.testBinaryPath.path == directBinaryPath.path)
  }
}

@Test func xcodeCoverageInspectorParsesFunctionsAndMissingLines() throws {
  let resultBundlePath = URL(fileURLWithPath: "/tmp/result.xcresult")
  let filePath = "/tmp/ContentView.swift"
  let archiveCommand = "xcrun xccov view --archive --file \(filePath) \(resultBundlePath.path)"
  let functionsCommand =
    "xcrun xccov view --report --functions-for-file \(filePath) \(resultBundlePath.path)"
  let inspector = XcodeCoverageInspector(
    processRunner: StubProcessRunner(results: [
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

  #expect(
    result.files == [
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
  let inspector = XcodeCoverageInspector(
    processRunner: StubProcessRunner(results: [
      archiveCommand: StubProcessRunner.failure("xccov archive failed")
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
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "xcode_coverage_archive_failed")
    #expect(error.message.contains("xccov archive failed"))
  }
}

