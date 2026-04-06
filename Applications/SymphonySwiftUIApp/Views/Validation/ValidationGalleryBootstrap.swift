import Foundation

import SymphonyValidationGallery

enum ValidationGalleryBootstrapAction: Equatable, Sendable {
  case open(ValidationBundleSource, rememberRecent: Bool)
  case restoreLastOpenedBundle
  case none
}

enum ValidationGalleryBootstrapResolver {
  static func resolve(
    arguments: [String],
    environment: [String: String],
    bundledFixtureSource: ValidationBundleSource? = ValidationGalleryFixtureLocator.bundledFixtureSource
  ) -> ValidationGalleryBootstrapAction {
    if let bundlePath = environment["XCODE_VALIDATION_GALLERY_UI_TEST_BUNDLE_PATH"],
      bundlePath.isEmpty == false
    {
      return .open(.folder(URL(fileURLWithPath: bundlePath)), rememberRecent: false)
    }

    if let manifestPath = environment["XCODE_VALIDATION_GALLERY_UI_TEST_MANIFEST_PATH"],
      manifestPath.isEmpty == false
    {
      return .open(.manifestFile(URL(fileURLWithPath: manifestPath)), rememberRecent: false)
    }

    if environment["XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE"] == "1",
      let bundledFixtureSource
    {
      return .open(bundledFixtureSource, rememberRecent: false)
    }

    if arguments.contains("--ui-testing") {
      return .none
    }

    return .restoreLastOpenedBundle
  }
}
