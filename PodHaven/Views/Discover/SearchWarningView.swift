// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchWarningView: View {
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
  SearchWarningView(warning: "Test Warning")
}
