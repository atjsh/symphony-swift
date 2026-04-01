import Foundation
import SwiftUI
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct ValidationGalleryCommentExportFile: Equatable, Sendable {
  public let relativePath: String
  public let data: Data

  public init(relativePath: String, data: Data) {
    self.relativePath = relativePath
    self.data = data
  }
}

public struct ValidationGalleryPreparedCommentExport: Sendable {
  public let rootDirectoryName: String
  public let payload: ValidationGalleryCommentExportPayload
  public let files: [ValidationGalleryCommentExportFile]

  public init(
    rootDirectoryName: String,
    payload: ValidationGalleryCommentExportPayload,
    files: [ValidationGalleryCommentExportFile]
  ) {
    self.rootDirectoryName = rootDirectoryName
    self.payload = payload
    self.files = files
  }
}

@MainActor
public protocol ValidationGalleryCommentExportPreparing {
  func prepareExport(
    from store: ValidationGalleryStore,
    options: ValidationGalleryCommentExportOptions
  ) throws -> ValidationGalleryPreparedCommentExport
}

@MainActor
public struct ValidationGalleryCommentExportCoordinator: ValidationGalleryCommentExportPreparing {
  public init() {}

  public func prepareExport(
    from store: ValidationGalleryStore,
    options: ValidationGalleryCommentExportOptions
  ) throws -> ValidationGalleryPreparedCommentExport {
    let payload = try store.exportCommentsPayload(options: options)
    guard payload.comments.isEmpty == false else {
      throw ValidationGalleryError.loadFailed("Add a comment before exporting.")
    }

    let manifestData = try makeManifestData(payload)
    var files = [ValidationGalleryCommentExportFile(relativePath: "comments.json", data: manifestData)]

    if options.applyAreaDiagram {
      for entry in payload.comments {
        let data = try renderAnnotatedImage(for: entry)
        files.append(
          ValidationGalleryCommentExportFile(
            relativePath: "media/\(entry.exportedMediaFilename)",
            data: data
          )
        )
      }
    } else {
      var exportedFilenames = Set<String>()
      for entry in payload.comments where exportedFilenames.insert(entry.exportedMediaFilename).inserted {
        let sourceURL = URL(fileURLWithPath: entry.imagePath)
        let data = try Data(contentsOf: sourceURL)
        files.append(
          ValidationGalleryCommentExportFile(
            relativePath: "media/\(entry.exportedMediaFilename)",
            data: data
          )
        )
      }
    }

    return ValidationGalleryPreparedCommentExport(
      rootDirectoryName: Self.defaultRootDirectoryName(exportedAt: payload.exportedAt),
      payload: payload,
      files: files.sorted { $0.relativePath < $1.relativePath }
    )
  }

  public static func defaultRootDirectoryName(exportedAt: Date) -> String {
    "validation-comments-\(timestampFormatter.string(from: exportedAt))"
  }

  private func makeManifestData(_ payload: ValidationGalleryCommentExportPayload) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(payload)
  }

  private func renderAnnotatedImage(
    for entry: ValidationGalleryCommentExportPayload.CommentEntry
  ) throws -> Data {
    let sourceURL = URL(fileURLWithPath: entry.imagePath)
    guard
      let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw ValidationGalleryError.loadFailed("Could not load \(sourceURL.lastPathComponent) for export rendering.")
    }

    let color = ValidationGalleryAnnotationColor(rawValue: entry.annotationColor) ?? .red
    let content = ValidationGalleryCommentExportRenderView(
      baseImage: cgImage,
      entry: entry,
      annotationColor: color
    )
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    guard let renderedImage = renderer.cgImage else {
      throw ValidationGalleryError.loadFailed("Could not render the exported annotation preview.")
    }

    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw ValidationGalleryError.loadFailed("Could not create a PNG export destination.")
    }

    CGImageDestinationAddImage(destination, renderedImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw ValidationGalleryError.loadFailed("Could not finalize the exported annotation image.")
    }

    return data as Data
  }

  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }()
}

private struct ValidationGalleryCommentExportRenderView: View {
  let baseImage: CGImage
  let entry: ValidationGalleryCommentExportPayload.CommentEntry
  let annotationColor: ValidationGalleryAnnotationColor

  private var imageSize: CGSize {
    CGSize(width: baseImage.width, height: baseImage.height)
  }

  private var accentColor: Color {
    switch annotationColor {
    case .red:
      .red
    case .orange:
      .orange
    case .yellow:
      .yellow
    case .green:
      .green
    case .blue:
      .blue
    case .indigo:
      .indigo
    case .violet:
      .purple
    case .white:
      .white
    case .gray:
      .gray
    case .black:
      .black
    }
  }

  private var badgeForeground: Color {
    switch annotationColor {
    case .yellow, .white, .gray:
      .black
    default:
      .white
    }
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      Image(decorative: baseImage, scale: 1)
        .resizable()
        .interpolation(.high)
        .frame(width: imageSize.width, height: imageSize.height)

      overlay
    }
    .frame(width: imageSize.width, height: imageSize.height)
    .background(Color.clear)
  }

  @ViewBuilder
  private var overlay: some View {
    switch entry.anchor.kind {
    case "point":
      if let point = pixelPoint {
        ZStack {
          Circle()
            .fill(accentColor)
          Circle()
            .strokeBorder(.white.opacity(0.92), lineWidth: 3)
          Text("\(entry.annotationID)")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(badgeForeground)
        }
        .frame(width: 56, height: 56)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
        .position(x: point.x, y: point.y)
      }
    default:
      if let rect = pixelRect {
        let highlightRect = CGRect(
          x: rect.minX,
          y: rect.minY,
          width: rect.width,
          height: rect.height
        )

        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(accentColor, lineWidth: 6)
            .background(
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accentColor.opacity(0.12))
            )

          Text("\(entry.annotationID)")
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(badgeForeground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(accentColor, in: Capsule())
            .overlay {
              Capsule()
                .strokeBorder(.white.opacity(0.88), lineWidth: 2)
            }
            .padding(12)
        }
        .frame(width: highlightRect.width, height: highlightRect.height)
        .position(x: highlightRect.midX, y: highlightRect.midY)
      }
    }
  }

  private var pixelPoint: CGPoint? {
    if let point = entry.anchor.pixelPoint {
      return CGPoint(x: point.x, y: point.y)
    }
    guard let point = entry.anchor.normalizedPoint else {
      return nil
    }
    return CGPoint(x: point.x * imageSize.width, y: point.y * imageSize.height)
  }

  private var pixelRect: CGRect? {
    if let rect = entry.anchor.pixelRect {
      return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
    guard let rect = entry.anchor.normalizedRect else {
      return nil
    }
    return CGRect(
      x: rect.x * imageSize.width,
      y: rect.y * imageSize.height,
      width: rect.width * imageSize.width,
      height: rect.height * imageSize.height
    )
  }
}
