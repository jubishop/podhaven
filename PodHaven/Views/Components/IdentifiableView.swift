// Copyright Justin Bishop, 2025

import SwiftUI

struct IdentifiableView<Content: View, ID: Hashable>: View {
  let content: Content
  let viewID: ID

  init(_ content: Content, id: ID) {
    self.content = content
    self.viewID = id
  }

  var body: some View {
    content.id(viewID)
  }
}
