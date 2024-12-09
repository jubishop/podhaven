// Copyright Justin Bishop, 2024

import SwiftUI

struct TabContent<Content: View>: View {
  @State private var alert = Alert.shared

  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .toolbarBackground(.visible, for: .tabBar)
  }
}

#Preview {
  TabView {
    Tab("Preview", systemImage: "gear") {
      TabContent { Text("Hello World") }
    }
  }
}
