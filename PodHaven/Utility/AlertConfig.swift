// Copyright Justin Bishop, 2025

import SwiftUI

struct AlertConfig {
  public let title: String
  public var actions: () -> AnyView
  public var message: () -> AnyView

  public init(
    title: String,
    @ViewBuilder actions: @escaping () -> some View = {
      Button("OK", action: {})
    },
    @ViewBuilder message: @escaping () -> some View = {
      EmptyView()
    }
  ) {
    self.title = title
    self.actions = { AnyView(actions()) }
    self.message = { AnyView(message()) }
  }
}

extension View {
  func customAlert(_ config: Binding<AlertConfig?>) -> some View {
    alert(
      config.wrappedValue?.title ?? "",
      isPresented: Binding(
        get: { config.wrappedValue != nil },
        set: { isShown in
          if !isShown {
            config.wrappedValue = nil
          }
        }
      ),
      actions: {
        if let actions = config.wrappedValue?.actions() {
          actions
        }
      },
      message: {
        if let message = config.wrappedValue?.message() {
          message
        }
      }
    )
  }
}

