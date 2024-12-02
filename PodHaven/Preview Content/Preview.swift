// Copyright Justin Bishop, 2024

import Foundation
import SwiftUI

#if DEBUG
  struct Preview<Content: View>: View {
    @State private var navigation = Navigation()
    @State private var alert = Alert.shared

    let content: Content

    init(@ViewBuilder content: () -> Content) {
      self.content = content()
    }

    var body: some View {
      content
        .environment(navigation)
        .customAlert($alert.config)
    }
  }
#endif
