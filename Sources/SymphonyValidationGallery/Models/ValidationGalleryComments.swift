import CoreGraphics
import Foundation

public enum ValidationGalleryAnnotationColor: String, Codable, CaseIterable, Equatable, Sendable {
  case red
  case orange
  case yellow
  case green
  case blue
  case indigo
  case violet
  case white
  case gray
  case black

  public var displayName: String {
    switch self {
    case .red:
      "Red"
    case .orange:
      "Orange"
    case .yellow:
      "Yellow"
    case .green:
      "Green"
    case .blue:
      "Blue"
    case .indigo:
      "Indigo"
    case .violet:
      "Violet"
    case .white:
      "White"
    case .gray:
      "Gray"
    case .black:
      "Black"
    }
  }

  public var cgColor: CGColor {
    let components = srgbComponents
    return CGColor(
      red: components.red,
      green: components.green,
      blue: components.blue,
      alpha: 1
    )
  }

  public init(cgColor: CGColor) {
    let components = Self.srgbComponents(from: cgColor)
    self = Self.allCases.min(by: { lhs, rhs in
      lhs.distanceSquared(to: components) < rhs.distanceSquared(to: components)
    }) ?? .red
  }

  private var srgbComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) {
    switch self {
    case .red:
      (1, 0, 0)
    case .orange:
      (1, 0.584, 0)
    case .yellow:
      (1, 0.8, 0)
    case .green:
      (0.204, 0.78, 0.349)
    case .blue:
      (0, 0.478, 1)
    case .indigo:
      (0.345, 0.337, 0.839)
    case .violet:
      (0.686, 0.321, 0.871)
    case .white:
      (1, 1, 1)
    case .gray:
      (0.557, 0.557, 0.576)
    case .black:
      (0, 0, 0)
    }
  }

  private func distanceSquared(to other: (red: CGFloat, green: CGFloat, blue: CGFloat)) -> CGFloat {
    let components = srgbComponents
    let redDistance = components.red - other.red
    let greenDistance = components.green - other.green
    let blueDistance = components.blue - other.blue
    return (redDistance * redDistance) + (greenDistance * greenDistance) + (blueDistance * blueDistance)
  }

  private static func srgbComponents(
    from cgColor: CGColor
  ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
    if let convertedColor = cgColor.converted(
      to: CGColorSpace(name: CGColorSpace.sRGB) ?? cgColor.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
      intent: .defaultIntent,
      options: nil
    ), let components = convertedColor.components {
      if components.count >= 3 {
        return (components[0], components[1], components[2])
      }
      if components.count == 2 {
        return (components[0], components[0], components[0])
      }
    }

    if let components = cgColor.components {
      if components.count >= 3 {
        return (components[0], components[1], components[2])
      }
      if components.count == 2 {
        return (components[0], components[0], components[0])
      }
    }

    return (1, 0, 0)
  }
}

public struct ValidationGalleryNormalizedPoint: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct ValidationGalleryNormalizedRect: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public enum ValidationGalleryCommentAnchor: Codable, Equatable, Sendable {
  case point(ValidationGalleryNormalizedPoint)
  case area(ValidationGalleryNormalizedRect)
}

public struct ValidationGalleryCommentDraft: Equatable, Sendable {
  public let artifactID: ValidationGalleryArtifact.ID
  public let anchor: ValidationGalleryCommentAnchor
  public var body: String

  public init(
    artifactID: ValidationGalleryArtifact.ID,
    anchor: ValidationGalleryCommentAnchor,
    body: String = ""
  ) {
    self.artifactID = artifactID
    self.anchor = anchor
    self.body = body
  }
}

public struct ValidationGalleryComment: Equatable, Sendable, Identifiable {
  public let id: String
  public let artifactID: ValidationGalleryArtifact.ID
  public let body: String
  public let anchor: ValidationGalleryCommentAnchor
  public let createdAt: Date

  public init(
    id: String = UUID().uuidString,
    artifactID: ValidationGalleryArtifact.ID,
    body: String,
    anchor: ValidationGalleryCommentAnchor,
    createdAt: Date
  ) {
    self.id = id
    self.artifactID = artifactID
    self.body = body
    self.anchor = anchor
    self.createdAt = createdAt
  }
}

public struct ValidationGalleryNumberedComment: Equatable, Sendable, Identifiable {
  public let annotationID: Int
  public let comment: ValidationGalleryComment

  public var id: ValidationGalleryComment.ID {
    comment.id
  }

  public init(annotationID: Int, comment: ValidationGalleryComment) {
    self.annotationID = annotationID
    self.comment = comment
  }
}

public enum ValidationGalleryCommentExportScope: Sendable {
  case selectedArtifact
  case currentBundle
}

public struct ValidationGalleryCommentExportOptions: Equatable, Sendable {
  public var scope: ValidationGalleryCommentExportScope
  public var applyAreaDiagram: Bool
  public var annotationColor: ValidationGalleryAnnotationColor

  public init(
    scope: ValidationGalleryCommentExportScope,
    applyAreaDiagram: Bool = true,
    annotationColor: ValidationGalleryAnnotationColor = .red
  ) {
    self.scope = scope
    self.applyAreaDiagram = applyAreaDiagram
    self.annotationColor = annotationColor
  }
}

public struct ValidationGalleryCommentExportPayload: Codable, Equatable, Sendable {
  public struct CommentEntry: Codable, Equatable, Sendable {
    public struct AnchorPayload: Codable, Equatable, Sendable {
      public let kind: String
      public let normalizedPoint: ValidationGalleryNormalizedPoint?
      public let normalizedRect: ValidationGalleryNormalizedRect?
      public let pixelPoint: ValidationGalleryNormalizedPoint?
      public let pixelRect: ValidationGalleryNormalizedRect?

      public init(
        kind: String,
        normalizedPoint: ValidationGalleryNormalizedPoint?,
        normalizedRect: ValidationGalleryNormalizedRect?,
        pixelPoint: ValidationGalleryNormalizedPoint?,
        pixelRect: ValidationGalleryNormalizedRect?
      ) {
        self.kind = kind
        self.normalizedPoint = normalizedPoint
        self.normalizedRect = normalizedRect
        self.pixelPoint = pixelPoint
        self.pixelRect = pixelRect
      }

      enum CodingKeys: String, CodingKey {
        case kind
        case normalizedPoint = "normalized_point"
        case normalizedRect = "normalized_rect"
        case pixelPoint = "pixel_point"
        case pixelRect = "pixel_rect"
      }
    }

    public let commentID: String
    public let annotationID: Int
    public let artifactID: String
    public let artifactTitle: String
    public let platform: String
    public let plan: String
    public let checkpoint: String
    public let surface: String
    public let variant: String
    public let imagePath: String
    public let imageURL: String
    public let exportedMediaFilename: String
    public let renderApplied: Bool
    public let annotationColor: String
    public let comment: String
    public let anchor: AnchorPayload
    public let createdAt: Date

    public init(
      commentID: String,
      annotationID: Int,
      artifactID: String,
      artifactTitle: String,
      platform: String,
      plan: String,
      checkpoint: String,
      surface: String,
      variant: String,
      imagePath: String,
      imageURL: String,
      exportedMediaFilename: String,
      renderApplied: Bool,
      annotationColor: String,
      comment: String,
      anchor: AnchorPayload,
      createdAt: Date
    ) {
      self.commentID = commentID
      self.annotationID = annotationID
      self.artifactID = artifactID
      self.artifactTitle = artifactTitle
      self.platform = platform
      self.plan = plan
      self.checkpoint = checkpoint
      self.surface = surface
      self.variant = variant
      self.imagePath = imagePath
      self.imageURL = imageURL
      self.exportedMediaFilename = exportedMediaFilename
      self.renderApplied = renderApplied
      self.annotationColor = annotationColor
      self.comment = comment
      self.anchor = anchor
      self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
      case commentID = "comment_id"
      case annotationID = "annotation_id"
      case artifactID = "artifact_id"
      case artifactTitle = "artifact_title"
      case platform
      case plan
      case checkpoint
      case surface
      case variant
      case imagePath = "image_path"
      case imageURL = "image_url"
      case exportedMediaFilename = "exported_media_filename"
      case renderApplied = "render_applied"
      case annotationColor = "annotation_color"
      case comment
      case anchor
      case createdAt = "created_at"
    }
  }

  public let bundleRootPath: String
  public let manifestPath: String
  public let exportedAt: Date
  public let comments: [CommentEntry]

  public init(
    bundleRootPath: String,
    manifestPath: String,
    exportedAt: Date,
    comments: [CommentEntry]
  ) {
    self.bundleRootPath = bundleRootPath
    self.manifestPath = manifestPath
    self.exportedAt = exportedAt
    self.comments = comments
  }

  enum CodingKeys: String, CodingKey {
    case bundleRootPath = "bundle_root_path"
    case manifestPath = "manifest_path"
    case exportedAt = "exported_at"
    case comments
  }
}
