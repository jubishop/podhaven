// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct TrendingItemDetailView: View {
  @Environment(Alert.self) var alert

  private let viewModel: TrendingItemDetailViewModel

  init(viewModel: TrendingItemDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(spacing: 40) {
      HTMLText(viewModel.unsavedPodcast.description)
        .lineLimit(3)
        .padding(.horizontal)

      if viewModel.subscribable {
        Button("Subscribe") {
          viewModel.subscribe()
        }
      }

      if viewModel.unsavedEpisodes.isEmpty {
        Text("Loading episodes")
      } else {
        List(viewModel.unsavedEpisodes, id: \.guid) { unsavedEpisode in
          NavigationLink(
            value: UnsavedPodcastEpisode(
              unsavedPodcast: viewModel.unsavedPodcast,
              unsavedEpisode: unsavedEpisode
            ),
            label: {
              TrendingItemEpisodeListView(unsavedEpisode: unsavedEpisode)
            }
          )
        }
        .navigationDestination(
          for: UnsavedPodcastEpisode.self,
          destination: { unsavedPodcastEpisode in
            TrendingItemEpisodeDetailView(
              viewModel: TrendingItemEpisodeDetailViewModel(
                unsavedPodcastEpisode: unsavedPodcastEpisode
              )
            )
          }
        )
      }
    }
    .navigationTitle(viewModel.unsavedPodcast.title)
    .task { await viewModel.execute() }
  }
}

#Preview {
  @Previewable @State var viewModel: TrendingItemDetailViewModel?
  @ObservationIgnored @LazyInjected(\.repo) var repo

  NavigationStack {
    if let viewModel = viewModel {
      TrendingItemDetailView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let unsavedPodcast = try! await PreviewHelpers.loadUnsavedPodcast()
    if let existingPodcastSeries = try? await repo.podcastSeries(unsavedPodcast.feedURL) {
      try! await repo.delete(existingPodcastSeries.id)
    }
    viewModel = TrendingItemDetailViewModel(
      category: "News",
      unsavedPodcast: try! await PreviewHelpers.loadUnsavedPodcast()
    )
  }
}
