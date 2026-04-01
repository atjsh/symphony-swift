import Foundation
import Testing

@testable import SymphonyHarness

@Test func coverageInspectionUtilitiesCoverFallbackBranchesAndRenderingHelpers() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let codecovRoot = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov", isDirectory: true)
    let fallbackBundleRoot = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/FallbackPackageTests.xctest/Contents/MacOS",
      isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/SymphonyServerCore"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: fallbackBundleRoot, withIntermediateDirectories: true)

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
    #expect(
      noDetails.files == [
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

    let relativePath = "Sources/SymphonyServerCore/Orchestrator.swift"
    let resolvedRelativePath = resolvedRepoRoot.appendingPathComponent(relativePath).path
    let failingShowCommand =
      "xcrun llvm-cov show -instr-profile \(context.profileDataPath.path) \(context.testBinaryPath.path) \(resolvedRelativePath)"
    do {
      _ = try SwiftPMCoverageInspector(
        processRunner: StubProcessRunner(results: [
          failingShowCommand: CommandResult(exitStatus: 1, stdout: "", stderr: "")
        ])
      ).inspect(
        coverageJSONPath: coverageJSONPath,
        projectRoot: repoRoot,
        candidates: [
          CoverageInspectionFileCandidate(
            targetName: "SymphonyServerCore",
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
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "swiftpm_coverage_inspection_failed")
      #expect(
        error.message
          == "Failed to inspect SwiftPM missing lines for Sources/SymphonyServerCore/Orchestrator.swift."
      )
    }

    let failingFunctionsCommand =
      "xcrun llvm-cov report --show-functions -instr-profile \(context.profileDataPath.path) \(context.testBinaryPath.path) \(resolvedRelativePath)"
    do {
      _ = try SwiftPMCoverageInspector(
        processRunner: StubProcessRunner(results: [
          failingFunctionsCommand: StubProcessRunner.failure("llvm-cov report failed")
        ])
      ).inspect(
        coverageJSONPath: coverageJSONPath,
        projectRoot: repoRoot,
        candidates: [
          CoverageInspectionFileCandidate(
            targetName: "SymphonyServerCore",
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
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "swiftpm_coverage_inspection_failed")
      #expect(error.message.contains("llvm-cov report failed"))
    }

    do {
      _ = try SwiftPMCoverageInspector(
        processRunner: StubProcessRunner(results: [
          failingFunctionsCommand: CommandResult(exitStatus: 1, stdout: "", stderr: "")
        ])
      ).inspect(
        coverageJSONPath: coverageJSONPath,
        projectRoot: repoRoot,
        candidates: [
          CoverageInspectionFileCandidate(
            targetName: "SymphonyServerCore",
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
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "swiftpm_coverage_inspection_failed")
      #expect(
        error.message
          == "Failed to inspect SwiftPM functions for Sources/SymphonyServerCore/Orchestrator.swift."
      )
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
  #expect(
    noDetailXcodeInspection.files == [
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

  let xcodeFunctionsCommand =
    "xcrun xccov view --report --functions-for-file /tmp/ContentView.swift /tmp/result.xcresult"
  do {
    _ = try XcodeCoverageInspector(
      processRunner: StubProcessRunner(results: [
        xcodeFunctionsCommand: CommandResult(exitStatus: 1, stdout: "", stderr: "")
      ])
    ).inspect(
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
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "xcode_coverage_functions_failed")
    #expect(error.message == "Failed to inspect Xcode functions for /tmp/ContentView.swift.")
  }

  do {
    _ = try XcodeCoverageInspector(
      processRunner: StubProcessRunner(results: [
        xcodeFunctionsCommand: StubProcessRunner.failure("xccov functions failed")
      ])
    ).inspect(
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
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "xcode_coverage_functions_failed")
    #expect(error.message.contains("xccov functions failed"))
  }

  let xcodeArchiveCommand =
    "xcrun xccov view --archive --file /tmp/ContentView.swift /tmp/result.xcresult"
  do {
    _ = try XcodeCoverageInspector(
      processRunner: StubProcessRunner(results: [
        xcodeArchiveCommand: CommandResult(exitStatus: 1, stdout: "", stderr: "")
      ])
    ).inspect(
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
  } catch let error as SymphonyHarnessError {
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
      CoverageTargetReport(
        name: "NoFiles", buildProductPath: nil, coveredLines: 0, executableLines: 0,
        lineCoverage: 0, files: nil),
      CoverageTargetReport(
        name: "SymphonyServerCore",
        buildProductPath: nil,
        coveredLines: 3,
        executableLines: 6,
        lineCoverage: 0.5,
        files: [
          CoverageFileReport(
            name: "Covered.swift", path: "/tmp/Covered.swift", coveredLines: 2, executableLines: 2,
            lineCoverage: 1),
          CoverageFileReport(
            name: "Partial.swift", path: "/tmp/Partial.swift", coveredLines: 1, executableLines: 4,
            lineCoverage: 0.25),
        ]
      ),
    ]
  )
  #expect(
    inspectionCandidates(from: candidateReport) == [
      CoverageInspectionFileCandidate(
        targetName: "SymphonyServerCore",
        path: "/tmp/Partial.swift",
        coveredLines: 1,
        executableLines: 4,
        lineCoverage: 0.25
      )
    ])
  #expect(
    SwiftPMCoverageInspector.parseAnnotatedMissingLineRanges(output: "ignored", separator: "?")
      .isEmpty)
  #expect(SwiftPMCoverageInspector.collapsedRanges(for: []).isEmpty)
  #expect(
    renderRawInspectionHuman(
      report: CoverageInspectionRawReport(
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
      )
    ).contains("<all-files>"))
  #expect(
    renderRawInspectionHuman(
      report: CoverageInspectionRawReport(
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
      )
    ).contains("<empty>"))
  #expect(
    renderMissingLineRanges([
      CoverageLineRange(startLine: 3, endLine: 3),
      CoverageLineRange(startLine: 5, endLine: 6),
    ]) == "3,5-6")
}

