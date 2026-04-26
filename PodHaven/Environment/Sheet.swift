// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import OSLog
import SwiftUI

extension Container {
  @MainActor var sheet: Factory<Sheet> {
    Factory(self) { @MainActor in Sheet() }.scope(.cached)
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
  // Per-presentation identity. Each callAsFunction creates a new SheetConfig
  // with a fresh UUID so SwiftUI's `.sheet(item:)` sees an identity change and
  // re-presents. This avoids the bool-based `.sheet(isPresented:)` failure
  // mode where a stale non-nil config can leave the binding's isPresented
  // wedged at true and silently swallow new presentations.
  let id = UUID()

  // Optional user-supplied key for deduping rapid duplicate presentations of
  // the same logical thing (e.g., presenting the same EpisodeDetail twice in
  // succession should be a no-op, not a dismiss-and-re-present flicker).
  let userID: AnyHashable?

  let content: AnyView

  init<Content: View>(userID: AnyHashable?, @ViewBuilder content: @escaping () -> Content) {
    self.userID = userID
    self.content = AnyView(content())
  }
}

extension View {
  func customSheet(_ config: Binding<SheetConfig?>) -> some View {
    sheet(item: config) { sheetConfig in
      sheetConfig.content
        .onDisappear {
          // Defensive desync recovery for the bug we're fixing: if SwiftUI's
          // binding-setter never fires during dismissal, `config` stays
          // non-nil and a re-present with the same userID would short-circuit
          // via dedup. Clearing here makes that dedup naturally fail. The id
          // guard avoids racing with a freshly-presented sheet.
          if config.wrappedValue?.id == sheetConfig.id {
            Sheet.log.debug(
              """
              onDisappear: clearing stale config
                id: \(sheetConfig.id)
                userID: \(String(describing: sheetConfig.userID))
              """
            )
            config.wrappedValue = nil
          }
        }
    }
  }
}
