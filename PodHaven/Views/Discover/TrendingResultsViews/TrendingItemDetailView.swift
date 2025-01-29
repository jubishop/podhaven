// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingItemDetailView: View {
  @Environment(Alert.self) var alert

  private let viewModel: TrendingItemDetailViewModel

  init(viewModel: TrendingItemDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(spacing: 40) {
      Text(viewModel.feedResult.title)
        .font(.largeTitle)
      HTMLText(viewModel.feedResult.description)
      Button(
        action: {
          Task { try await viewModel.subscribe() }
        },
        label: {
          Text("Subscribe")
        }
      )
      if viewModel.unsavedEpisodes.isEmpty {
        Text("Loading episodes")
      } else if let unsavedPodcast = viewModel.unsavedPodcast {
        List(viewModel.unsavedEpisodes, id: \.guid) { unsavedEpisode in
          NavigationLink(
            value: unsavedEpisode,
            // TODO: Make this TrendingItemEpisodeListView
            label: { Text(unsavedEpisode.title) }
          )
        }
        .navigationDestination(for: UnsavedEpisode.self) { unsavedEpisode in
          TrendingItemEpisodeDetailView(unsavedPodcast, unsavedEpisode)
        }
      }
    }
    .navigationTitle(viewModel.category)
    .task {
      do {
        try await viewModel.fetchFeed()
      } catch {
        alert.andReport(error)
      }
    }
  }
}

#Preview {
  @Previewable @State var viewModel: TrendingItemDetailViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      TrendingItemDetailView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    viewModel = TrendingItemDetailViewModel(
      category: "News",
      feedResult: try! await PreviewHelpers.loadFeedResult()
    )
  }
}
