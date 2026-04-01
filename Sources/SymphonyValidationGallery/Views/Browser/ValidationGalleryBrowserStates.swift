import SwiftUI

struct ValidationGalleryEmptyStateView: View {
  let onOpenBundle: () -> Void
  let onOpenManifest: () -> Void

  var body: some View {
    ValidationGalleryActionStateView(
      title: "Open a Validation Bundle",
      systemImage: "rectangle.stack.badge.plus",
      message: "Choose a local validation bundle folder or a manifest file to browse screenshots, videos, and audit notes.",
      primaryActionTitle: "Open Bundle",
      primaryAction: onOpenBundle,
      secondaryActionTitle: "Open Manifest",
      secondaryAction: onOpenManifest
    )
  }
}

struct ValidationGalleryErrorStateView: View {
  let error: ValidationGalleryError
  let onOpenBundle: () -> Void
  let onOpenManifest: () -> Void

  var body: some View {
    ValidationGalleryActionStateView(
      title: title,
      systemImage: "exclamationmark.triangle",
      message: "\(error.errorDescription ?? "Unknown error")\n\n\(recoverySuggestion)",
      primaryActionTitle: primaryActionTitle,
      primaryAction: primaryAction,
      secondaryActionTitle: secondaryActionTitle,
      secondaryAction: secondaryAction
    )
  }

  private var title: String {
    switch error {
    case .exportFailed:
      "Couldn't Export Comments"
    default:
      "Couldn't Open Bundle"
    }
  }

  private var primaryActionTitle: String {
    switch error {
    case .exportFailed:
      "Open Bundle"
    default:
      "Open Bundle"
    }
  }

  private var primaryAction: () -> Void {
    onOpenBundle
  }

  private var secondaryActionTitle: String {
    switch error {
    case .exportFailed:
      "Open Manifest"
    default:
      "Open Manifest"
    }
  }

  private var secondaryAction: () -> Void {
    onOpenManifest
  }

  private var recoverySuggestion: String {
    switch error {
    case .bookmarkStale:
      "Open the bundle again to relink the saved location."
    case .accessDenied:
      "Choose the bundle or manifest again to grant access."
    case .missingRequiredFile, .malformedJSON:
      "Open a different validation bundle or manifest with the required files."
    case .loadFailed:
      "Try reopening the bundle, or open the manifest directly if the folder layout is incomplete."
    case .exportFailed:
      "Try exporting again after checking the save location and write permissions."
    }
  }
}

struct ValidationGalleryActionStateView: View {
  let title: String
  let systemImage: String
  let message: String
  let primaryActionTitle: String
  let primaryAction: () -> Void
  let secondaryActionTitle: String
  let secondaryAction: () -> Void

  var body: some View {
    ViewThatFits(in: .vertical) {
      VStack(spacing: 0) {
        Spacer(minLength: 0)
        actionCard
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(24)

      ScrollView(.vertical) {
        actionCard
          .frame(maxWidth: 520)
          .padding(.horizontal, 24)
          .padding(.vertical, 32)
          .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var actionCard: some View {
    VStack(spacing: 24) {
      Image(systemName: systemImage)
        .font(.system(size: 34, weight: .medium))
        .foregroundStyle(.primary)
        .accessibilityHidden(true)

      VStack(spacing: 10) {
        Text(title)
          .font(.title2.weight(.semibold))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity)

        Text(message)
          .font(.body)
          .foregroundStyle(validationGalleryMutedForeground())
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity)
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          primaryActionButton
          secondaryActionButton
        }

        VStack(spacing: 10) {
          primaryActionButton
          secondaryActionButton
        }
      }
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: 520, minHeight: 280)
    .padding(.horizontal, 20)
    .padding(.vertical, 24)
  }

  private var primaryActionButton: some View {
    ValidationGalleryActionButton(
      title: primaryActionTitle,
      prominence: .primary,
      action: primaryAction
    )
      .accessibilityIdentifier("open-validation-bundle-button")
  }

  private var secondaryActionButton: some View {
    ValidationGalleryActionButton(
      title: secondaryActionTitle,
      prominence: .secondary,
      action: secondaryAction
    )
      .accessibilityIdentifier("open-manifest-button")
  }
}

struct ValidationGalleryActionButton: View {
  enum Prominence {
    case primary
    case secondary
  }

  let title: String
  let prominence: Prominence
  let action: () -> Void

  var body: some View {
    Group {
      switch prominence {
      case .primary:
        Button(title, action: action)
          .buttonStyle(.borderedProminent)
          .tint(validationGalleryProminentActionTint())
      case .secondary:
        Button(title, action: action)
          .buttonStyle(.bordered)
      }
    }
    .controlSize(.large)
    .font(.headline.weight(.semibold))
    .frame(maxWidth: .infinity)
  }
}
