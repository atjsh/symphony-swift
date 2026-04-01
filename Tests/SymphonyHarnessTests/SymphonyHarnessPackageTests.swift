import Foundation
import Testing

@testable import SymphonyHarness

@Test func workspaceDiscoveryRejectsLegacyToolsPackageManifest() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try "# root package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Symphony.xcworkspace"), withIntermediateDirectories: true
    )

    let toolsPackageRoot = repoRoot.appendingPathComponent(
      "Tools/SymphonyBuildPackage", isDirectory: true)
    try FileManager.default.createDirectory(at: toolsPackageRoot, withIntermediateDirectories: true)
    try "# nested package".write(
      to: toolsPackageRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )

    do {
      _ = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: repoRoot)
      Issue.record("Expected legacy nested tool package manifests to fail discovery.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "extra_package_manifest")
      #expect(error.message.contains("Tools/SymphonyBuildPackage/Package.swift"))
    }
  }
}

@Test func repositoryRootContainsOnlyTheCanonicalRootPackageManifest() {
  let repoRoot = currentRepositoryRoot()

  #expect(FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("Package.swift").path))
  #expect(
    !FileManager.default.fileExists(
      atPath: repoRoot.appendingPathComponent("Tools/SymphonyBuildPackage/Package.swift").path))
}

@Test func rootManifestPublishesCanonicalHarnessProductsAndTargets() throws {
  let repoRoot = currentRepositoryRoot()
  let manifest = try String(
    contentsOf: repoRoot.appendingPathComponent("Package.swift"),
    encoding: .utf8
  )

  #expect(manifest.contains(#".library(name: "SymphonyHarness""#))
  #expect(manifest.contains(#".library(name: "SymphonyHarnessCLI""#))
  #expect(manifest.contains(#".executable(name: "harness""#))
  #expect(manifest.contains(#"name: "SymphonyHarness""#))
  #expect(manifest.contains(#"name: "SymphonyHarnessCLI""#))
  #expect(manifest.contains(#".executableTarget("#))
  #expect(!manifest.contains("SymphonyBuildCore"))
  #expect(!manifest.contains("SymphonyBuildCLI"))
  #expect(!manifest.contains("symphony-build"))
}

@Test func harnessLibraryPublicSurfaceUsesSubjectRequestsInsteadOfLegacyProductRequests() throws {
  let repoRoot = currentRepositoryRoot()
  let modelsDir = repoRoot.appendingPathComponent("Sources/SymphonyHarness/Models")
  let modelFiles = try FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "swift" }
  let buildModels = try modelFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
  let planningModels = try String(
    contentsOf: repoRoot.appendingPathComponent("Sources/SymphonyHarness/Models/HarnessPlanningModels.swift"),
    encoding: .utf8
  )
  let harnessDir = repoRoot.appendingPathComponent("Sources/SymphonyHarness")
  let toolFiles = try FileManager.default.contentsOfDirectory(at: harnessDir, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("SymphonyHarnessTool") && $0.pathExtension == "swift" }
  let toolSource = try toolFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
  let artifactsDir = repoRoot.appendingPathComponent("Sources/SymphonyHarness/Artifacts")
  let artifactFiles = try FileManager.default.contentsOfDirectory(at: artifactsDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "swift" }
  let artifactManager = try artifactFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
  let harnessSubdir = repoRoot.appendingPathComponent("Sources/SymphonyHarness/Harness")
  let commitFiles = try FileManager.default.contentsOfDirectory(at: harnessSubdir, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("CommitHarness") && $0.pathExtension == "swift" }
  let commitHarness = try commitFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

  #expect(planningModels.contains("public struct ExecutionRequest"))
  #expect(!buildModels.contains("public struct BuildCommandRequest"))
  #expect(!buildModels.contains("public struct TestCommandRequest"))
  #expect(!buildModels.contains("public struct RunCommandRequest"))
  #expect(!buildModels.contains("public enum XcodeAction"))
  #expect(!buildModels.contains("public struct SchemeSelector"))
  #expect(!buildModels.contains("public struct XcodeCommandRequest"))
  #expect(!buildModels.contains("public enum BuildCommandFamily"))
  #expect(!buildModels.contains("public enum ProductKind"))
  #expect(!buildModels.contains("public struct HarnessCommandRequest"))
  #expect(!buildModels.contains("public struct HooksInstallRequest"))
  #expect(!buildModels.contains("public struct ArtifactsCommandRequest"))
  #expect(!buildModels.contains("public struct SimSetServerRequest"))
  #expect(!buildModels.contains("public struct SimBootRequest"))
  #expect(buildModels.contains("public struct GoEnryMaterializationRequest"))

  #expect(toolSource.contains("public func build(_ request: ExecutionRequest)"))
  #expect(toolSource.contains("public func test(_ request: ExecutionRequest)"))
  #expect(toolSource.contains("public func run(_ request: ExecutionRequest)"))
  #expect(toolSource.contains("public func validate(_ request: ExecutionRequest)"))
  #expect(toolSource.contains("public func doctor(_ request: DoctorCommandRequest)"))
  #expect(toolSource.contains("public func materializeGoEnry(_ request: GoEnryMaterializationRequest)"))
  #expect(!toolSource.contains("public func build(_ request: BuildCommandRequest)"))
  #expect(!toolSource.contains("public func test(_ request: TestCommandRequest)"))
  #expect(!toolSource.contains("public func run(_ request: RunCommandRequest)"))
  #expect(!toolSource.contains("public func artifacts(_ request: ArtifactsCommandRequest)"))
  #expect(!toolSource.contains("public func harness(_ request: HarnessCommandRequest)"))
  #expect(!toolSource.contains("public func hooksInstall(_ request: HooksInstallRequest)"))
  #expect(!toolSource.contains("public func simBoot(_ request: SimBootRequest)"))
  #expect(!toolSource.contains("public func simSetServer(_ request: SimSetServerRequest)"))
  #expect(!toolSource.contains("public func simClearServer(currentDirectory: URL)"))
  #expect(!toolSource.contains("public func simList(currentDirectory: URL)"))

  #expect(!artifactManager.contains("public func resolveArtifacts(workspace: WorkspaceContext, request: ArtifactsCommandRequest)"))
  #expect(!artifactManager.contains("public func recordXcodeExecution("))
  #expect(!artifactManager.contains("public func recordSwiftPMExecution("))
  #expect(!commitHarness.contains("public func run(workspace: WorkspaceContext, request: HarnessCommandRequest)"))
  #expect(!commitHarness.contains("public func execute(workspace: WorkspaceContext, request: HarnessCommandRequest)"))
}

@Test func repositoryUsesCanonicalHarnessSourceAndTestRoots() {
  let repoRoot = currentRepositoryRoot()
  let fileManager = FileManager.default

  #expect(
    fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Sources/SymphonyHarness").path))
  #expect(
    fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Sources/SymphonyHarnessCLI").path))
  #expect(fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Sources/harness").path))
  #expect(
    fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Tests/SymphonyHarnessTests").path))
  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Tests/SymphonyHarnessCLITests").path))

  #expect(
    !fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Sources/SymphonyBuildCore").path))
  #expect(
    !fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Sources/SymphonyBuildCLI").path))
  #expect(
    !fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Tests/SymphonyBuildCoreTests").path))
  #expect(
    !fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Tests/SymphonyBuildCLITests").path))
}

@Test func repositoryPublishesThinJustWrapperRecipes() throws {
  let repoRoot = currentRepositoryRoot()
  let justfile = try String(
    contentsOf: repoRoot.appendingPathComponent("justfile"),
    encoding: .utf8
  )

  #expect(justfile.contains("build *subjects:"))
  #expect(justfile.contains("test *subjects:"))
  #expect(justfile.contains("run subject"))
  #expect(justfile.contains("validate *subjects:"))
  #expect(justfile.contains("doctor:"))
  #expect(justfile.contains("materialize-go-enry:"))
  #expect(justfile.contains("harness_scratch_path :="))
  #expect(justfile.contains("swift run --quiet --scratch-path {{harness_scratch_path}} harness build"))
  #expect(justfile.contains("swift run --quiet --scratch-path {{harness_scratch_path}} harness validate"))
  #expect(
    justfile.contains(
      "swift run --quiet --scratch-path {{harness_scratch_path}} harness materialize-go-enry"))
  #expect(!justfile.contains("./Scripts/materialize-go-enry.sh"))
}

@Test func rootManifestPublishesCanonicalServerTargetsAndRemovesLegacyRuntimeTargets() throws {
  let repoRoot = currentRepositoryRoot()
  let manifest = try String(
    contentsOf: repoRoot.appendingPathComponent("Package.swift"),
    encoding: .utf8
  )

  #expect(manifest.contains(#".library(name: "SymphonyServerCore""#))
  #expect(manifest.contains(#".library(name: "SymphonyServer""#))
  #expect(manifest.contains(#".executable(name: "symphony-server""#))
  #expect(manifest.contains(#"name: "SymphonyServerCLI""#))
  #expect(!manifest.contains(#".library(name: "SymphonyRuntime""#))
  #expect(!manifest.contains(#"name: "SymphonyRuntime""#))
  #expect(!manifest.contains(#".executable(name: "SymphonyServer""#))
}

@Test func repositoryUsesCanonicalServerSourceAndTestRoots() {
  let repoRoot = currentRepositoryRoot()
  let fileManager = FileManager.default

  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Sources/SymphonyServerCore").path))
  #expect(
    fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Sources/SymphonyServer").path))
  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Sources/SymphonyServerCLI").path))
  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Tests/SymphonyServerCoreTests").path))
  #expect(
    fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Tests/SymphonyServerTests").path))
  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Tests/SymphonyServerCLITests").path))

  #expect(
    !fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Sources/SymphonyRuntime").path))
}

@Test func repositoryUsesCanonicalAppRootsAndCheckedInTestPlans() throws {
  let repoRoot = currentRepositoryRoot()
  let fileManager = FileManager.default

  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Applications/SymphonySwiftUIApp").path))
  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Applications/SymphonySwiftUIAppTests").path))
  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Applications/SymphonySwiftUIAppUITests").path))
  #expect(
    !fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Applications/Symphony").path))
  #expect(
    !fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Applications/SymphonyTests").path))
  #expect(
    !fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Applications/SymphonyUITests").path))
  #expect(
    !fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Sources/SymphonyClientUI").path))
  #expect(
    !fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Tests/SymphonyClientUITests").path))

  let xcodeTestPlanRoot = repoRoot.appendingPathComponent(
    "SymphonyApps.xcodeproj/xcshareddata/xctestplans",
    isDirectory: true
  )
  let testPlanFiles =
    (try? fileManager.contentsOfDirectory(at: xcodeTestPlanRoot, includingPropertiesForKeys: nil))
    ?? []
  #expect(testPlanFiles.contains { $0.pathExtension == "xctestplan" })
}

@Test func repositoryUsesSwiftTestingForNonUIAppTestsAndUIValidationMarkers() throws {
  let repoRoot = currentRepositoryRoot()
  let fileManager = FileManager.default

  let nonUITests = try String(
    contentsOf: repoRoot.appendingPathComponent(
      "Applications/SymphonySwiftUIAppTests/BootstrapSupportTests.swift"),
    encoding: .utf8
  )
  #expect(nonUITests.contains("import Testing"))
  #expect(!nonUITests.contains("import XCTest"))
  #expect(nonUITests.contains("@Suite"))
  #expect(nonUITests.contains("@Test"))

  let uiTestDir = repoRoot.appendingPathComponent("Applications/SymphonySwiftUIAppUITests")
  let uiTestFiles = try FileManager.default.contentsOfDirectory(at: uiTestDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "swift" }
  let uiTests = try uiTestFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
  #expect(uiTests.contains("performAccessibilityAudit(for:"))
  #expect(uiTests.contains("XCTAttachment(screenshot:"))
  #expect(uiTests.contains("root"))
  #expect(uiTests.contains("root-landscape"))
  #expect(uiTests.contains("overview"))
  #expect(uiTests.contains("sessions"))
  #expect(uiTests.contains("logs"))
  #expect(uiTests.contains("XCUIDevice.shared.orientation"))
  #expect(uiTests.contains("testAccessibilityAuditCoversRequiredCheckpoints"))
  #expect(!uiTests.contains("verifyMacOSAccessibilitySurface"))

  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Applications/SymphonySwiftUIAppTests").path))
  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Applications/SymphonySwiftUIAppUITests").path))
}

@Test func sharedAppSchemesReferenceCheckedInTestPlans() throws {
  let repoRoot = currentRepositoryRoot()

  let appScheme = try String(
    contentsOf: repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xcschemes/SymphonySwiftUIApp.xcscheme"),
    encoding: .utf8
  )
  #expect(appScheme.contains("<TestPlans>"))
  #expect(appScheme.contains("SymphonySwiftUIApp.xctestplan"))
  #expect(appScheme.contains("SymphonySwiftUIAppTests.xctestplan"))
  #expect(appScheme.contains("SymphonySwiftUIAppUITests.xctestplan"))

  let uiScheme = try String(
    contentsOf: repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xcschemes/SymphonySwiftUIAppUITests.xcscheme"),
    encoding: .utf8
  )
  #expect(uiScheme.contains("<TestPlans>"))
  #expect(uiScheme.contains("SymphonySwiftUIAppUITests.xctestplan"))
}

@Test func checkedInAppTestPlansDeclareSeededUITestEnvironment() throws {
  let repoRoot = currentRepositoryRoot()

  let combinedPlan = try String(
    contentsOf: repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xctestplans/SymphonySwiftUIApp.xctestplan"),
    encoding: .utf8
  )
  #expect(!combinedPlan.contains("SYMPHONY_UI_TESTING"))
  #expect(!combinedPlan.contains(#""name" : "SymphonySwiftUIAppUITests""#))

  let uiPlan = try String(
    contentsOf: repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xctestplans/SymphonySwiftUIAppUITests.xctestplan"),
    encoding: .utf8
  )
  #expect(uiPlan.contains("environmentVariableEntries"))
  #expect(uiPlan.contains("SYMPHONY_UI_TESTING"))
}

@Test func xcodeProjectUsesCanonicalAppTargetNamesAndRemovesLegacyAliases() throws {
  let repoRoot = currentRepositoryRoot()
  let project = try String(
    contentsOf: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj/project.pbxproj"),
    encoding: .utf8
  )

  #expect(project.contains("SymphonySwiftUIApp"))
  #expect(project.contains("SymphonySwiftUIAppTests"))
  #expect(project.contains("SymphonySwiftUIAppUITests"))
  #expect(!project.contains("SymphonyClientUI"))
  #expect(!project.contains("SymphonyTests"))
  #expect(!project.contains("SymphonyUITests"))
}

@Test func xcodeProjectKeepsCanonicalAppBundleModuleSigningAndTestTargetSettings() throws {
  let repoRoot = currentRepositoryRoot()
  let project = try String(
    contentsOf: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj/project.pbxproj"),
    encoding: .utf8
  )
  let projectLines = project.split(separator: "\n")
  let developmentTeamLines = projectLines.filter { $0.contains("DEVELOPMENT_TEAM =") }

  #expect(project.contains("PRODUCT_NAME = Symphony;"))
  #expect(project.contains("PRODUCT_MODULE_NAME = SymphonySwiftUIApp;"))
  #expect(project.contains("INFOPLIST_KEY_CFBundleDisplayName = Symphony;"))
  #expect(project.contains("CODE_SIGN_STYLE = Automatic;"))
  #expect(project.contains("CODE_SIGNING_ALLOWED = YES;"))
  #expect(!project.contains("CODE_SIGN_IDENTITY = "))
  #expect(developmentTeamLines.allSatisfy { $0.contains("DEVELOPMENT_TEAM = \"\";") })
  #expect(project.contains("TEST_TARGET_NAME = SymphonySwiftUIApp;"))
}

@Test func repositoryProvidesCanonicalJustWrapperAndPreCommitWorkflow() throws {
  let repoRoot = currentRepositoryRoot()
  let justfilePath = repoRoot.appendingPathComponent("justfile")
  let preCommitPath = repoRoot.appendingPathComponent(".githooks/pre-commit")

  #expect(FileManager.default.fileExists(atPath: justfilePath.path))

  let justfile = try String(contentsOf: justfilePath, encoding: .utf8)
  for recipe in ["build", "test", "run", "validate", "doctor", "materialize-go-enry"] {
    #expect(justfile.contains(recipe))
    #expect(justfile.contains("swift run --quiet --scratch-path {{harness_scratch_path}} harness \(recipe)"))
  }

  #expect(
    !FileManager.default.fileExists(
      atPath: repoRoot.appendingPathComponent("Scripts/materialize-go-enry.sh").path))

  let preCommit = try String(contentsOf: preCommitPath, encoding: .utf8)
  #expect(preCommit.contains("#!/bin/sh"))
  #expect(preCommit.contains("just validate"))
  #expect(!preCommit.contains("symphony-build"))
  #expect(!preCommit.contains("Tools/SymphonyBuildPackage"))
}
