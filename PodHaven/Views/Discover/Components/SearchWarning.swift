// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchWarning: View {
  private let warning: String

  init(warning: String) {
    self.warning = warning
  }

  var body: some View {
    Text(warning)
      .padding()
      .background(Color(.systemBackground))
  }
}

#Preview {
  SearchWarning(warning: "Test Warning")
    .preview()
}
