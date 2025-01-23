// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct DiscoverView: View {
  @Environment(Alert.self) var alert

  @State private var navigation = Container.shared.navigation()
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
        .onSubmit(of: .search) {
          Task {
            do {
              try await viewModel.searchSubmitted()
            } catch {
              alert.andReport(error)
            }
          }
        }
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
    .task {
      do {
        try await viewModel.runSearch()
      } catch {
        alert.andReport(error)
      }
    }
  }
}

#Preview {
  DiscoverView()
    .preview()
}
