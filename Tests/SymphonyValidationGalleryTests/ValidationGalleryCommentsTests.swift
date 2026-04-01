import CoreGraphics
import Testing

@testable import SymphonyValidationGallery

@Suite("ValidationGalleryAnnotationColor")
struct ValidationGalleryAnnotationColorTests {
  @Test func annotationColorsRoundTripThroughCGColor() {
    for color in ValidationGalleryAnnotationColor.allCases {
      #expect(ValidationGalleryAnnotationColor(cgColor: color.cgColor) == color)
    }
  }

  @Test func annotationColorMatchingIgnoresOpacityAndChoosesNearestPaletteColor() {
    #expect(
      ValidationGalleryAnnotationColor(
        cgColor: CGColor(red: 0.02, green: 0.20, blue: 0.98, alpha: 0.18)
      ) == .blue
    )
    #expect(
      ValidationGalleryAnnotationColor(
        cgColor: CGColor(gray: 0.54, alpha: 0.42)
      ) == .gray
    )
  }
}
