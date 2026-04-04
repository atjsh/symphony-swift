import SwiftUI

@testable import SymphonySwiftUIApp

#if canImport(AppKit)
  import AppKit
#endif
#if canImport(UIKit)
  import UIKit
#endif

// MARK: - macOS Hosting

#if canImport(AppKit)
  @MainActor
  func fittingSize<V: View>(_ view: V) -> CGSize {
    let hostingView = NSHostingView(rootView: view)
    hostingView.layoutSubtreeIfNeeded()
    return hostingView.fittingSize
  }

  @MainActor
  func host<V: View>(
    _ view: V,
    width: CGFloat = 1280,
    height: CGFloat = 900
  ) -> NSHostingView<V> {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
    return hostingView
  }

  @MainActor
  func render<V: View>(_ hostingView: NSHostingView<V>) {
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()
  }
#endif

// MARK: - iOS Hosting

#if canImport(UIKit)
  @MainActor
  struct IOSHostedView<Content: View> {
    let window: UIWindow
    let controller: UIHostingController<Content>
  }

  @MainActor
  func host<V: View>(
    _ view: V,
    width: CGFloat = 1280,
    height: CGFloat = 900
  ) -> IOSHostedView<V> {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
    let controller = UIHostingController(rootView: view)
    window.rootViewController = controller
    window.isHidden = false
    controller.view.frame = window.bounds
    controller.loadViewIfNeeded()
    return IOSHostedView(window: window, controller: controller)
  }

  @MainActor
  func render<V: View>(_ hostingView: IOSHostedView<V>) {
    hostingView.controller.view.frame = hostingView.window.bounds
    hostingView.controller.view.setNeedsLayout()
    hostingView.controller.view.layoutIfNeeded()
  }
#endif

// MARK: - Exercise Helpers

@MainActor
func exercise<V: View>(
  _ view: V,
  width: CGFloat = 1280,
  height: CGFloat = 900
) {
  #if canImport(AppKit)
    render(host(view, width: width, height: height))
  #elseif canImport(UIKit)
    render(host(view, width: width, height: height))
  #else
    _ = view
  #endif
}

let operatorDetailPanelsSourceURL = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .appendingPathComponent("SymphonySwiftUIApp")
  .appendingPathComponent("Views")
  .appendingPathComponent("Detail")
  .appendingPathComponent("OperatorDetailView.swift")
