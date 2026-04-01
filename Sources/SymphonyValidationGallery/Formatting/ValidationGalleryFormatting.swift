import Foundation
import SymphonyXcodeValidation

public enum ValidationGalleryFormatting {
  static func platformTitle(_ platform: String) -> String {
    switch platform {
    case "macos":
      "macOS"
    case "ios":
      "iPhone"
    case "ipados":
      "iPad"
    default:
      prettifyToken(platform)
    }
  }

  static func planTitle(_ plan: String) -> String {
    switch plan {
    case "app":
      "App"
    case "app-tests":
      "App Tests"
    case "ui-tests":
      "UI Tests"
    default:
      prettifyToken(plan)
    }
  }

  static func checkpointTitle(_ checkpoint: String) -> String {
    prettifyToken(checkpoint)
  }

  static func artifactTitle(_ artifact: ValidationGalleryArtifact) -> String {
    if artifact.record.surface == artifact.record.checkpoint {
      return checkpointTitle(artifact.record.surface)
    }
    return "\(checkpointTitle(artifact.record.surface)) · \(checkpointTitle(artifact.record.checkpoint))"
  }

  static func artifactBrowserSubtitle(_ artifact: ValidationGalleryArtifact) -> String {
    [
      artifact.record.orientation,
      artifact.record.variant,
    ]
    .filter { $0.isEmpty == false }
    .joined(separator: " · ")
  }

  static func artifactInspectorSummary(_ artifact: ValidationGalleryArtifact) -> String {
    let typeDescriptor: String
    if artifact.record.variant.isEmpty {
      typeDescriptor = artifact.record.artifactType.rawValue
    } else {
      typeDescriptor = "\(artifact.record.variant) \(artifact.record.artifactType.rawValue)"
    }

    return [
      platformTitle(artifact.record.platform),
      planTitle(artifact.record.plan),
      artifact.record.orientation,
      typeDescriptor,
    ]
    .filter { $0.isEmpty == false }
      .joined(separator: " · ")
  }

  static func assetTitle(_ artifact: ValidationGalleryArtifact) -> String {
    let typeTitle = artifact.record.artifactType == .video ? "Video" : "Screenshot"
    return "\(artifactTitle(artifact)) \(typeTitle)"
  }

  static func sidebarSelectionTitle(_ selection: ValidationGallerySidebarSelection) -> String {
    switch selection {
    case .all:
      "All Artifacts"
    case .platform(let platform):
      platformTitle(platform)
    case .plan(let platform, let plan):
      "\(platformTitle(platform)) · \(planTitle(plan))"
    }
  }

  static func resultCountSummary(_ count: Int) -> String {
    switch count {
    case 0:
      "No results"
    case 1:
      "1 result"
    default:
      "\(count) results"
    }
  }

  public static func noResultsDescription(searchText: String, visibleScopeTitle: String) -> String {
    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedSearchText.isEmpty {
      return "No artifacts are visible in \(visibleScopeTitle). Clear or change the current filters to keep browsing."
    }

    return
      "No artifacts match “\(trimmedSearchText)” in \(visibleScopeTitle). Try a different term or clear the search to keep browsing."
  }

  public static func exportSummaryDescription(applyAreaDiagram: Bool) -> String {
    if applyAreaDiagram {
      return "Saved screenshots include numbered markers for each comment."
    }

    return "Saved screenshots stay unmarked, and comment numbering remains in comments.json."
  }

  public static func emptyExportDescription(scope: ValidationGalleryCommentExportScope) -> String {
    switch scope {
    case .selectedArtifact:
      "Add a comment to this screenshot to enable Export."
    case .currentBundle:
      "Add at least one comment in this bundle to enable Export."
    }
  }

  public static func exportAnnotationColorDescription(_ color: ValidationGalleryAnnotationColor) -> String {
    "Numbered markers use \(color.displayName.lowercased()) in exported media."
  }

  static func selectionUpdatedMessage(for artifact: ValidationGalleryArtifact) -> String {
    "The previous selection is hidden by the current filters, so \(artifactTitle(artifact)) is now selected."
  }

  static func inspectorEmptyStateTitle(hasActiveFilters: Bool) -> String {
    if hasActiveFilters {
      return "No Artifact in View"
    }

    return "Choose an Artifact"
  }

  static func inspectorEmptyStateDescription(hasActiveFilters: Bool) -> String {
    if hasActiveFilters {
      return "Clear or change the current filters to restore the detail view."
    }

    return "Select a screenshot or video from the browser to inspect its preview, metadata, and audit context."
  }

  static func commentListEmptyDescription(isAddingComment: Bool) -> String {
    if isAddingComment {
      return "Place a marker on the screenshot to create the first comment."
    }

    return "Choose Add Comment from the detail view to place the first marker on this screenshot."
  }

  static var discardDraftTitle: String {
    "Discard New Comment?"
  }

  static var discardDraftMessage: String {
    "This draft comment hasn’t been saved yet."
  }

  static func deleteCommentTitle(annotationID: Int) -> String {
    "Delete Comment #\(annotationID)?"
  }

  static var deleteCommentMessage: String {
    "This removes the comment from the screenshot and from any future export."
  }

  static func recentBundleTitle(_ recent: ValidationRecentBundle) -> String {
    let displayName = normalizedRecentDisplayName(for: recent)
    guard looksOpaque(recentLabel: displayName) else {
      return displayName
    }

    return recent.kind == .manifestFile ? "Manifest File" : "Validation Bundle"
  }

  static func recentBundleSubtitle(_ recent: ValidationRecentBundle) -> String? {
    let displayName = normalizedRecentDisplayName(for: recent)
    let url = URL(fileURLWithPath: recent.fallbackPath)

    if looksOpaque(recentLabel: displayName) {
      return displayName
    }

    switch recent.kind {
    case .folder:
      let parent = url.deletingLastPathComponent().lastPathComponent
      return parent.isEmpty ? nil : parent
    case .manifestFile:
      let parent = url.deletingLastPathComponent().lastPathComponent
      return parent.isEmpty ? url.lastPathComponent : "\(parent) • \(url.lastPathComponent)"
    }
  }

  public static func recentBundleMenuTitle(_ recent: ValidationRecentBundle) -> String {
    let title = recentBundleTitle(recent)
    let displayName = normalizedRecentDisplayName(for: recent)
    guard title != displayName, let subtitle = recentBundleSubtitle(recent) else {
      return title
    }

    return "\(title) (\(subtitle))"
  }

  static func outcomeTitle(_ outcome: ValidationOutcome) -> String {
    switch outcome {
    case .passed:
      "Passed"
    case .failed:
      "Failed"
    }
  }

  static func outcomeSymbolName(_ outcome: ValidationOutcome) -> String {
    switch outcome {
    case .passed:
      "checkmark.circle.fill"
    case .failed:
      "exclamationmark.triangle.fill"
    }
  }

  static func sourceBundleTitle(_ artifact: ValidationGalleryArtifact) -> String {
    let sourceResultBundle = artifact.record.sourceResultBundle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard sourceResultBundle.isEmpty == false else {
      return "Unknown Result Bundle"
    }

    let lastPathComponent = (sourceResultBundle as NSString).lastPathComponent
    return resultBundleTitle(fromPath: lastPathComponent.isEmpty ? sourceResultBundle : lastPathComponent)
  }

  static func resultBundleTitle(fromPath path: String) -> String {
    let filename = (path as NSString).lastPathComponent
    let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedFilename.isEmpty == false else {
      return "Result Bundle"
    }

    let baseName = (trimmedFilename as NSString).deletingPathExtension
    let extensionName = (trimmedFilename as NSString).pathExtension.lowercased()
    let titleSuffix = extensionName == "xcresult" ? " Result Bundle" : ""
    let tokens = baseName
      .split(separator: "-")
      .map(String.init)

    guard let platformToken = tokens.first else {
      return prettifyToken(baseName) + titleSuffix
    }

    let descriptorTokens = Array(tokens.dropFirst())
    let platform = platformTitle(platformToken)
    if platform == prettifyToken(platformToken) {
      return prettifyToken(baseName) + titleSuffix
    }

    let descriptor = resultBundleDescriptorTitle(tokens: descriptorTokens)
    if descriptor.isEmpty {
      return platform + titleSuffix
    }

    return "\(platform) \(descriptor)\(titleSuffix)"
  }

  static func summaryCounts(from artifacts: [ValidationGalleryArtifact]) -> (screenshots: Int, videos: Int) {
    (
      screenshots: artifacts.filter { $0.record.artifactType == .screenshot }.count,
      videos: artifacts.filter { $0.record.artifactType == .video }.count
    )
  }

  static func accessibilitySlug(for artifact: ValidationGalleryArtifact) -> String {
    [
      artifact.record.platform,
      artifact.record.plan,
      artifact.record.checkpoint,
      artifact.record.variant,
      artifact.record.artifactType.rawValue,
    ]
    .map(sanitizeForIdentifier)
    .joined(separator: "-")
  }

  static func sanitizeForIdentifier(_ value: String) -> String {
    value
      .lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }

  private static func prettifyToken(_ value: String) -> String {
    value
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .split(separator: " ")
      .map { token in
        let lowercased = token.lowercased()
        if lowercased == "ui" {
          return "UI"
        }
        return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
      }
      .joined(separator: " ")
  }

  private static func resultBundleDescriptorTitle(tokens: [String]) -> String {
    switch tokens {
    case ["app"]:
      return "App"
    case ["app", "tests"]:
      return "App Tests"
    case ["ui", "tests"]:
      return "UI Tests"
    case ["rich", "media"]:
      return "Rich Media"
    default:
      return prettifyToken(tokens.joined(separator: "-"))
    }
  }

  private static func normalizedRecentDisplayName(for recent: ValidationRecentBundle) -> String {
    let trimmedName = recent.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedName.isEmpty == false {
      return trimmedName
    }

    let fallbackURL = URL(fileURLWithPath: recent.fallbackPath)
    let fallbackName = fallbackURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    if fallbackName.isEmpty == false {
      return fallbackName
    }

    return recent.kind == .manifestFile ? "Manifest File" : "Validation Bundle"
  }

  private static func looksOpaque(recentLabel: String) -> Bool {
    recentLabel.range(
      of: #"^[0-9]{6,}(?:[-_][0-9]+)*$"#,
      options: .regularExpression
    ) != nil
  }
}
