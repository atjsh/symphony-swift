import Foundation
import CoreGraphics
import ImageIO

extension ValidationGalleryStore {

  public func exportCommentsPayload(
    scope: ValidationGalleryCommentExportScope
  ) throws -> ValidationGalleryCommentExportPayload {
    try exportCommentsPayload(options: ValidationGalleryCommentExportOptions(scope: scope))
  }

  public func exportCommentsPayload(
    options: ValidationGalleryCommentExportOptions
  ) throws -> ValidationGalleryCommentExportPayload {
    let comments = scopedNumberedComments(scope: options.scope)
      .map { makeCommentEntry($0, options: options) }

    return ValidationGalleryCommentExportPayload(
      bundleRootPath: snapshot?.bundleRootURL.path ?? "",
      manifestPath: snapshot?.manifestURL.path ?? "",
      exportedAt: now(),
      comments: comments
    )
  }

  public func exportCommentsJSONString(scope: ValidationGalleryCommentExportScope) throws -> String {
    try exportCommentsJSONString(options: ValidationGalleryCommentExportOptions(scope: scope))
  }

  public func exportCommentsJSONString(options: ValidationGalleryCommentExportOptions) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(exportCommentsPayload(options: options))
    return String(decoding: data, as: UTF8.self)
  }

  func scopedNumberedComments(
    scope: ValidationGalleryCommentExportScope
  ) -> [NumberedCommentItem] {
    switch scope {
    case .selectedArtifact:
      guard let selectedArtifactID else {
        return []
      }
      return numberedCurrentBundleComments().filter { $0.artifact.id == selectedArtifactID }
    case .currentBundle:
      return numberedCurrentBundleComments()
    }
  }

  func makeCommentEntry(
    _ item: NumberedCommentItem,
    options: ValidationGalleryCommentExportOptions
  ) -> ValidationGalleryCommentExportPayload.CommentEntry {
    let pixelSize = imagePixelSize(for: item.artifact.fileURL)

    return ValidationGalleryCommentExportPayload.CommentEntry(
      commentID: item.comment.id,
      annotationID: item.annotationID,
      artifactID: item.artifact.id,
      artifactTitle: ValidationGalleryFormatting.artifactTitle(item.artifact),
      platform: item.artifact.record.platform,
      plan: item.artifact.record.plan,
      checkpoint: item.artifact.record.checkpoint,
      surface: item.artifact.record.surface,
      variant: item.artifact.record.variant,
      imagePath: item.artifact.fileURL.path,
      imageURL: item.artifact.fileURL.absoluteURL.absoluteString,
      exportedMediaFilename: exportedMediaFilename(for: item, options: options),
      renderApplied: options.applyAreaDiagram,
      annotationColor: options.annotationColor.rawValue,
      comment: item.comment.body,
      anchor: makeAnchorPayload(item.comment.anchor, pixelSize: pixelSize),
      createdAt: item.comment.createdAt
    )
  }

  func makeAnchorPayload(
    _ anchor: ValidationGalleryCommentAnchor,
    pixelSize: CGSize?
  ) -> ValidationGalleryCommentExportPayload.CommentEntry.AnchorPayload {
    switch anchor {
    case .point(let point):
      return .init(
        kind: "point",
        normalizedPoint: point,
        normalizedRect: nil,
        pixelPoint: pixelSize.map {
          .init(
            x: roundedPixelValue(point.x * $0.width),
            y: roundedPixelValue(point.y * $0.height)
          )
        },
        pixelRect: nil
      )
    case .area(let rect):
      return .init(
        kind: "area",
        normalizedPoint: nil,
        normalizedRect: rect,
        pixelPoint: nil,
        pixelRect: pixelSize.map {
          .init(
            x: roundedPixelValue(rect.x * $0.width),
            y: roundedPixelValue(rect.y * $0.height),
            width: roundedPixelValue(rect.width * $0.width),
            height: roundedPixelValue(rect.height * $0.height)
          )
        }
      )
    }
  }

  func imagePixelSize(for fileURL: URL) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
      return nil
    }

    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Double,
      let height = properties[kCGImagePropertyPixelHeight] as? Double
    else {
      return nil
    }

    return CGSize(width: width, height: height)
  }

  func roundedPixelValue(_ value: Double) -> Double {
    (value * 1_000).rounded() / 1_000
  }

  func exportedMediaFilename(
    for item: NumberedCommentItem,
    options: ValidationGalleryCommentExportOptions
  ) -> String {
    if options.applyAreaDiagram {
      return String(
        format: "%03d-%@.png",
        item.annotationID,
        ValidationGalleryFormatting.accessibilitySlug(for: item.artifact)
      )
    }

    let slug = ValidationGalleryFormatting.accessibilitySlug(for: item.artifact)
    let pathExtension = item.artifact.fileURL.pathExtension.isEmpty ? "png" : item.artifact.fileURL.pathExtension
    return "artifact-\(slug).\(pathExtension.lowercased())"
  }
}
