import SwiftUI

#if os(macOS)
  import AppKit
#endif

#if os(iOS)
  import UIKit
#endif

func validationGalleryPanelBackgroundColor() -> Color {
  #if os(macOS)
    Color(nsColor: .controlBackgroundColor)
  #elseif os(iOS)
    Color(uiColor: .secondarySystemBackground)
  #else
    Color.primary.opacity(0.08)
  #endif
}

func validationGalleryMutedForeground(opacity: Double = 0.92) -> Color {
  Color.primary.opacity(opacity)
}

func validationGalleryProminentActionTint() -> Color {
  Color(red: 0.13, green: 0.29, blue: 0.66)
}

func validationGallerySecondaryActionBackgroundColor() -> Color {
  #if os(macOS)
    Color(nsColor: .windowBackgroundColor)
  #elseif os(iOS)
    Color(uiColor: .systemBackground)
  #else
    Color.primary.opacity(0.04)
  #endif
}
