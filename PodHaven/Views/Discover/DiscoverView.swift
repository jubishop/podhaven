// Copyright Justin Bishop, 2025

import SwiftUI

struct DiscoverView: View {
  @State private var navigation = Navigation.shared
  @State private var viewModel = DiscoverViewModel()

  var body: some View {
    NavigationStack(path: $navigation.discoverPath) {
      ScrollView {
        switch viewModel.currentView {
        case .allFields:
          TrendingResultView()
        case .titles:
          TitlesResultView()
        case .people:
          PeopleResultView()
        case .trending:
          TrendingResultView()
        default: fatalError("currentView unknonw: \(viewModel.currentView)")
        }
      }
      .navigationTitle("Discover")
      .searchable(
        text: $viewModel.searchText,
        tokens: $viewModel.currentTokens,
        suggestedTokens: .constant(viewModel.allTokens),
        isPresented: $viewModel.searchPresented
      ) { token in
        HStack {
          let imageName =
            switch token {
            case .trending:
              "chart.line.uptrend.xyaxis"
            case .allFields:
              "line.3.horizontal.decrease.circle"
            case .titles:
              "text.book.closed"
            case .people:
              "person"
            case .category(_):
              "square.grid.2x2"
            }
          Image(systemName: imageName)
          Text(token.text)
        }
      }
      .onSubmit(of: .search, viewModel.searchSubmitted)
      .overlay(alignment: .top) {
        if viewModel.showSearchWarning {
          Text("Must Enter A Search Query")
            .padding()
            .background(Color(.systemBackground))
        }
        if viewModel.showCategories {
          ScrollView {
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
            .background(Color(.systemBackground))
          }
        }
      }
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
