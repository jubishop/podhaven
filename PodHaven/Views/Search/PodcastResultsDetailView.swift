// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import NukeUI
import SwiftUI

struct PodcastResultsDetailView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: PodcastResultsDetailViewModel

  private static let log = Log.as(LogSubsystem.SearchView.podcastDetail)

  init(viewModel: PodcastResultsDetailViewModel) {
    Self.log.debug(
      """
      Showing PodcastResultsDetailView
        viewModel: \(viewModel.unsavedPodcast.title)
      """
    )
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(spacing: 4) {
      Group {
        PodcastHeaderView(
          podcast: viewModel.unsavedPodcast,
          subscribable: viewModel.subscribable,
          subscribeAction: viewModel.subscribe
        )

        PodcastAboutHeaderView(
          displayAboutSection: $viewModel.displayAboutSection,
          mostRecentEpisodeDate: viewModel.mostRecentEpisodeDate
        )
        if viewModel.displayAboutSection {
          Divider()
          PodcastMetadataView(
            mostRecentEpisodeDate: viewModel.mostRecentEpisodeDate,
            episodeCount: viewModel.episodeList.allEntries.count
          )
          Divider()
          PodcastExpandedAboutView(podcast: viewModel.unsavedPodcast)
        }
      }
      .padding(.horizontal)

      if !viewModel.displayAboutSection {
        EpisodeFilterView(
          entryFilter: $viewModel.episodeList.entryFilter,
          currentFilterMethod: $viewModel.currentFilterMethod
        )
        .padding(.horizontal)

        if viewModel.subscribable {
          List(viewModel.episodeList.filteredEntries, id: \.guid) { unsavedEpisode in
            NavigationLink(
              value: Navigation.Search.Destination.searchedPodcastEpisode(
                SearchedPodcastEpisode(
                  searchedText: viewModel.searchedText,
                  unsavedPodcastEpisode: UnsavedPodcastEpisode(
                    unsavedPodcast: viewModel.unsavedPodcast,
                    unsavedEpisode: unsavedEpisode
                  )
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
            .episodeQueueableContextMenu(viewModel: viewModel, episode: unsavedEpisode)
          }
          .animation(.default, value: viewModel.episodeList.filteredEntries)
        } else {
          VStack {
            Text("Loading episodes...")
              .foregroundColor(.secondary)
              .padding()
            Spacer()
          }
        }
      }
    }
    .queueableSelectableEpisodesToolbar(viewModel: viewModel, episodeList: $viewModel.episodeList)
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
