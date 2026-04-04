import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SymphonyValidationGallery

@Suite("ValidationGalleryThumbnailLoader")
struct ValidationGalleryThumbnailLoaderTests {

  @Test func loadValidImageReturnsThumbnail() async throws {
    let (loader, imageURL) = try makeLoaderWithTestImage(width: 200, height: 200)
    let result = await loader.thumbnail(for: imageURL, maxPixelSize: 100)
    #expect(result != nil)
  }

  @Test func loadSameURLTwiceReturnsCachedResult() async throws {
    let (loader, imageURL) = try makeLoaderWithTestImage(width: 200, height: 200)

    let first = await loader.thumbnail(for: imageURL, maxPixelSize: 100)
    #expect(first != nil)

    // Remove file so only cache can serve it
    try FileManager.default.removeItem(at: imageURL)

    let second = await loader.thumbnail(for: imageURL, maxPixelSize: 100)
    #expect(second != nil)
  }

  @Test func loadNonExistentURLReturnsNil() async {
    let loader = ValidationGalleryThumbnailLoader()
    let fakeURL = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).png")
    let result = await loader.thumbnail(for: fakeURL, maxPixelSize: 100)
    #expect(result == nil)
  }

  @Test func loadCorruptFileReturnsNil() async throws {
    let tempDir = try makeTempDirectory()
    let corruptURL = tempDir.appendingPathComponent("corrupt.png")
    try Data("not a real png".utf8).write(to: corruptURL)

    let loader = ValidationGalleryThumbnailLoader()
    let result = await loader.thumbnail(for: corruptURL, maxPixelSize: 100)
    #expect(result == nil)
  }

  @Test func loadZeroByteFileReturnsNil() async throws {
    let tempDir = try makeTempDirectory()
    let emptyURL = tempDir.appendingPathComponent("empty.png")
    try Data().write(to: emptyURL)

    let loader = ValidationGalleryThumbnailLoader()
    let result = await loader.thumbnail(for: emptyURL, maxPixelSize: 100)
    #expect(result == nil)
  }

  @Test func separateInstancesHaveIndependentCaches() async throws {
    let (loader1, imageURL) = try makeLoaderWithTestImage(width: 100, height: 100)
    let loader2 = ValidationGalleryThumbnailLoader()

    let result1 = await loader1.thumbnail(for: imageURL, maxPixelSize: 50)
    #expect(result1 != nil)

    // Remove the file — loader1 has it cached, loader2 does not
    try FileManager.default.removeItem(at: imageURL)

    let cached = await loader1.thumbnail(for: imageURL, maxPixelSize: 50)
    #expect(cached != nil)

    let uncached = await loader2.thumbnail(for: imageURL, maxPixelSize: 50)
    #expect(uncached == nil)
  }

  // MARK: - Helpers

  private func makeLoaderWithTestImage(
    width: Int,
    height: Int
  ) throws -> (ValidationGalleryThumbnailLoader, URL) {
    let tempDir = try makeTempDirectory()
    let imageURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).png")
    try writeTestPNG(to: imageURL, width: width, height: height)
    return (ValidationGalleryThumbnailLoader(), imageURL)
  }

  private func makeTempDirectory() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("thumbnail-loader-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    return tempDir
  }

  private func writeTestPNG(to url: URL, width: Int, height: Int) throws {
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      let cgImage = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw ThumbnailTestError.couldNotCreateTestImage
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
      throw ThumbnailTestError.couldNotWriteTestImage
    }
  }
}

private enum ThumbnailTestError: Error {
  case couldNotCreateTestImage
  case couldNotWriteTestImage
}
