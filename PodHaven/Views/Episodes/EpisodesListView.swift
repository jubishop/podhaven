// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import IdentifiedCollections
import Logging
import SwiftUI

struct EpisodesListView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  private static let log = Log.as(LogSubsystem.EpisodesView.list)

  @State private var viewModel: EpisodesListViewModel

  init(viewModel: EpisodesListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    episodesView
      .searchable(
        text: $viewModel.filterDebouncer.currentValue,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Filter episodes"
      )
      .searchPresentationToolbarBehavior(.avoidHidingContent)
      .animation(.default, value: viewModel.episodeList.filteredEntries)
      .navigationTitle(viewModel.title)
      .toolbar {
        sortableEpisodesToolbarItems(viewModel: viewModel)
        selectableEpisodesToolbarItems(viewModel: viewModel)
      }
      .toolbarRole(.editor)
      .task(id: viewModel.observationKey, viewModel.startObservation)
  }

  @ViewBuilder
  private var episodesView: some View {
    if viewModel.isLoading {
      loadingView
    } else if viewModel.episodeList.filteredEntries.isEmpty {
      noEpisodesMessage
    } else {
      listView
    }
  }

  private var listView: some View {
    List(viewModel.episodeList.filteredEntries) { podcastEpisode in
      NavigationLink(
        value: Navigation.Destination.episode(DisplayedEpisode(podcastEpisode)),
        label: {
          EpisodeListView(
            episode: podcastEpisode,
            isSelecting: viewModel.episodeList.isSelecting,
            isSelected: $viewModel.episodeList.isSelected[podcastEpisode.id]
          )
          .listRowSeparator()
        }
      )
      .listRow()
      .episodeSwipeActions(viewModel: viewModel, episode: podcastEpisode)
      .episodeContextMenu(viewModel: viewModel, episode: podcastEpisode) {
        AppIcon.showPodcast.labelButton {
          viewModel.showPodcast(podcastEpisode)
        }
      }
    }
  }

  private var loadingView: some View {
    VStack {
      ProgressView("Loading episodes...")
        .foregroundColor(.secondary)
        .padding()
      Spacer()
    }
  }

  private var noEpisodesMessage: some View {
    VStack {
      Text("No episodes match the filters.")
        .foregroundColor(.secondary)
        .padding()
      Spacer()
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview("Recent Episodes") {
  @Previewable @State var path: [String] = []

  NavigationStack(path: $path) {
    Button("Go to Recent Episodes") {
      path = ["episodes"]
    }
    .navigationDestination(for: String.self) { _ in
      EpisodesListView(
        viewModel: EpisodesListViewModel(
          title: "Recent Episodes",
          filter: AppDB.NoOp
        )
      )
    }
  }
  .preview()
  .task {
    do {
      let repo = Container.shared.repo()
      let allThumbnails = PreviewBundle.loadAllThumbnails()

      // Create multiple episodes for this podcast
      var queueOrder = 0
      var episodes = IdentifiedArrayOf<UnsavedEpisode>()
      for j in 0..<24 {
        let duration = CMTime.seconds(Double.random(in: 1200...3600))
        let episode = try Create.unsavedEpisode(
          title: "Episode \(j + 1) - \(String.random())",
          pubDate: j.daysAgo,
          duration: duration,
          image: allThumbnails.randomElement()!.value.url,
          currentTime: j % 2 == 0 ? CMTime.seconds(Double.random(in: 0..<duration.seconds)) : nil,
          queueOrder: j % 2 == 0
            ? {
              let current = queueOrder
              queueOrder += 1
              return current
            }() : nil,
          cachedFilename: j % 2 == 0 ? "cached_\(j).mp3" : nil
        )
        episodes.append(episode)
      }

      _ = try await repo.insertSeries(
        UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(), unsavedEpisodes: episodes)
      )

      path = ["episodes"]
    } catch {
      print("Preview error: \(error)")
    }
  }
}
#endif
