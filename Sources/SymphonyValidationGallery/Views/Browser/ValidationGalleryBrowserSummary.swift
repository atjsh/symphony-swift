import SwiftUI

struct ValidationGallerySummaryHeader: View {
  let snapshot: ValidationBundleSnapshot
  @State private var isBundleLocationExpanded = false

  var body: some View {
    let counts = ValidationGalleryFormatting.summaryCounts(from: snapshot.artifacts)

    VStack(alignment: .leading, spacing: 10) {
      Text("Loaded Bundle")
        .font(.caption.weight(.medium))
        .foregroundStyle(validationGalleryMutedForeground(opacity: 0.86))

      Text(snapshot.source.displayName)
        .font(.title3.weight(.semibold))
        .lineLimit(2)

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 18) {
          summaryStats(
            counts: counts,
            auditCount: snapshot.auditIssues.count,
            status: snapshot.summary.status.rawValue.capitalized
          )
        }

        VStack(alignment: .leading, spacing: 10) {
          summaryStats(
            counts: counts,
            auditCount: snapshot.auditIssues.count,
            status: snapshot.summary.status.rawValue.capitalized
          )
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Button {
          withAnimation(.easeInOut(duration: 0.18)) {
            isBundleLocationExpanded.toggle()
          }
        } label: {
          HStack(spacing: 10) {
            Text("Bundle Location")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Image(systemName: isBundleLocationExpanded ? "chevron.down" : "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(validationGalleryMutedForeground(opacity: 0.96))
              .accessibilityHidden(true)
          }
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the bundle path used to load this validation snapshot.")

        if isBundleLocationExpanded {
          Text(snapshot.bundleRootURL.path)
            .font(.footnote.monospaced())
            .foregroundStyle(validationGalleryMutedForeground(opacity: 0.94))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(.bottom, 4)
  }

  @ViewBuilder
  private func summaryStats(
    counts: (screenshots: Int, videos: Int),
    auditCount: Int,
    status: String
  ) -> some View {
    Group {
      ValidationGallerySummaryStat(
        label: "Status",
        value: status,
        symbolName: status == "Passed" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
      )
      ValidationGallerySummaryStat(label: "Screenshots", value: "\(counts.screenshots)")
      ValidationGallerySummaryStat(label: "Videos", value: "\(counts.videos)")
      ValidationGallerySummaryStat(label: "Audit", value: "\(auditCount)")
    }
  }
}

struct ValidationGalleryWarningStrip: View {
  let warnings: [ValidationBundleWarning]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Bundle Warnings", systemImage: "exclamationmark.triangle.fill")
        .font(.subheadline.weight(.semibold))
      ForEach(warnings) { warning in
        HStack(alignment: .top, spacing: 8) {
          Text("Warning")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())

          Text(warning.message)
            .font(.footnote)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(16)
    .background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.orange.opacity(0.08))
    }
  }
}

struct ValidationGallerySummaryStat: View {
  let label: String
  let value: String
  var symbolName: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(validationGalleryMutedForeground(opacity: 0.92))

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        if let symbolName {
          Image(systemName: symbolName)
            .font(.caption.weight(.semibold))
            .accessibilityHidden(true)
        }

        Text(value)
          .font(.headline.monospacedDigit().weight(.bold))
          .foregroundStyle(.primary)
      }
    }
  }
}
