// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct PodcastResultsDetailView: View {
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: PodcastResultsDetailViewModel

  init(viewModel: PodcastResultsDetailViewModel) {
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

        if viewModel.episodeList.filteredEntries.isEmpty {
          Divider()
          Text("No matching episodes found.").foregroundColor(.secondary)
          Spacer()
        } else {
          List(viewModel.episodeList.filteredEntries, id: \.guid) { unsavedEpisode in
            NavigationLink(
              value: SearchedPodcastEpisode(
                searchedText: viewModel.searchedText,
                unsavedPodcastEpisode: UnsavedPodcastEpisode(
                  unsavedPodcast: viewModel.unsavedPodcast,
                  unsavedEpisode: unsavedEpisode
                )
              ),
              label: {
                EpisodeResultsListView(
                  viewModel: EpisodeResultsListViewModel(
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
          .queueableSelectableEpisodesToolbar(
            viewModel: viewModel,
            episodeList: $viewModel.episodeList
          )
        }
      } else {
        Divider()
        Text("Loading episodes")
      }
    }
    .navigationTitle(viewModel.unsavedPodcast.title)
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  @Previewable @State var viewModel: PodcastResultsDetailViewModel?
  @ObservationIgnored @DynamicInjected(\.repo) var repo

  NavigationStack {
    if let viewModel {
      PodcastResultsDetailView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let unsavedPodcast = try! await PreviewHelpers.loadUnsavedPodcast()
    if let existingPodcastSeries = try? await repo.podcastSeries(unsavedPodcast.feedURL) {
      try! await repo.delete(existingPodcastSeries.id)
    }
    viewModel = PodcastResultsDetailViewModel(
      searchedPodcast: SearchedPodcast(searchedText: "News", unsavedPodcast: unsavedPodcast)
    )
  }
}
#endif
