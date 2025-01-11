// Copyright Justin Bishop, 2025

import SwiftUI

struct DiscoverView: View {
  @State private var navigation = Navigation.shared
  @State private var viewModel = DiscoverViewModel()

  var body: some View {
    NavigationStack(path: $navigation.discoverPath) {
      SearchView(viewModel: viewModel)
        .searchable(
          text: $viewModel.searchText,
          tokens: $viewModel.currentTokens,
          suggestedTokens: .constant(viewModel.allTokens),
          isPresented: $viewModel.searchPresented
        ) { token in
          SearchTokenView(token: token)
        }
        .onSubmit(of: .search, viewModel.searchSubmitted)
        .overlay(alignment: .top) {
          if viewModel.showSearchWarning {
            SearchWarning(warning: "Must Enter A Search Query")
          }
          if viewModel.showCategories {
            CategoryGrid(viewModel: viewModel)
          }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
          geometry.size.width
        } action: { newWidth in
          viewModel.width = newWidth
        }
    }
  }
}

#Preview {
  DiscoverView().preview()
}
