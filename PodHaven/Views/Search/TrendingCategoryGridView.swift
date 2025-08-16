// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct TrendingCategoryGridView: View {
  @DynamicInjected(\.alert) private var alert

  @State private var viewModel: TrendingCategoryGridViewModel

  init(viewModel: TrendingCategoryGridViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ScrollView {
      switch viewModel.state {
      case .loading:
        ProgressView("Loading \(viewModel.category) podcasts...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding()

      case .loaded(let trendingSearchResult):
        ItemGrid(
          items: trendingSearchResult.result.convertibleFeeds.compactMap {
            try? $0.toUnsavedPodcast()
          }
        ) { unsavedPodcast in
          NavigationLink(
            value: Navigation.Search.Destination.category(trendingSearchResult.category),
            label: {
              SelectableGridItem(
                viewModel: SelectableListItemModel<UnsavedPodcast>(
                  isSelected: $viewModel.podcastList.isSelected[unsavedPodcast],
                  item: unsavedPodcast,
                  isSelecting: viewModel.isSelecting
                )
              )
            }
          )
        }
        .padding()

      case .error(let message):
        VStack {
          Text("Error")
            .font(.headline)
          Text(message)
            .foregroundColor(.secondary)
        }
        .padding()
      }
    }
    .navigationTitle(viewModel.category)
    .task(viewModel.execute)
  }
}
