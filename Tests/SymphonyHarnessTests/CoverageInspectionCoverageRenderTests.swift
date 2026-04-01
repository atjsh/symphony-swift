import Foundation
import Testing

@testable import SymphonyHarness

@Test func coverageInspectionHelpersCoverFormattingAndEmptyXcodeInspectionBranches() throws {
  let candidate = CoverageInspectionFileCandidate(
    targetName: "SymphonyServerCore",
    path: "/tmp/BootstrapSupport.swift",
    coveredLines: 1,
    executableLines: 2,
    lineCoverage: 0.5
  )
  #expect(candidate.targetName == "SymphonyServerCore")

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
    skippedReason:
      "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
  )
  let skippedHuman = renderHarnessInspectionHuman(artifact: skippedArtifact)
  #expect(skippedHuman.contains("client inspection backend xcode"))
  #expect(
    skippedHuman.contains(
      "skipped not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
    ))

  #expect(
    SwiftPMCoverageInspector.collapsedRanges(for: [7, 8, 10, 10, 11]) == [
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
  #expect(
    xcodeInspector.renderedMissingLinesCommandLine(
      resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
      filePath: "/tmp/ContentView.swift"
    ).contains("xccov view --archive --file /tmp/ContentView.swift /tmp/result.xcresult"))
  #expect(
    xcodeInspector.renderedFunctionsCommandLine(
      resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
      filePath: "/tmp/ContentView.swift"
    ).contains(
      "xccov view --report --functions-for-file /tmp/ContentView.swift /tmp/result.xcresult"))

  #expect(
    XcodeCoverageInspector.parseXcodeFunctions(
      output: """
        /tmp/ContentView.swift:
        ID Name                                  Range   Coverage
        -- ------------------------------------- ------- ---------------
        0  fullyCovered()                        {1, 1} 100.00% (1/1)
        1  zeroLines()                           {2, 0} 0.00% (0/0)
        """
    ).isEmpty)

  let stripped = strippedCoverageReport(
    CoverageReport(
      coveredLines: 2,
      executableLines: 4,
      lineCoverage: 0.5,
      includeTestTargets: false,
      excludedTargets: [],
      targets: [
        CoverageTargetReport(
          name: "SymphonyServerCore",
          buildProductPath: "/tmp/SymphonyServerCore",
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
  #expect(
    inspectionCandidates(
      from: CoverageReport(
        coveredLines: 2,
        executableLines: 2,
        lineCoverage: 1,
        includeTestTargets: false,
        excludedTargets: [],
        targets: [
          CoverageTargetReport(
            name: "SymphonyServerCore",
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
              ),
            ]
          )
        ]
      )
    ).isEmpty)

  let inspectionHuman = renderInspectionHuman(
    report: CoverageInspectionReport(
      backend: .swiftPM,
      product: .server,
      generatedAt: "2026-03-25T00:00:00Z",
      files: [
        CoverageInspectionFileReport(
          targetName: "SymphonyServerCore",
          path: "Sources/SymphonyServerCore/Orchestrator.swift",
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
    targetName: "SymphonyServerCore",
    path: "Sources/SymphonyServerCore/Orchestrator.swift",
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

  let inspectionHuman = renderInspectionHuman(
    report: CoverageInspectionReport(
      backend: .swiftPM,
      product: .server,
      generatedAt: "2026-03-25T00:00:00Z",
      files: [fileReport]
    ))
  #expect(inspectionHuman.contains("missing_lines 3-4"))
  #expect(inspectionHuman.contains("function bootstrap() 50.00% (2/4)"))

  let harnessHuman = renderHarnessInspectionHuman(
    artifact: HarnessCoverageInspectionArtifact(
      suite: "server",
      backend: .swiftPM,
      generatedAt: "2026-03-25T00:00:00Z",
      files: [fileReport]
    ))
  #expect(harnessHuman.contains("server inspection backend swiftPM"))
  #expect(harnessHuman.contains("missing_lines 3-4"))
  #expect(harnessHuman.contains("function bootstrap() 50.00% (2/4)"))

  let rawHuman = renderRawInspectionHuman(
    report: CoverageInspectionRawReport(
      backend: .swiftPM,
      product: .server,
      commands: [
        CoverageInspectionRawCommand(
          commandLine: "llvm-cov show",
          scope: "missing-lines",
          filePath: "Sources/SymphonyServerCore/Orchestrator.swift",
          format: "text",
          output: "annotated output"
        )
      ]
    ))
  #expect(rawHuman.contains("annotated output"))
}

@Test func swiftPMCoverageInspectorRequiresAvailableLLVMCovCommandWhenInspectionIsRequested() throws
{
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

    let inspector = SwiftPMCoverageInspector(
      processRunner: StubProcessRunner(results: [
        "which xcrun": StubProcessRunner.failure(""),
        "which llvm-cov": StubProcessRunner.failure(""),
      ]))
    do {
      _ = try inspector.inspect(
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
      Issue.record("Expected missing llvm-cov tooling to fail SwiftPM inspection.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_llvm_cov")
    }
  }
}
