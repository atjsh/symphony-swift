import SwiftUI

struct ValidationGalleryFilterStatusBar: View {
  @Bindable var store: ValidationGalleryStore

  var body: some View {
    #if os(iOS)
      VStack(alignment: .leading, spacing: 8) {
        contextSummary
        if store.hasActiveFilters {
          clearFiltersButton
        }
      }
    #else
      HStack(alignment: .top, spacing: 16) {
        if store.filterContextSummary.isEmpty == false {
          HStack(alignment: .top) {
            contextSummary
            if store.hasActiveFilters {
              clearFiltersButton
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    #endif
  }

  private var contextSummary: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(store.resultCountSummary)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("validation-gallery-result-count-summary")
      Text(store.visibleScopeTitle)
        .font(.footnote)
        .foregroundStyle(validationGalleryMutedForeground(opacity: 0.94))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("validation-gallery-visible-scope-title")
      if store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
        Text("Filter: \u{201c}\(store.searchText.trimmingCharacters(in: .whitespacesAndNewlines))\u{201d}")
          .font(.footnote.monospaced())
          .foregroundStyle(validationGalleryMutedForeground(opacity: 0.94))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var clearFiltersButton: some View {
    Button("Clear Filters") {
      store.clearFilters()
    }
    .buttonStyle(.borderless)
    .padding(.vertical, 8)
    .frame(minHeight: 44, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityIdentifier("clear-filters-button")
  }
}

struct ValidationGallerySelectionFeedbackStrip: View {
  let feedback: ValidationGallerySelectionFeedback
  let onDismiss: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
        .foregroundStyle(validationGalleryMutedForeground())
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(feedback.title)
          .font(.footnote.weight(.semibold))
        Text(feedback.message)
          .font(.footnote)
          .foregroundStyle(validationGalleryMutedForeground())
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      Button("Dismiss", action: onDismiss)
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .padding(12)
    .background(
      validationGalleryPanelBackgroundColor(),
      in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
  }
}

struct ValidationGalleryFilteredEmptyStateView: View {
  @Bindable var store: ValidationGalleryStore

  var body: some View {
    VStack {
      ContentUnavailableView {
        VStack(spacing: 10) {
          Image(systemName: "line.3.horizontal.decrease.circle")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(validationGalleryMutedForeground())
            .accessibilityHidden(true)

          Text("No Matching Artifacts")
            .font(.title2.weight(.bold))
            .foregroundStyle(.primary)
            .accessibilityIdentifier("validation-gallery-no-results-state")
        }
      } description: {
        VStack(spacing: 8) {
          Text(store.noResultsDescription)
            .font(.body)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

          Text(store.visibleScopeTitle)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.primary)

          if store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            Text("Filter: \u{201c}\(store.searchText.trimmingCharacters(in: .whitespacesAndNewlines))\u{201d}")              .font(.footnote.monospaced())
              .foregroundStyle(.primary)
          }
        }
      } actions: {
        Button("Clear Filters") {
          store.clearFilters()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(minHeight: 44)
        .tint(validationGalleryProminentActionTint())
        .accessibilityIdentifier("clear-filters-button")
      }
    }
    .frame(maxWidth: .infinity, minHeight: 280)
    .padding(.horizontal, 24)
    .padding(.vertical, 28)
  }
}
