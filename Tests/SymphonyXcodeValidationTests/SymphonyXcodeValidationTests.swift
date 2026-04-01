import Foundation
import Testing

@testable import SymphonyXcodeValidation

@Suite("SymphonyXcodeValidation")
struct SymphonyXcodeValidationTests {
  @Test func defaultDestinationMatrixMatchesPlannedPlatforms() {
    #expect(
      ValidationDestination.defaultMatrix == [
        .macOS,
        .iPhoneSimulator,
        .iPadSimulator,
      ]
    )
    #expect(ValidationDestination.macOS.xcodeDestination == "platform=macOS,arch=arm64")
    #expect(
      ValidationDestination.iPhoneSimulator.xcodeDestination
        == "platform=iOS Simulator,id=E09AB2DE-2B82-49E2-8119-6C2FD1227C04")
    #expect(
      ValidationDestination.iPadSimulator.xcodeDestination
        == "platform=iOS Simulator,id=FB1A9F71-0620-4314-BF84-1BD1C46ABF5D")
  }

  @Test func buildForTestingCommandIncludesSchemePlanDestinationAndDerivedData() {
    let projectRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
    let command = ValidationCommandBuilder.buildForTestingCommand(
      projectRoot: projectRoot,
      subject: .symphonySwiftUIApp,
      plan: .uiTests,
      destination: .macOS,
      buildProfile: .standard,
      derivedDataPath: projectRoot.appendingPathComponent(".build/derived-data/ui-tests"),
      outputModeQuiet: true
    )

    #expect(command.executable == "xcodebuild")
    #expect(command.arguments.contains("build-for-testing"))
    #expect(command.arguments.contains("-quiet") == false)
    #expect(command.arguments.contains("-project"))
    #expect(command.arguments.contains("SymphonyApps.xcodeproj"))
    #expect(command.arguments.contains("-scheme"))
    #expect(command.arguments.contains("SymphonySwiftUIAppUITests"))
    #expect(command.arguments.contains("-testPlan"))
    #expect(command.arguments.contains("SymphonySwiftUIAppUITests"))
    #expect(command.arguments.contains("-destination"))
    #expect(command.arguments.contains("platform=macOS,arch=arm64"))
    #expect(command.arguments.contains("-derivedDataPath"))
    #expect(command.arguments.contains("/tmp/repo/.build/derived-data/ui-tests"))
    #expect(command.arguments.contains("-enableCodeCoverage") == false)
    #expect(command.arguments.contains("COMPILER_INDEX_STORE_ENABLE=NO") == false)
    #expect(command.currentDirectory == projectRoot)
  }

  @Test func buildForTestingCommandQuietModeStillSilencesNonUITestPlans() {
    let projectRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
    let command = ValidationCommandBuilder.buildForTestingCommand(
      projectRoot: projectRoot,
      subject: .xcodeValidationGalleryApp,
      plan: .appTests,
      destination: .macOS,
      buildProfile: .fast,
      derivedDataPath: projectRoot.appendingPathComponent(".build/derived-data/gallery-app-tests"),
      outputModeQuiet: true
    )

    #expect(command.arguments.contains("-quiet"))
  }

  @Test func buildForTestingCommandFastProfileDisablesCoverageAndIndexStore() {
    let projectRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
    let command = ValidationCommandBuilder.buildForTestingCommand(
      projectRoot: projectRoot,
      subject: .symphonySwiftUIApp,
      plan: .uiTests,
      destination: .iPhoneSimulator,
      buildProfile: .fast,
      derivedDataPath: projectRoot.appendingPathComponent(".build/derived-data/ui-tests"),
      outputModeQuiet: true
    )

    #expect(command.arguments.contains("-enableCodeCoverage"))
    #expect(command.arguments.contains("NO"))
    #expect(command.arguments.contains("COMPILER_INDEX_STORE_ENABLE=NO"))
  }

  @Test func testWithoutBuildingCommandIncludesXCTestRunOnlyTestingAndResultBundle() {
    let projectRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
    let command = ValidationCommandBuilder.testWithoutBuildingCommand(
      projectRoot: projectRoot,
      subject: .symphonySwiftUIApp,
      plan: .uiTests,
      xctestrunPath: projectRoot.appendingPathComponent(
        ".build/derived-data/ui-tests/Build/Products/ui-tests.xctestrun"
      ),
      destination: .iPadSimulator,
      buildProfile: .standard,
      resultBundlePath: projectRoot.appendingPathComponent(".build/results/ui-tests.xcresult"),
      onlyTesting: [
        "SymphonySwiftUIAppUITests/SymphonySwiftUIAppUITests/testRichMediaWalkthroughCapturesExtensibleSurfaceMatrix"
      ],
      outputModeQuiet: true
    )

    #expect(command.executable == "xcodebuild")
    #expect(command.arguments.contains("test-without-building"))
    #expect(command.arguments.contains("-xctestrun"))
    #expect(
      command.arguments.contains(
        "/tmp/repo/.build/derived-data/ui-tests/Build/Products/ui-tests.xctestrun"))
    #expect(command.arguments.contains("-destination"))
    #expect(
      command.arguments.contains("platform=iOS Simulator,id=FB1A9F71-0620-4314-BF84-1BD1C46ABF5D"))
    #expect(command.arguments.contains("-resultBundlePath"))
    #expect(command.arguments.contains("/tmp/repo/.build/results/ui-tests.xcresult"))
    #expect(command.arguments.contains("-only-testing"))
    #expect(
      command.arguments.contains(
        "SymphonySwiftUIAppUITests/SymphonySwiftUIAppUITests/testRichMediaWalkthroughCapturesExtensibleSurfaceMatrix"))
    #expect(command.arguments.contains("-enableCodeCoverage") == false)
    #expect(command.arguments.contains("-quiet") == false)
  }

  @Test func testWithoutBuildingCommandFastProfileDisablesCoverage() {
    let projectRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
    let command = ValidationCommandBuilder.testWithoutBuildingCommand(
      projectRoot: projectRoot,
      subject: .symphonySwiftUIApp,
      plan: .uiTests,
      xctestrunPath: projectRoot.appendingPathComponent(
        ".build/derived-data/ui-tests/Build/Products/ui-tests.xctestrun"
      ),
      destination: .iPadSimulator,
      buildProfile: .fast,
      resultBundlePath: projectRoot.appendingPathComponent(".build/results/ui-tests.xcresult"),
      onlyTesting: [],
      outputModeQuiet: true
    )

    #expect(command.arguments.contains("-enableCodeCoverage"))
    #expect(command.arguments.contains("NO"))
  }

  @Test func testWithoutBuildingCommandQuietModeStillSilencesNonUITestPlans() {
    let projectRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
    let command = ValidationCommandBuilder.testWithoutBuildingCommand(
      projectRoot: projectRoot,
      subject: .xcodeValidationGalleryApp,
      plan: .appTests,
      xctestrunPath: projectRoot.appendingPathComponent(
        ".build/derived-data/gallery-app-tests/Build/Products/gallery-app-tests.xctestrun"
      ),
      destination: .macOS,
      buildProfile: .standard,
      resultBundlePath: projectRoot.appendingPathComponent(".build/results/gallery-app-tests.xcresult"),
      onlyTesting: [
        "XcodeValidationGalleryAppTests/XcodeValidationGalleryAppBootstrapTests/bundledFixtureBootstrapActionUsesBundledFixtureSource()"
      ],
      outputModeQuiet: true
    )

    #expect(command.arguments.contains("-quiet"))
  }

  @Test func simulatorTerminationCommandsTargetKnownBundlesOnSimulatorsOnly() {
    let projectRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
    let commands = ValidationCommandBuilder.simulatorTerminationCommands(
      projectRoot: projectRoot,
      destination: .iPhoneSimulator,
      bundleIdentifiers: [
        "dev.atjsh.symphony",
        "dev.atjsh.symphony.uitests.xctrunner",
      ]
    )

    #expect(commands.count == 2)
    #expect(commands[0].executable == "xcrun")
    #expect(
      commands[0].arguments == [
        "simctl",
        "terminate",
        "E09AB2DE-2B82-49E2-8119-6C2FD1227C04",
        "dev.atjsh.symphony",
      ])
    #expect(
      commands[1].arguments == [
        "simctl",
        "terminate",
        "E09AB2DE-2B82-49E2-8119-6C2FD1227C04",
        "dev.atjsh.symphony.uitests.xctrunner",
      ])
    #expect(
      ValidationCommandBuilder.simulatorTerminationCommands(
        projectRoot: projectRoot,
        destination: .macOS,
        bundleIdentifiers: ["dev.atjsh.symphony"]
      ).isEmpty
    )
  }

  @Test func simulatorRestartCommandsShutdownBootAndWaitForBootstatus() {
    let projectRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
    let commands = ValidationCommandBuilder.simulatorRestartCommands(
      projectRoot: projectRoot,
      destination: .iPadSimulator
    )

    #expect(commands.count == 3)
    #expect(
      commands.map(\.arguments) == [
        ["simctl", "shutdown", "FB1A9F71-0620-4314-BF84-1BD1C46ABF5D"],
        ["simctl", "boot", "FB1A9F71-0620-4314-BF84-1BD1C46ABF5D"],
        ["simctl", "bootstatus", "FB1A9F71-0620-4314-BF84-1BD1C46ABF5D", "-b"],
      ]
    )
    #expect(
      ValidationCommandBuilder.simulatorRestartCommands(
        projectRoot: projectRoot,
        destination: .macOS
      ).isEmpty
    )
  }

  @Test func pathFactorySeparatesPhaseDestinationAndPlanArtifacts() {
    let root = URL(fileURLWithPath: "/tmp/repo/.build/xcode-validation/20260329-180000", isDirectory: true)
    let context = ValidationPathFactory.makeContext(
      outputRoot: root,
      phase: .richCapture,
      destination: .iPhoneSimulator,
      plan: .uiTests,
      buildProfile: .fast,
      runName: "rich-media"
    )
    let matrixContext = ValidationPathFactory.makeContext(
      outputRoot: root,
      phase: .fullMatrix,
      destination: .iPhoneSimulator,
      plan: .uiTests,
      buildProfile: .fast,
      runName: "full-ui-tests"
    )
    let standardContext = ValidationPathFactory.makeContext(
      outputRoot: root,
      phase: .fullMatrix,
      destination: .iPhoneSimulator,
      plan: .uiTests,
      buildProfile: .standard,
      runName: "full-ui-tests"
    )

    #expect(context.artifactRoot.path == "/tmp/repo/.build/xcode-validation/20260329-180000/ios/ui-tests/rich-capture/rich-media")
    #expect(context.derivedDataPath.path == "/tmp/repo/.build/xcode-validation/20260329-180000/intermediates/build-cache/ios/ui-tests/fast/derived-data")
    #expect(context.resultBundlePath.path == "/tmp/repo/.build/xcode-validation/20260329-180000/intermediates/ios/ui-tests/rich-capture/rich-media/result.xcresult")
    #expect(context.attachmentExportPath.path == "/tmp/repo/.build/xcode-validation/20260329-180000/exports/ios/ui-tests/rich-capture/rich-media")
    #expect(context.mediaDirectory.path == "/tmp/repo/.build/xcode-validation/20260329-180000/ios/media")
    #expect(matrixContext.derivedDataPath == context.derivedDataPath)
    #expect(standardContext.derivedDataPath != context.derivedDataPath)
    #expect(matrixContext.resultBundlePath != context.resultBundlePath)
    #expect(matrixContext.attachmentExportPath != context.attachmentExportPath)
  }

  @Test func validationRequestDefaultsToCanonicalOnlyRetentionFastBuildProfileAndInfoLogging() {
    let request = ValidationRequest(projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true))

    #expect(request.subject == .symphonySwiftUIApp)
    #expect(request.artifactRetention == .canonicalOnly)
    #expect(request.buildProfile == .fast)
    #expect(request.executionProfile == .aggressive)
    #expect(request.concurrency == nil)
    #expect(request.logLevel == .info)
    #expect(request.skipRichCapture == false)
    #expect(request.skipFullMatrix == false)
  }

  @Test func validationSubjectsResolveExpectedPlanConfigurationAndEnvironmentDefaults() {
    let symphonyConfiguration = ValidationSubject.symphonySwiftUIApp.configuration
    let galleryConfiguration = ValidationSubject.xcodeValidationGalleryApp.configuration

    #expect(symphonyConfiguration.planConfiguration(for: .uiTests).schemeName == "SymphonySwiftUIAppUITests")
    #expect(symphonyConfiguration.planConfiguration(for: .app).testPlanName == "SymphonySwiftUIApp")
    #expect(symphonyConfiguration.defaultCommandEnvironment.isEmpty)

    #expect(galleryConfiguration.planConfiguration(for: .app).schemeName == "XcodeValidationGalleryApp")
    #expect(galleryConfiguration.planConfiguration(for: .appTests).testPlanName == "XcodeValidationGalleryAppTests")
    #expect(
      galleryConfiguration.defaultCommandEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE"]
        == "1"
    )
    #expect(
      galleryConfiguration.simulatorBundleIdentifiers == [
        "dev.atjsh.xcode-validation-gallery",
        "dev.atjsh.xcodevalidationgallery.uitests.xctrunner",
      ]
    )
  }

  @Test func gallerySubjectBuildAndTestCommandsUseGallerySchemesPlansAndDefaultEnvironment() {
    let projectRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
    let buildCommand = ValidationCommandBuilder.buildForTestingCommand(
      projectRoot: projectRoot,
      subject: .xcodeValidationGalleryApp,
      plan: .uiTests,
      destination: .macOS,
      buildProfile: .standard,
      derivedDataPath: projectRoot.appendingPathComponent(".build/derived-data/gallery-ui-tests"),
      outputModeQuiet: true
    )
    let testCommand = ValidationCommandBuilder.testWithoutBuildingCommand(
      projectRoot: projectRoot,
      subject: .xcodeValidationGalleryApp,
      plan: .uiTests,
      xctestrunPath: projectRoot.appendingPathComponent(
        ".build/derived-data/gallery-ui-tests/Build/Products/gallery-ui-tests.xctestrun"
      ),
      destination: .iPhoneSimulator,
      buildProfile: .fast,
      resultBundlePath: projectRoot.appendingPathComponent(".build/results/gallery-ui-tests.xcresult"),
      onlyTesting: [
        "XcodeValidationGalleryAppUITests/XcodeValidationGalleryAppUITests/testRichMediaWalkthroughCapturesValidationGallerySurfaces()"
      ],
      outputModeQuiet: true
    )

    #expect(buildCommand.arguments.contains("XcodeValidationGalleryAppUITests"))
    #expect(buildCommand.arguments.contains("-quiet") == false)
    #expect(testCommand.arguments.contains("-enableCodeCoverage"))
    #expect(testCommand.arguments.contains("-quiet") == false)
    #expect(
      buildCommand.environment["XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE"] == "1"
    )
    #expect(
      testCommand.environment["XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE"] == "1"
    )
  }

  @Test func executionProfilesResolveExpectedConcurrencyDefaults() {
    #expect(
      ValidationExecutionProfile.aggressive.defaultConcurrency
        == ValidationConcurrency(
          maxParallelBuilds: 3,
          maxParallelDestinations: 3,
          maxParallelSimulators: 2,
          warmBuildsBeforeMitigationPass: true
        )
    )
    #expect(
      ValidationExecutionProfile.balanced.defaultConcurrency
        == ValidationConcurrency(
          maxParallelBuilds: 2,
          maxParallelDestinations: 2,
          maxParallelSimulators: 1,
          warmBuildsBeforeMitigationPass: true
        )
    )
    #expect(
      ValidationExecutionProfile.serial.defaultConcurrency
        == ValidationConcurrency(
          maxParallelBuilds: 1,
          maxParallelDestinations: 1,
          maxParallelSimulators: 1,
          warmBuildsBeforeMitigationPass: false
        )
    )
  }

  @Test func validationRequestResolvedConcurrencyUsesProfileDefaultsAndExplicitOverrides() {
    let defaultRequest = ValidationRequest(
      projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
      executionProfile: .balanced
    )
    let overriddenRequest = ValidationRequest(
      projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
      executionProfile: .aggressive,
      concurrency: ValidationConcurrency(
        maxParallelBuilds: 5,
        maxParallelDestinations: 4,
        maxParallelSimulators: 2,
        warmBuildsBeforeMitigationPass: false
      )
    )

    #expect(defaultRequest.resolvedConcurrency() == .init(
      maxParallelBuilds: 2,
      maxParallelDestinations: 2,
      maxParallelSimulators: 1,
      warmBuildsBeforeMitigationPass: true
    ))
    #expect(overriddenRequest.resolvedConcurrency() == .init(
      maxParallelBuilds: 5,
      maxParallelDestinations: 4,
      maxParallelSimulators: 2,
      warmBuildsBeforeMitigationPass: false
    ))
  }

}
