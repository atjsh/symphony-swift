import SwiftUI

// MARK: - Commands

struct SymphonyCommands: Commands {
  var commandModel: SymphonyCommandModel

  init(model: SymphonyOperatorModel) {
    self.commandModel = SymphonyCommandModel(model: model)
  }

  var body: some Commands {
    CommandGroup(after: .appSettings) {
      Button("Server…") {
        commandModel.openServerEditor()
      }
      .keyboardShortcut(",", modifiers: .command)
    }

    CommandGroup(after: .newItem) {
      Button("Refresh Issues") {
        commandModel.refresh()
      }
      .keyboardShortcut("r", modifiers: .command)
      .disabled(commandModel.model.isConnecting || commandModel.model.isRefreshing)

      Divider()

      Button("Connect") {
        commandModel.connect()
      }
      .keyboardShortcut("k", modifiers: .command)
      .disabled(commandModel.model.isConnecting)
    }
  }
}

// MARK: - Command Model

@MainActor
@Observable
final class SymphonyCommandModel {
  let model: SymphonyOperatorModel

  init(model: SymphonyOperatorModel) {
    self.model = model
  }

  func openServerEditor() {
    #if os(macOS)
      NotificationCenter.default.post(
        name: .symphonyOpenServerEditor,
        object: nil
      )
    #endif
  }

  func refresh() {
    Task { await model.refresh() }
  }

  func connect() {
    Task { await model.connect() }
  }
}

extension Notification.Name {
  static let symphonyOpenServerEditor = Notification.Name("symphonyOpenServerEditor")
}
