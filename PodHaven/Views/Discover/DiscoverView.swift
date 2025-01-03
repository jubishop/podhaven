// Copyright Justin Bishop, 2025 

import SwiftUI

struct DiscoverView: View {
  @State private var navigation = Navigation.shared
  @State private var viewModel = DiscoverViewModel()

  var body: some View {
    NavigationStack(path: $navigation.discoverPath) {
      Form {
      }
      .navigationTitle("Discover")
    }
  }
}

#Preview {
    DiscoverView()
}
