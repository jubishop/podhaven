// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct TrendingCategoryGridView: View {
  @DynamicInjected(\.alert) private var alert

  @State private var viewModel: TrendingCategoryGridViewModel
  @State private var gridItemSize: CGFloat = 100

  init(viewModel: TrendingCategoryGridViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ScrollView {
      switch viewModel.state {
      case .loading:
        ProgressView("Loading \(viewModel.category) podcasts...")

      case .loaded(let unsavedPodcasts):
        ItemGrid(items: unsavedPodcasts) { unsavedPodcast in
          NavigationLink(
            value: Navigation.Destination.podcast(DisplayedPodcast(unsavedPodcast)),
            label: {
              SquareImage(
                image: unsavedPodcast.image,
                size: $gridItemSize
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
