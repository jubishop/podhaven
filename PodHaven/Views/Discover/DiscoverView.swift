// Copyright Justin Bishop, 2025

import SwiftUI

struct DiscoverView: View {
  @State private var navigation = Navigation.shared
  @State private var viewModel = DiscoverViewModel()

  var body: some View {
    NavigationStack(path: $navigation.discoverPath) {
      ScrollView {
        if viewModel.showCategories {
          TokenGridView(tokens: SearchService.categories, width: viewModel.width) { category in
            Button(action: {
              viewModel.categorySelected(category)
            }) {
              Text(category)
                .font(.caption)
                .padding(4)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(4)
            }
          }
        }
      }
      .searchable(
        text: $viewModel.searchText,
        tokens: $viewModel.currentTokens,
        suggestedTokens: .constant(viewModel.allTokens)
      ) { token in Text(token.rawValue) }
      .navigationTitle("Discover")
    }
    .onGeometryChange(for: CGFloat.self) { geometry in
      geometry.size.width
    } action: { newWidth in
      viewModel.width = newWidth
    }
  }
}

#Preview {
  DiscoverView().preview()
}
