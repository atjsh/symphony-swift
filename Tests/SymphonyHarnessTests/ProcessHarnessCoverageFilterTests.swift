import Foundation
import Testing

@testable import SymphonyHarness

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
    } catch let error as SymphonyHarnessError {
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
    } catch let error as SymphonyHarnessError {
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
            "buildProductPath": "/tmp/SymphonySwiftUIAppTests.xctest/Contents/MacOS/SymphonySwiftUIAppTests",
            "coveredLines": 2,
            "executableLines": 2,
            "files": [
              { "coveredLines": 2, "executableLines": 2, "name": "Ignored.swift", "path": "/tmp/Ignored.swift" }
            ],
            "name": "SymphonySwiftUIAppTests.xctest"
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

    #expect(artifacts.report.excludedTargets == ["SymphonySwiftUIAppTests.xctest"])
    #expect(artifacts.report.targets.count == 1)
    #expect(artifacts.report.targets[0].files?.map(\.name) == ["Beta.swift", "Alpha.swift"])
    #expect(artifacts.textOutput.contains("excluded_targets SymphonySwiftUIAppTests.xctest"))
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

@Test func coverageReporterExcludesPlatformMismatchedClientTargets() throws {
  try withTemporaryDirectory { directory in
    let resultBundlePath = directory.appendingPathComponent("result.xcresult")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let json = #"""
      {
        "targets": [
          {
            "buildProductPath": "/tmp/Build/Products/Debug-iphonesimulator/Symphony.app/Symphony",
            "coveredLines": 5,
            "executableLines": 5,
            "files": [
              { "coveredLines": 5, "executableLines": 5, "name": "ContentView.swift", "path": "/tmp/ContentView.swift" }
            ],
            "name": "Symphony.app"
          },
          {
            "buildProductPath": "/tmp/Build/Products/Debug/SymphonyLocalServerHelper",
            "coveredLines": 0,
            "executableLines": 1,
            "files": [
              { "coveredLines": 0, "executableLines": 1, "name": "main.swift", "path": "/tmp/main.swift" }
            ],
            "name": "SymphonyLocalServerHelper"
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
    #expect(artifacts.report.excludedTargets == ["SymphonyLocalServerHelper"])
    #expect(artifacts.report.coveredLines == 5)
    #expect(artifacts.report.executableLines == 5)
  }
}

@Test func coverageReporterKeepsClientTargetsSharingBuildProductsRoot() throws {
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
            "buildProductPath": "/tmp/Build/Products/Debug/SymphonyLocalServerHelper",
            "coveredLines": 1,
            "executableLines": 1,
            "files": [
              { "coveredLines": 1, "executableLines": 1, "name": "main.swift", "path": "/tmp/main.swift" }
            ],
            "name": "SymphonyLocalServerHelper"
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

    #expect(artifacts.report.targets.map(\.name) == ["Symphony.app", "SymphonyLocalServerHelper"])
    #expect(artifacts.report.excludedTargets.isEmpty)
    #expect(artifacts.report.coveredLines == 6)
    #expect(artifacts.report.executableLines == 6)
  }
}

@Test func coverageReporterRetainsIncludedTestBundlesAndPathlessClientTargets() throws {
  try withTemporaryDirectory { directory in
    let resultBundlePath = directory.appendingPathComponent("result.xcresult")
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let json = #"""
      {
        "targets": [
          {
            "buildProductPath": "/tmp/Build/Products/Debug-iphonesimulator/Symphony.app/Symphony",
            "coveredLines": 5,
            "executableLines": 5,
            "files": [
              { "coveredLines": 5, "executableLines": 5, "name": "ContentView.swift", "path": "/tmp/ContentView.swift" }
            ],
            "name": "Symphony.app"
          },
          {
            "buildProductPath": "/tmp/Build/Products/Debug-iphonesimulator/Symphony.app/PlugIns/SymphonySwiftUIAppTests.xctest/SymphonySwiftUIAppTests",
            "coveredLines": 2,
            "executableLines": 2,
            "files": [
              { "coveredLines": 2, "executableLines": 2, "name": "Test.swift", "path": "/tmp/Test.swift" }
            ],
            "name": "SymphonySwiftUIAppTests.xctest"
          },
          {
            "buildProductPath": null,
            "coveredLines": 1,
            "executableLines": 1,
            "files": [
              { "coveredLines": 1, "executableLines": 1, "name": "main.swift", "path": "/tmp/main.swift" }
            ],
            "name": "DetachedHelper"
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
      includeTestTargets: true,
      showFiles: true
    )

    #expect(
      artifacts.report.targets.map(\.name) == [
        "Symphony.app",
        "SymphonySwiftUIAppTests.xctest",
        "DetachedHelper",
      ])
    #expect(artifacts.report.excludedTargets.isEmpty)
    #expect(artifacts.report.coveredLines == 8)
    #expect(artifacts.report.executableLines == 8)
  }
}
