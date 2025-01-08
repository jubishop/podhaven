// Copyright Justin Bishop, 2025

import SwiftUI

struct AlertConfig<Actions: View, Message: View> {
  let title: String
  let actions: Actions
  let message: Message

  init(
    title: String = "Error",
    @ViewBuilder actions: () -> Actions = { Button("Ok") {} },
    @ViewBuilder message: () -> Message
  ) {
    self.title = title
    self.actions = actions()
    self.message = message()
  }
}

extension View {
  func customAlert<Actions: View, Message: View>(_ config: Binding<AlertConfig<Actions, Message>?>)
    -> some View
  {
    alert(
      config.wrappedValue?.title ?? "",
      isPresented: Binding(
        get: { config.wrappedValue != nil },
        set: { if !$0 { config.wrappedValue = nil } }
      ),
      actions: { config.wrappedValue?.actions },
      message: { config.wrappedValue?.message }
    )
  }
}
