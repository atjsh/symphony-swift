import Foundation

#if os(macOS)
  import AppKit
#endif

#if os(iOS)
  import UIKit
#endif

@MainActor
enum ValidationGalleryClipboard {
  static func copy(_ text: String) {
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #elseif os(iOS)
      UIPasteboard.general.string = text
    #endif
  }
}
