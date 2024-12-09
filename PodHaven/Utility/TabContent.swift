// Copyright Justin Bishop, 2024

import SwiftUI

struct TabContent<Content: View>: View {
  @State private var alert = Alert.shared
  @Binding var height: CGFloat

  let content: Content

  init(height: Binding<CGFloat>, @ViewBuilder content: () -> Content) {
    self._height = height
    self.content = content()
  }

  var body: some View {
    content
      .toolbarBackground(.visible, for: .tabBar)
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.size.height
      } action: { newHeight in
        height = newHeight
        print("setting new internalTab Height: \(newHeight)")
      }
  }
}

#Preview {
  TabView {
    Tab("Preview", systemImage: "gear") {
      TabContent(height: .constant(0)) { Text("Hello World") }
    }
  }
}
