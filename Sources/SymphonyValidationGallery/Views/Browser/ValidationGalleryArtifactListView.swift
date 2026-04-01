import SwiftUI

struct ValidationGalleryRegularArtifactList: View {
  let artifacts: [ValidationGalleryArtifact]
  let selectedArtifactID: ValidationGalleryArtifact.ID?
  let onSelectArtifact: (ValidationGalleryArtifact.ID?) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(artifacts.enumerated()), id: \.element.id) { index, artifact in
        Button {
          onSelectArtifact(artifact.id)
        } label: {
          HStack(alignment: .top, spacing: 12) {
            ValidationGalleryArtifactListThumbnail(artifact: artifact)

            VStack(alignment: .leading, spacing: 4) {
              Text(ValidationGalleryFormatting.artifactTitle(artifact))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

              Text(ValidationGalleryFormatting.artifactBrowserSubtitle(artifact))
                .font(.footnote)
                .foregroundStyle(validationGalleryMutedForeground(opacity: 0.94))
                .fixedSize(horizontal: false, vertical: true)

              Text(ValidationGalleryFormatting.sourceBundleTitle(artifact))
                .font(.footnote.monospaced())
                .foregroundStyle(validationGalleryMutedForeground(opacity: 0.82))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .background(
            selectedArtifactID == artifact.id
              ? Color.accentColor.opacity(0.10)
              : Color.clear
          )
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

        if index < artifacts.count - 1 {
          Divider()
            .padding(.leading, 82)
        }
      }
    }
  }
}

struct ValidationGalleryArtifactListThumbnail: View {
  let artifact: ValidationGalleryArtifact

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.secondary.opacity(0.08))

      if artifact.record.artifactType == .video {
        Image(systemName: "play.rectangle.fill")
          .font(.title3)
          .foregroundStyle(validationGalleryMutedForeground())
      } else {
        ValidationGalleryThumbnailView(
          url: artifact.fileURL,
          isAvailable: artifact.isAvailable,
          minimumHeight: 52,
          maximumHeight: 52
        )
      }
    }
    .frame(width: 56, height: 56)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .accessibilityHidden(true)
  }
}
