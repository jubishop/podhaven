// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SearchView: View {
  @DynamicInjected(\.alert) private var alert
  @InjectedObservable(\.navigation) private var navigation

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
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  SearchView()
    .preview()
}
#endif
