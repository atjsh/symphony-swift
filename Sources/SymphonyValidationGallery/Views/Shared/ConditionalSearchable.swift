import SwiftUI

/// Applies `.searchable()` only when `isEnabled` is true, avoiding duplicate
/// `com.apple.SwiftUI.search` toolbar items when multiple searchable views
/// coexist in the same window (e.g. embedded inside a TabView alongside
/// another view that already provides its own `.searchable()`).
///
/// When disabled, an inline search field is rendered in the toolbar instead.
struct ConditionalSearchable: ViewModifier {
  @Binding var text: String
  var isEnabled: Bool

  func body(content: Content) -> some View {
    if isEnabled {
      content.searchable(text: $text, prompt: "Filter artifacts")
    } else {
      content.toolbar {
        ToolbarItem(placement: .automatic) {
          TextField("Filter artifacts", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 160, maxWidth: 240)
            .accessibilityLabel("Filter artifacts")
        }
      }
    }
  }
}
