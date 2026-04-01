#if os(macOS)
import SwiftUI

func workflowStepHeader(
  eyebrow: String,
  title: String,
  message: String
) -> some View {
  VStack(alignment: .leading, spacing: 10) {
    Text(eyebrow.uppercased())
      .font(.caption2.weight(.bold))
      .tracking(0.6)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        Capsule(style: .continuous)
          .fill(Color.accentColor.opacity(0.08))
      )
      .overlay(
        Capsule(style: .continuous)
          .strokeBorder(Color.accentColor.opacity(0.14), lineWidth: 1)
      )
      .foregroundStyle(Color.accentColor)
    Text(title)
      .font(.title3.weight(.semibold))
    Text(message)
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
  .frame(maxWidth: .infinity, alignment: .leading)
}

func workflowInlineError(message: String) -> some View {
  Label {
    Text(message)
      .font(.callout)
  } icon: {
    Image(systemName: "exclamationmark.triangle.fill")
      .foregroundStyle(.orange)
  }
  .padding(12)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(Color.orange.opacity(0.12))
  )
  .overlay(
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
  )
}

func workflowSection<Content: View>(
  title: String,
  subtitle: String,
  isExpanded: Binding<Bool>,
  @ViewBuilder content: @escaping () -> Content
) -> some View {
  GroupBox {
    DisclosureGroup(isExpanded: isExpanded) {
      VStack(alignment: .leading, spacing: 14) {
        content()
      }
      .padding(.top, 10)
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline.weight(.semibold))
        Text(subtitle)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, 2)
    }
  }
}

func workflowTextField(
  _ title: String,
  text: Binding<String>,
  identifier: String
) -> some View {
  VStack(alignment: .leading, spacing: 6) {
    Text(title)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.secondary)
    TextField(title, text: text)
      .textFieldStyle(.roundedBorder)
      .accessibilityIdentifier(identifier)
  }
}

func workflowTextEditor(
  _ title: String,
  text: Binding<String>,
  identifier: String,
  footer: String,
  idealHeight: CGFloat
) -> some View {
  VStack(alignment: .leading, spacing: 6) {
    Text(title)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.secondary)
    TextEditor(text: text)
      .font(.body)
      .frame(idealHeight: idealHeight)
      .padding(6)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color(nsColor: .textBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
      )
      .accessibilityIdentifier(identifier)
    Text(footer)
      .font(.footnote)
      .foregroundStyle(.secondary)
  }
}
#endif
