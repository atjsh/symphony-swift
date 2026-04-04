import Foundation
import Testing

@testable import SymphonyHarness

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
      coveragePathInvocation: "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path",
      packageCoverage: packageReport,
      clientCoverageInvocation: nil,
      clientCoverage: nil,
      serverCoverageInvocation: "server",
      serverCoverage: serverCoverage,
      packageFileViolations: [
        HarnessCoverageViolation(
          suite: "package", kind: "file", name: "Sources/Foo.swift",
          coveredLines: 9, executableLines: 10, lineCoverage: 0.9,
          uncoveredFunctions: ["reconcile()", "tick()"],
          missingLineRanges: [CoverageLineRange(startLine: 12, endLine: 14)])
      ],
      clientTargetViolations: [],
      clientFileViolations: [],
      serverTargetViolations: [],
      serverFileViolations: []
    )
  )
  #expect(human.contains("package file Sources/Foo.swift 90.00% (9/10)"))
  #expect(human.contains("  missing_lines 12-14"))
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
      coveragePathInvocation: "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path",
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

@Test
func commitHarnessExecuteInspectsPackageViolationsBeforeCoverageLoadersRewriteSwiftPMArtifacts()
  throws
{
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let codecovRoot = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov", isDirectory: true)
    let testBundleRoot = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/symphony-swiftPackageTests.xctest/Contents/MacOS",
      isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/Foo", isDirectory: true),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: testBundleRoot, withIntermediateDirectories: true)

    let sourceFile = repoRoot.appendingPathComponent("Sources/Foo/Bar.swift")
    try "func bar() {}".write(to: sourceFile, atomically: true, encoding: .utf8)

    let coveragePath = codecovRoot.appendingPathComponent("symphony-swift.json")
    let packageCoverageJSON = #"""
      {
        "data": [
          {
            "files": [
              {
                "filename": "__REPO__/Sources/Foo/Bar.swift",
                "summary": { "lines": { "count": 4, "covered": 2 } }
              }
            ]
          }
        ]
      }
      """#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    try packageCoverageJSON.write(to: coveragePath, atomically: true, encoding: .utf8)

    let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
    let testBinaryPath = testBundleRoot.appendingPathComponent("symphony-swiftPackageTests")
    try Data().write(to: profdataPath)
    try Data().write(to: testBinaryPath)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let runner = PackageInspectionOverwriteProcessRunner(
      packageCoveragePath: coveragePath.path,
      sourceFilePath: sourceFile.path,
      profdataPath: profdataPath.path,
      testBinaryPath: testBinaryPath.path
    )
    let suiteCoverage = CoverageReport(
      coveredLines: 1,
      executableLines: 1,
      lineCoverage: 1,
      includeTestTargets: false,
      excludedTargets: [],
      targets: []
    )

    let execution = try CommitHarness(
      processRunner: runner,
      statusSink: { _ in },
      clientCoverageLoader: { _ in suiteCoverage },
      serverCoverageLoader: { _ in
        runner.markArtifactsRewritten()
        return suiteCoverage
      },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).execute(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 100, json: false, currentDirectory: repoRoot)
    )

    let violation = try #require(execution.report.packageFileViolations.first)
    #expect(violation.name == "Sources/Foo/Bar.swift")
    #expect(violation.missingLineRanges == [CoverageLineRange(startLine: 2, endLine: 3)])
    #expect(violation.uncoveredFunctions == ["initial()"])
  }
}

@Test func harnessCoverageViolationDecodesWithoutUncoveredFunctions() throws {
  let json =
    #"{"suite":"package","kind":"file","name":"Foo.swift","coveredLines":9,"executableLines":10,"lineCoverage":0.9}"#
  let data = Data(json.utf8)
  let violation = try JSONDecoder().decode(HarnessCoverageViolation.self, from: data)
  #expect(violation.suite == "package")
  #expect(violation.uncoveredFunctions == nil)
  #expect(violation.missingLineRanges == nil)
}

@Test func harnessCoverageViolationDecodesWithUncoveredFunctions() throws {
  let json =
    #"{"suite":"package","kind":"file","name":"Foo.swift","coveredLines":9,"executableLines":10,"lineCoverage":0.9,"uncoveredFunctions":["bar()"],"missingLineRanges":[{"startLine":3,"endLine":4}]}"#
  let data = Data(json.utf8)
  let violation = try JSONDecoder().decode(HarnessCoverageViolation.self, from: data)
  #expect(violation.uncoveredFunctions == ["bar()"])
  #expect(violation.missingLineRanges == [CoverageLineRange(startLine: 3, endLine: 4)])
}

@Test func applyInspectionFilesDemanglesNamesAndCapturesMissingLines() {
  let demangleCommand = "xcrun swift-demangle $s4Main3baryyF"
  let enriched = CommitHarness.applyInspectionFiles(
    [
      CoverageInspectionFileReport(
        targetName: "Foo",
        path: "Sources/Foo/Bar.swift",
        coveredLines: 2,
        executableLines: 4,
        lineCoverage: 0.5,
        missingLineRanges: [CoverageLineRange(startLine: 2, endLine: 3)],
        functions: [
          CoverageInspectionFunctionReport(
            name: "$s4Main3baryyF",
            coveredLines: 2,
            executableLines: 4,
            lineCoverage: 0.5
          )
        ]
      )
    ],
    to: [
      HarnessCoverageViolation(
        suite: "package",
        kind: "file",
        name: "Sources/Foo/Bar.swift",
        coveredLines: 2,
        executableLines: 4,
        lineCoverage: 0.5
      )
    ],
    processRunner: StubProcessRunner(results: [
      demangleCommand: StubProcessRunner.success(
        """
        $s4Main3baryyF ---> Main.bar() -> ()
        ignored trailing line
        """
      )
    ]),
    xcrunAvailable: true
  )

  #expect(enriched.count == 1)
  #expect(enriched[0].uncoveredFunctions == ["Main.bar() -> ()"])
  #expect(enriched[0].missingLineRanges == [CoverageLineRange(startLine: 2, endLine: 3)])
}

@Test func applyInspectionFilesFallsBackWhenDemanglingIsUnavailableOrUnnecessary() {
  let fallbackDemangleCommand = "xcrun swift-demangle $s4Main3baryyF"
  let enriched = CommitHarness.applyInspectionFiles(
    [
      CoverageInspectionFileReport(
        targetName: "Foo",
        path: "Sources/Foo/Bar.swift",
        coveredLines: 1,
        executableLines: 4,
        lineCoverage: 0.25,
        missingLineRanges: [CoverageLineRange(startLine: 2, endLine: 3)],
        functions: [
          CoverageInspectionFunctionReport(
            name: "helper()",
            coveredLines: 0,
            executableLines: 2,
            lineCoverage: 0
          ),
          CoverageInspectionFunctionReport(
            name: "$s4Main3baryyF",
            coveredLines: 2,
            executableLines: 4,
            lineCoverage: 0.5
          ),
          CoverageInspectionFunctionReport(
            name: "$s4Main3baryyF",
            coveredLines: 2,
            executableLines: 4,
            lineCoverage: 0.5
          ),
        ]
      )
    ],
    to: [
      HarnessCoverageViolation(
        suite: "package",
        kind: "file",
        name: "Sources/Foo/Bar.swift",
        coveredLines: 1,
        executableLines: 4,
        lineCoverage: 0.25
      )
    ],
    processRunner: StubProcessRunner(results: [
      fallbackDemangleCommand: StubProcessRunner.success("Main.bar() -> ()\n")
    ]),
    xcrunAvailable: true
  )

  #expect(enriched[0].uncoveredFunctions == ["helper()", "Main.bar() -> ()", "Main.bar() -> ()"])
  #expect(enriched[0].missingLineRanges == [CoverageLineRange(startLine: 2, endLine: 3)])
}

@Test func applyInspectionFilesLeavesMangledNamesWhenXcrunIsUnavailable() {
  let enriched = CommitHarness.applyInspectionFiles(
    [
      CoverageInspectionFileReport(
        targetName: "Foo",
        path: "Sources/Foo/Bar.swift",
        coveredLines: 1,
        executableLines: 4,
        lineCoverage: 0.25,
        missingLineRanges: [CoverageLineRange(startLine: 2, endLine: 2)],
        functions: [
          CoverageInspectionFunctionReport(
            name: "$s4Main3baryyF",
            coveredLines: 0,
            executableLines: 2,
            lineCoverage: 0
          )
        ]
      )
    ],
    to: [
      HarnessCoverageViolation(
        suite: "package",
        kind: "file",
        name: "Sources/Foo/Bar.swift",
        coveredLines: 1,
        executableLines: 4,
        lineCoverage: 0.25
      )
    ],
    processRunner: StubProcessRunner(),
    xcrunAvailable: false
  )

  #expect(enriched[0].uncoveredFunctions == ["$s4Main3baryyF"])
  #expect(enriched[0].missingLineRanges == [CoverageLineRange(startLine: 2, endLine: 2)])
}

@Test func applyInspectionFilesFallsBackToRawMangledNameWhenDemangleOutputIsUnusable() {
  let failureDemangleCommand = "xcrun swift-demangle $s4Main4failyyF"
  let emptyDemangleCommand = "xcrun swift-demangle $s4Main5emptyyyF"
  let enriched = CommitHarness.applyInspectionFiles(
    [
      CoverageInspectionFileReport(
        targetName: "Foo",
        path: "Sources/Foo/Bar.swift",
        coveredLines: 1,
        executableLines: 4,
        lineCoverage: 0.25,
        missingLineRanges: [CoverageLineRange(startLine: 2, endLine: 2)],
        functions: [
          CoverageInspectionFunctionReport(
            name: "$s4Main4failyyF",
            coveredLines: 0,
            executableLines: 2,
            lineCoverage: 0
          ),
          CoverageInspectionFunctionReport(
            name: "$s4Main5emptyyyF",
            coveredLines: 0,
            executableLines: 2,
            lineCoverage: 0
          ),
        ]
      )
    ],
    to: [
      HarnessCoverageViolation(
        suite: "package",
        kind: "file",
        name: "Sources/Foo/Bar.swift",
        coveredLines: 1,
        executableLines: 4,
        lineCoverage: 0.25
      )
    ],
    processRunner: StubProcessRunner(results: [
      failureDemangleCommand: StubProcessRunner.failure("demangle failed"),
      emptyDemangleCommand: StubProcessRunner.success(""),
    ]),
    xcrunAvailable: true
  )

  #expect(enriched[0].uncoveredFunctions == ["$s4Main4failyyF", "$s4Main5emptyyyF"])
  #expect(enriched[0].missingLineRanges == [CoverageLineRange(startLine: 2, endLine: 2)])
}

