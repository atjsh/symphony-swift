import SwiftUI

struct ValidationGalleryArtifactCard: View, Equatable {
  let artifact: ValidationGalleryArtifact
  let isSelected: Bool
  let onSelect: () -> Void

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.artifact == rhs.artifact && lhs.isSelected == rhs.isSelected
  }

  var body: some View {
    Button(action: onSelect) {
      VStack(alignment: .leading, spacing: 10) {
        ZStack(alignment: .topTrailing) {
          Group {
            if artifact.record.artifactType == .video {
              ValidationGalleryVideoPreview(
                url: artifact.fileURL,
                isAvailable: artifact.isAvailable,
                minimumHeight: 120,
                maximumHeight: 120
              )
            } else {
              ValidationGalleryThumbnailView(
                url: artifact.fileURL,
                isAvailable: artifact.isAvailable,
                minimumHeight: 120,
                maximumHeight: 120
              )
            }
          }
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

          if artifact.record.artifactType == .video {
            Label("Video", systemImage: "play.fill")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.primary)
              .padding(.horizontal, 8)
              .padding(.vertical, 5)
              .background(.regularMaterial, in: Capsule())
              .padding(8)
          }
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(ValidationGalleryFormatting.artifactTitle(artifact))
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

          Text(ValidationGalleryFormatting.artifactBrowserSubtitle(artifact))
            .font(.footnote)
            .foregroundStyle(validationGalleryMutedForeground())
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

          Text(ValidationGalleryFormatting.sourceBundleTitle(artifact))
            .font(.footnote.monospaced())
            .foregroundStyle(validationGalleryMutedForeground(opacity: 0.8))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(
            isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.10),
            lineWidth: isSelected ? 1.5 : 1
          )
      }
      .accessibilityHidden(true)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(ValidationGalleryFormatting.artifactTitle(artifact))
    .accessibilityValue(
      "\(ValidationGalleryFormatting.planTitle(artifact.record.plan)), \(ValidationGalleryFormatting.artifactBrowserSubtitle(artifact))"
    )
    .accessibilityHint("Opens the selected validation artifact.")
    .accessibilityIdentifier(
      "artifact-card-\(ValidationGalleryFormatting.accessibilitySlug(for: artifact))"
    )
  }
}

struct ValidationGalleryArtifactRow: View {
  let artifact: ValidationGalleryArtifact

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Group {
        if artifact.record.artifactType == .video {
          Image(systemName: "play.rectangle.fill")
            .font(.title3)
            .foregroundStyle(Color.accentColor)
        } else {
          Image(systemName: "photo.fill")
            .font(.title3)
            .foregroundStyle(validationGalleryMutedForeground())
        }
      }
      .frame(width: 28)

      VStack(alignment: .leading, spacing: 4) {
        Text(ValidationGalleryFormatting.artifactTitle(artifact))
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Text(
          "\(ValidationGalleryFormatting.planTitle(artifact.record.plan)) · \(ValidationGalleryFormatting.artifactBrowserSubtitle(artifact))"
        )
          .font(.footnote)
          .foregroundStyle(validationGalleryMutedForeground(opacity: 0.94))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Text(ValidationGalleryFormatting.sourceBundleTitle(artifact))
          .font(.footnote.monospaced())
          .foregroundStyle(validationGalleryMutedForeground(opacity: 0.9))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 4)
  }
}
