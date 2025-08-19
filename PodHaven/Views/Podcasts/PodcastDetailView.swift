// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import NukeUI
import SwiftUI

struct PodcastDetailView<ViewModel: PodcastDetailViewableModel>: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: ViewModel

  private static var log: Logger { Log.as(LogSubsystem.PodcastsView.detail) }

  init(viewModel: ViewModel) {
    Self.log.debug(
      """
      Showing PodcastDetailView
        viewModel: \(viewModel.podcast.toString)
      """
    )
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(spacing: 4) {
      Group {
        PodcastHeaderView(
          podcast: viewModel.podcast,
          subscribable: viewModel.subscribable,
          subscribed: viewModel.podcast.subscribed,
          subscribeAction: viewModel.subscribe,
          unsubscribeAction: viewModel.unsubscribe
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
          PodcastExpandedAboutView(podcast: viewModel.podcast)
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
          if !viewModel.episodeList.filteredEntries.isEmpty {
            List(viewModel.episodeList.filteredEntries) { episode in
              NavigationLink(
                value: viewModel.navigationDestination(for: episode),
                label: {
                  EpisodeListView(
                    viewModel: SelectableListItemModel(
                      isSelected: $viewModel.episodeList.isSelected[episode],
                      item: episode,
                      isSelecting: viewModel.episodeList.isSelecting
                    )
                  )
                }
              )
              .episodeQueueableSwipeActions(viewModel: viewModel, episode: episode)
              .episodeQueueableContextMenu(viewModel: viewModel, episode: episode)
            }
            .animation(.default, value: viewModel.episodeList.filteredEntries)
            .conditionalRefreshable(enabled: viewModel.refreshable, action: viewModel.refreshSeries)
          } else {
            VStack {
              Text("No episodes match the filters.")
                .foregroundColor(.secondary)
                .padding()
              Spacer()
            }
          }
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
    .task { await viewModel.execute() }
  }
}

#if DEBUG
#Preview("Changelog") {
  @Previewable @State var podcast: Podcast?

  NavigationStack {
    if let podcast {
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
    }
  }
  .preview()
  .task {
    await PreviewHelpers.dataFetcher
      .respond(
        to: URL(string: "https://changelog.com/podcast/feed")!,
        data: PreviewBundle.loadAsset(named: "changelog", in: .FeedRSS)
      )
    podcast = try? await PreviewHelpers.loadSeries(fileName: "changelog").podcast
  }
}

#Preview("Pod Save America") {
  @Previewable @State var podcast: Podcast?

  NavigationStack {
    if let podcast {
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
    }
  }
  .preview()
  .task {
    await PreviewHelpers.dataFetcher
      .respond(
        to: URL(string: "https://feeds.simplecast.com/dxZsm5kX")!,
        data: PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
      )
    podcast = try? await PreviewHelpers.loadSeries(fileName: "pod_save_america").podcast
  }
}
#endif
