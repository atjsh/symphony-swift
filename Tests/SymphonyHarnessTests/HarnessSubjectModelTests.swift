import Foundation
import Testing

@testable import SymphonyHarness

@Test func repositoryLayoutCapturesCanonicalRoots() {
  let layout = RepositoryLayout(
    projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
    rootPackagePath: URL(fileURLWithPath: "/tmp/repo/Package.swift", isDirectory: false),
    xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/repo/Symphony.xcworkspace", isDirectory: true),
    xcodeProjectPath: URL(fileURLWithPath: "/tmp/repo/SymphonyApps.xcodeproj", isDirectory: true),
    applicationsRoot: URL(fileURLWithPath: "/tmp/repo/Applications", isDirectory: true)
  )

  #expect(layout.projectRoot.path == "/tmp/repo")
  #expect(layout.rootPackagePath.lastPathComponent == "Package.swift")
  #expect(layout.xcodeWorkspacePath?.lastPathComponent == "Symphony.xcworkspace")
  #expect(layout.xcodeProjectPath?.lastPathComponent == "SymphonyApps.xcodeproj")
  #expect(layout.applicationsRoot.lastPathComponent == "Applications")
}

@Test func harnessSubjectsExposeCanonicalSection20Mappings() throws {
  #expect(HarnessSubjects.productionSubjectNames == [
    "SymphonyShared",
    "SymphonyServerCore",
    "SymphonyServer",
    "SymphonyServerCLI",
    "SymphonyHarness",
    "SymphonyHarnessCLI",
    "SymphonySwiftUIApp",
  ])
  #expect(HarnessSubjects.explicitTestSubjectNames == [
    "SymphonySharedTests",
    "SymphonyServerCoreTests",
    "SymphonyServerTests",
    "SymphonyServerCLITests",
    "SymphonyHarnessTests",
    "SymphonyHarnessCLITests",
    "SymphonySwiftUIAppTests",
    "SymphonySwiftUIAppUITests",
  ])

  let serverCore = try #require(HarnessSubjects.subject(named: "SymphonyServerCore"))
  #expect(serverCore.kind == .library)
  #expect(serverCore.buildSystem == .swiftpm)
  #expect(serverCore.defaultTestCompanion == "SymphonyServerCoreTests")
  #expect(serverCore.requiresXcode == false)
  #expect(serverCore.requiresExclusiveDestination == false)

  let app = try #require(HarnessSubjects.subject(named: "SymphonySwiftUIApp"))
  #expect(app.kind == .app)
  #expect(app.buildSystem == .xcode)
  #expect(app.defaultTestCompanion == "SymphonySwiftUIAppTests")
  #expect(app.requiresXcode)
  #expect(app.requiresExclusiveDestination)

  let uiTests = try #require(HarnessSubjects.subject(named: "SymphonySwiftUIAppUITests"))
  #expect(uiTests.kind == .uiTest)
  #expect(uiTests.buildSystem == .xcode)
  #expect(uiTests.defaultTestCompanion == nil)
  #expect(uiTests.requiresXcode)
  #expect(uiTests.requiresExclusiveDestination)

  #expect(HarnessSubjects.runnableSubjectNames == ["SymphonyServerCLI", "SymphonySwiftUIApp"])
  #expect(HarnessSubjects.subject(named: "does-not-exist") == nil)
}
