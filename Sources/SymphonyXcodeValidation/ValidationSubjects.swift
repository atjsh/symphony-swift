import Foundation

public enum ValidationSubject: String, Codable, CaseIterable, Sendable {
  case symphonySwiftUIApp = "symphony-swift-ui-app"
  case xcodeValidationGalleryApp = "xcode-validation-gallery-app"
}

struct ValidationPlanConfiguration: Equatable, Sendable {
  let schemeName: String
  let testPlanName: String
}

struct ValidationScenarioDefinition: Equatable, Sendable {
  let destinations: [ValidationDestination]
  let phase: RunPhase
  let plan: ValidationPlan
  let runName: String
  let onlyTesting: [String]
  let exportAttachments: Bool
  let recordVideo: Bool
  let captureSimulatorScreenshot: Bool
}

struct ValidationSubjectConfiguration: Equatable, Sendable {
  let subject: ValidationSubject
  let projectFileName: String
  let supportedPlans: [ValidationPlan]
  let planConfigurations: [ValidationPlan: ValidationPlanConfiguration]
  let defaultCommandEnvironment: [String: String]
  let simulatorBundleIdentifiers: [String]
  let mitigationScenarios: [ValidationScenarioDefinition]
  let richCaptureScenario: ValidationScenarioDefinition?

  func planConfiguration(for plan: ValidationPlan) -> ValidationPlanConfiguration {
    guard let configuration = planConfigurations[plan] else {
      preconditionFailure("Missing validation plan configuration for \(plan.rawValue).")
    }
    return configuration
  }
}

extension ValidationSubject {
  var configuration: ValidationSubjectConfiguration {
    switch self {
    case .symphonySwiftUIApp:
      ValidationSubjectConfiguration(
        subject: self,
        projectFileName: "SymphonyApps.xcodeproj",
        supportedPlans: ValidationPlan.fullMatrix,
        planConfigurations: [
          .app: ValidationPlanConfiguration(
            schemeName: "SymphonySwiftUIApp",
            testPlanName: "SymphonySwiftUIApp"
          ),
          .appTests: ValidationPlanConfiguration(
            schemeName: "SymphonySwiftUIApp",
            testPlanName: "SymphonySwiftUIAppTests"
          ),
          .uiTests: ValidationPlanConfiguration(
            schemeName: "SymphonySwiftUIAppUITests",
            testPlanName: "SymphonySwiftUIAppUITests"
          ),
        ],
        defaultCommandEnvironment: [:],
        simulatorBundleIdentifiers: [
          "dev.atjsh.symphony",
          "dev.atjsh.symphony.uitests.xctrunner",
        ],
        mitigationScenarios: [
          ValidationScenarioDefinition(
            destinations: [.macOS],
            phase: .mitigation,
            plan: .appTests,
            runName: "progress-report-model",
            onlyTesting: [
              "SymphonySwiftUIAppTests/SymphonyOperatorModelTests/ProgressReportViewModelShowsCachedSnapshotBeforeRefreshing()"
            ],
            exportAttachments: false,
            recordVideo: false,
            captureSimulatorScreenshot: false
          ),
          ValidationScenarioDefinition(
            destinations: [.macOS],
            phase: .mitigation,
            plan: .uiTests,
            runName: "accessibility-audit",
            onlyTesting: [
              "SymphonySwiftUIAppUITests/SymphonySwiftUIAppUITests/testAccessibilityAuditCoversRequiredCheckpoints()"
            ],
            exportAttachments: true,
            recordVideo: false,
            captureSimulatorScreenshot: false
          ),
        ],
        richCaptureScenario: ValidationScenarioDefinition(
          destinations: ValidationDestination.defaultMatrix,
          phase: .richCapture,
          plan: .uiTests,
          runName: "rich-media",
          onlyTesting: [
            "SymphonySwiftUIAppUITests/SymphonySwiftUIAppUITests/testRichMediaWalkthroughCapturesExtensibleSurfaceMatrix()"
          ],
          exportAttachments: true,
          recordVideo: true,
          captureSimulatorScreenshot: true
        )
      )
    case .xcodeValidationGalleryApp:
      ValidationSubjectConfiguration(
        subject: self,
        projectFileName: "SymphonyApps.xcodeproj",
        supportedPlans: ValidationPlan.fullMatrix,
        planConfigurations: [
          .app: ValidationPlanConfiguration(
            schemeName: "XcodeValidationGalleryApp",
            testPlanName: "XcodeValidationGalleryApp"
          ),
          .appTests: ValidationPlanConfiguration(
            schemeName: "XcodeValidationGalleryApp",
            testPlanName: "XcodeValidationGalleryAppTests"
          ),
          .uiTests: ValidationPlanConfiguration(
            schemeName: "XcodeValidationGalleryAppUITests",
            testPlanName: "XcodeValidationGalleryAppUITests"
          ),
        ],
        defaultCommandEnvironment: [
          "XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE": "1"
        ],
        simulatorBundleIdentifiers: [
          "dev.atjsh.xcode-validation-gallery",
          "dev.atjsh.xcodevalidationgallery.uitests.xctrunner",
        ],
        mitigationScenarios: [
          ValidationScenarioDefinition(
            destinations: [.macOS],
            phase: .mitigation,
            plan: .appTests,
            runName: "fixture-bootstrap",
            onlyTesting: [
              "XcodeValidationGalleryAppTests/XcodeValidationGalleryAppBootstrapTests/testBundledFixtureBootstrapActionUsesBundledFixtureSource()"
            ],
            exportAttachments: false,
            recordVideo: false,
            captureSimulatorScreenshot: false
          ),
          ValidationScenarioDefinition(
            destinations: [.macOS],
            phase: .mitigation,
            plan: .uiTests,
            runName: "accessibility-audit",
            onlyTesting: [
              "XcodeValidationGalleryAppUITests/XcodeValidationGalleryAppUITests/testAccessibilityAuditCoversRequiredCheckpoints()"
            ],
            exportAttachments: true,
            recordVideo: false,
            captureSimulatorScreenshot: false
          ),
        ],
        richCaptureScenario: ValidationScenarioDefinition(
          destinations: ValidationDestination.defaultMatrix,
          phase: .richCapture,
          plan: .uiTests,
          runName: "rich-media",
          onlyTesting: [
            "XcodeValidationGalleryAppUITests/XcodeValidationGalleryAppUITests/testRichMediaWalkthroughCapturesValidationGallerySurfaces()"
          ],
          exportAttachments: true,
          recordVideo: true,
          captureSimulatorScreenshot: true
        )
      )
    }
  }
}
