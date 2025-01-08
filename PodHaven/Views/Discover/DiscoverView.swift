// Copyright Justin Bishop, 2025

import SwiftUI

struct DiscoverView: View {
  @State private var navigation = Navigation.shared
  @State private var viewModel = DiscoverViewModel()

  var body: some View {
    NavigationStack(path: $navigation.discoverPath) {
      ScrollView {
      }
      .searchable(
        text: $viewModel.searchText,
        tokens: $viewModel.currentTokens,
        suggestedTokens: .constant(viewModel.allTokens)
      ) { token in Text(token.text) }
      .navigationTitle("Discover")
    }
  }
}

#Preview {
  DiscoverView().preview()
}
