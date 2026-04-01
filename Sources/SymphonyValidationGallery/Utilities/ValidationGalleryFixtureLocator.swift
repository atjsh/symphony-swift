import Foundation

public enum ValidationGalleryFixtureLocator {
  public static var bundledFixtureURL: URL? {
    Bundle.module.url(forResource: "XcodeValidationGalleryFixture", withExtension: nil)
  }

  public static var bundledFixtureSource: ValidationBundleSource? {
    bundledFixtureURL.map(ValidationBundleSource.folder)
  }
}
