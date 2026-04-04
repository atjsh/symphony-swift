import SwiftUI
import SymphonyXcodeValidationServerCore

/// Top-level runner container that routes between configuration and progress.
public struct ValidationRunnerView: View {
  @Bindable var store: ValidationRunnerStore

  public init(store: ValidationRunnerStore) {
    self.store = store
  }

  public var body: some View {
    Group {
      switch store.runStatus {
      case .idle:
        ValidationRunnerConfigurationView(store: store)
      case .running, .completed, .failed:
        ValidationRunnerProgressView(store: store)
      }
    }
    .navigationTitle("Validation Runner")
    #if os(macOS)
      .frame(minWidth: 400, minHeight: 300)
    #endif
  }
}
