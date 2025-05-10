// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct PodcastResultsView: View {
  @State private var viewModel: PodcastResultsViewModel

  init(viewModel: PodcastResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      HTMLText(viewModel.unsavedPodcast.description)
        .lineLimit(3)
        .padding(.horizontal)

      if viewModel.subscribable {
        Button("Subscribe") {
          viewModel.subscribe()
        }
      }

      HStack {
        SearchBar(
          text: $viewModel.episodeList.entryFilter,
          placeholder: "Filter episodes",
          imageName: "line.horizontal.3.decrease.circle"
        )

        Menu(
          content: {
            Button(viewModel.unplayedOnly ? "Show All" : "Unplayed Only") {
              viewModel.unplayedOnly.toggle()
            }
          },
          label: {
            Image(systemName: "line.horizontal.3.decrease.circle")
          }
        )
      }
      .padding(.horizontal)

      if viewModel.unsavedEpisodes.isEmpty {
        Text("Loading episodes")
      } else {
        List(viewModel.episodeList.filteredEntries, id: \.guid) { unsavedEpisode in
          NavigationLink(
            value: UnsavedPodcastEpisode(
              unsavedPodcast: viewModel.unsavedPodcast,
              unsavedEpisode: unsavedEpisode
            ),
            label: {
              EpisodeListResultsView(
                viewModel: EpisodeListResultsViewModel(
                  isSelected: $viewModel.episodeList.isSelected[unsavedEpisode],
                  item: unsavedEpisode,
                  isSelecting: viewModel.episodeList.isSelecting
                )
              )
            }
          )
          .episodeQueueableSwipeActions(viewModel: viewModel, episode: unsavedEpisode)
        }
        .animation(.default, value: viewModel.episodeList.filteredEntries)
      }
    }
    .navigationTitle(viewModel.unsavedPodcast.title)
    .navigationDestination(
      for: UnsavedPodcastEpisode.self,
      destination: { unsavedPodcastEpisode in
        EpisodeResultsView(
          viewModel: EpisodeResultsViewModel(
            unsavedPodcastEpisode: unsavedPodcastEpisode
          )
        )
      }
    )
    .queueableSelectableEpisodesToolbar(viewModel: viewModel, episodeList: $viewModel.episodeList)
    .task { await viewModel.execute() }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var viewModel: PodcastResultsViewModel?
  @ObservationIgnored @LazyInjected(\.repo) var repo

  NavigationStack {
    if let viewModel = viewModel {
      PodcastResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let unsavedPodcast = try! await PreviewHelpers.loadUnsavedPodcast()
    if let existingPodcastSeries = try? await repo.podcastSeries(unsavedPodcast.feedURL) {
      try! await repo.delete(existingPodcastSeries.id)
    }
    viewModel = PodcastResultsViewModel(
      searchedPodcast: SearchedPodcast(searchedText: "News", unsavedPodcast: unsavedPodcast)
    )
  }
}
#endif
