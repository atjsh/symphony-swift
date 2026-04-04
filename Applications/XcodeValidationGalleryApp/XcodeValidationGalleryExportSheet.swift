import SwiftUI

import SymphonyValidationGallery

struct XcodeValidationGalleryExportSheet: View {
  @Bindable var controller: XcodeValidationGalleryExportController
  @Bindable var store: ValidationGalleryStore

  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let commentCount = controller.commentCount(using: store)

    NavigationStack {
      Form {
        Section {
          LabeledContent("Scope") {
            Text(scopeTitle)
          }
        }

        Section {
          LabeledContent("Comments") {
            Text("\(commentCount)")
              .monospacedDigit()
          }
          LabeledContent("Screenshots") {
            Text("\(controller.screenshotCount(using: store))")
              .monospacedDigit()
          }
        } header: {
          Text("Content")
        } footer: {
          if commentCount == 0 {
            Text(
              ValidationGalleryFormatting.emptyExportDescription(
                scope: controller.request?.options.scope ?? .selectedArtifact
              )
            )
          }
        }

        Section {
          Toggle("Apply Area Diagram", isOn: applyAreaDiagramBinding)
            .accessibilityIdentifier("export-apply-area-diagram-toggle")
        } header: {
          Text("Diagram")
        } footer: {
          Text(
            ValidationGalleryFormatting.exportSummaryDescription(
              applyAreaDiagram: controller.request?.options.applyAreaDiagram == true
            )
          )
        }

        Section {
          ColorPicker(
            "Annotation Color",
            selection: annotationCGColorBinding,
            supportsOpacity: false
          )
          .accessibilityIdentifier("export-annotation-color-picker")
        } header: {
          Text("Appearance")
        } footer: {
          Text(
            ValidationGalleryFormatting.exportAnnotationColorDescription(
              annotationColorBinding.wrappedValue
            )
          )
        }
      }
      .navigationTitle(scopeTitle)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            controller.cancelExport()
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Export") {
            Task {
              await controller.performExport(using: store)
              if controller.request == nil {
                dismiss()
              }
            }
          }
          .disabled(controller.commentCount(using: store) == 0)
          .accessibilityIdentifier("confirm-export-comments-button")
        }
      }
    }
    .presentationDetents(sheetDetents)
    .accessibilityIdentifier("export-comments-sheet")
  }

  private var scopeTitle: String {
    switch controller.request?.options.scope {
    case .selectedArtifact:
      "Export Comments"
    case .currentBundle:
      "Export Bundle Comments"
    case .none:
      "Export Comments"
    }
  }

  private var applyAreaDiagramBinding: Binding<Bool> {
    Binding(
      get: { controller.request?.options.applyAreaDiagram ?? true },
      set: { controller.request?.options.applyAreaDiagram = $0 }
    )
  }

  private var annotationColorBinding: Binding<ValidationGalleryAnnotationColor> {
    Binding(
      get: { controller.request?.options.annotationColor ?? .red },
      set: { controller.request?.options.annotationColor = $0 }
    )
  }

  private var annotationCGColorBinding: Binding<CGColor> {
    Binding(
      get: { annotationColorBinding.wrappedValue.cgColor },
      set: { annotationColorBinding.wrappedValue = ValidationGalleryAnnotationColor(cgColor: $0) }
    )
  }

  private var sheetDetents: Set<PresentationDetent> {
    dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
  }

}
