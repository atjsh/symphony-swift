import ImageIO
import SwiftUI

#if os(macOS)
  import AppKit
  private typealias PlatformImage = NSImage
#endif

#if os(iOS)
  import UIKit
  private typealias PlatformImage = UIImage
#endif

actor ValidationGalleryThumbnailLoader {
  static let shared = ValidationGalleryThumbnailLoader()

  private var cache: [URL: PlatformImage] = [:]

  func thumbnail(for url: URL, maxPixelSize: Int) async -> Image? {
    if let cached = cache[url] {
      return swiftUIImage(from: cached)
    }

    let loaded = await Task.detached(priority: .userInitiated) {
      Self.loadFromDisk(url: url, maxPixelSize: maxPixelSize)
    }.value

    guard let loaded else {
      return nil
    }

    cache[url] = loaded
    return swiftUIImage(from: loaded)
  }

  private func swiftUIImage(from platformImage: PlatformImage) -> Image {
    #if os(macOS)
      Image(nsImage: platformImage)
    #elseif os(iOS)
      Image(uiImage: platformImage)
    #endif
  }

  private var fullImageCache: [URL: (PlatformImage, CGSize)] = [:]

  func fullImage(for url: URL) async -> ValidationGalleryLoadedImage? {
    if let (cached, size) = fullImageCache[url] {
      return ValidationGalleryLoadedImage(image: swiftUIImage(from: cached), pixelSize: size)
    }

    let result = await Task.detached(priority: .userInitiated) {
      Self.loadFullImageFromDisk(url: url)
    }.value

    guard let (platformImage, pixelSize) = result else {
      return nil
    }

    fullImageCache[url] = (platformImage, pixelSize)
    return ValidationGalleryLoadedImage(image: swiftUIImage(from: platformImage), pixelSize: pixelSize)
  }

  private static func loadFullImageFromDisk(url: URL) -> (PlatformImage, CGSize)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }

    let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)

    #if os(macOS)
      return (NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)), pixelSize)
    #elseif os(iOS)
      return (UIImage(cgImage: cgImage), pixelSize)
    #endif
  }

  private static func loadFromDisk(url: URL, maxPixelSize: Int) -> PlatformImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }

    #if os(macOS)
      return NSImage(
        cgImage: cgImage,
        size: NSSize(width: cgImage.width, height: cgImage.height)
      )
    #elseif os(iOS)
      return UIImage(cgImage: cgImage)
    #endif
  }
}
