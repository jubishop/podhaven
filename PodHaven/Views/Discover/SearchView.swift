// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct SearchView: View {
  @Environment(Alert.self) var alert

  @State private var navigation = Container.shared.navigation()
  @State private var viewModel = SearchViewModel()

  var body: some View {
    NavigationStack(path: $navigation.searchPath) {
      ResultsView(viewModel: viewModel)
        .searchable(
          text: $viewModel.searchText,
          tokens: $viewModel.currentTokens,
          suggestedTokens: .constant(viewModel.allTokens),
          isPresented: $viewModel.searchPresented
        ) { token in
          SearchTokenView(token: token)
        }
        .onSubmit(of: .search, viewModel.searchSubmitted)
        .navigationBarTitle("Search")
        .background(
          SizeReader { size in
            viewModel.width = size.width
          }
          .padding()
        )
        .overlay(alignment: .top) {
          if viewModel.showSearchWarning {
            SearchWarning(warning: "Must Enter A Search Query")
          }
          if viewModel.showCategories {
            CategoryGrid(viewModel: viewModel)
          }
        }
    }
    .task { await viewModel.execute() }
  }
}

#if DEBUG
#Preview {
  SearchView()
    .preview()
}
#endif
