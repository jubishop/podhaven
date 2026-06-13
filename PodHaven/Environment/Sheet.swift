// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import OSLog
import SwiftUI

extension Container {
  @MainActor var sheet: Factory<Sheet> {
    Factory(self) { Sheet() }.scope(.cached)
  }
}

@Observable @MainActor class Sheet {
  var config: SheetConfig?

  fileprivate static let log = Log.as("Sheet")

  fileprivate init() {}

  // MARK: - Public Sheet Presentation

  func callAsFunction<Content: View>(
    id: AnyHashable? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    if let id, config?.userID == id {
      Self.log.debug(
        """
        present: skipped — same id already presented
          id: \(id)
        """
      )
      return
    }

    let previousUserID = config?.userID
    config = SheetConfig(userID: id, content: content)
    Self.log.debug(
      """
      present
        userID: \(String(describing: id))
        previousUserID: \(String(describing: previousUserID))
      """
    )
  }

  func dismiss() {
    let wasPresented = config != nil
    let previousUserID = config?.userID
    config = nil
    Self.log.debug(
      """
      dismiss
        wasPresented: \(wasPresented)
        previousUserID: \(String(describing: previousUserID))
      """
    )
  }
}

@Observable @MainActor class SheetConfig: Identifiable {
  // Fresh per-presentation so .sheet(item:) sees an identity change on every call.
  let id = UUID()

  let userID: AnyHashable?
  let content: AnyView

  init<Content: View>(userID: AnyHashable?, @ViewBuilder content: @escaping () -> Content) {
    self.userID = userID
    self.content = AnyView(content())
  }
}

extension View {
  func customSheet(
    _ config: Binding<SheetConfig?>,
    alert alertConfig: Binding<AlertConfig?>? = nil
  ) -> some View {
    sheet(item: config) { sheetConfig in
      SheetContentView(config: config, sheetConfig: sheetConfig, alertConfig: alertConfig)
    }
  }
}

private struct SheetContentView: View {
  @Binding var config: SheetConfig?

  let sheetConfig: SheetConfig
  let alertConfig: Binding<AlertConfig?>?

  var body: some View {
    content
      .onDisappear {
        // Recover if SwiftUI's binding-setter doesn't fire on dismissal.
        if config?.id == sheetConfig.id {
          Sheet.log.debug(
            """
            onDisappear: clearing stale config
              id: \(sheetConfig.id)
              userID: \(String(describing: sheetConfig.userID))
            """
          )
          config = nil
        }
      }
  }

  @ViewBuilder private var content: some View {
    if let alertConfig {
      sheetConfig.content
        .customAlert(alertConfig)
    } else {
      sheetConfig.content
    }
  }
}
