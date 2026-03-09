// Copyright Justin Bishop, 2026

import SwiftUI

struct OptionalLink<Content: View>: View {
  let url: URL?
  @ViewBuilder let content: Content

  var body: some View {
    if let url {
      Link(destination: url) { content }
    } else {
      content
    }
  }
}
