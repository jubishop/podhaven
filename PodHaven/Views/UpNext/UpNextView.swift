// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import IdentifiedCollections
import SwiftUI

struct UpNextView: View {
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.userSettings) private var userSettings

  @State private var viewModel: UpNextViewModel

  init(viewModel: UpNextViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    NavStack(manager: navigation.upNext) {
      List {
        ForEach(viewModel.episodeList.filteredEntries) { podcastEpisode in
          upNextListView(podcastEpisode)
            .listRow()
            .episodeSwipeActions(viewModel: viewModel, episode: podcastEpisode)
            .episodeContextMenu(viewModel: viewModel, episode: podcastEpisode)
        }
        .onMove(perform: viewModel.moveEpisode)
      }
      .safeAreaInset(edge: .top, spacing: 12) {
        if userSettings.showNowPlayingInUpNext, let onDeck = sharedState.onDeck {
          EpisodeListView(
            episode: onDeck,
            alwaysShowPodcastImage: userSettings.alwaysShowPodcastImageInUpNext
          )
          .padding()
          .glassEffect(in: RoundedRectangle(cornerRadius: 12))
          .padding(.horizontal)
          .contentShape(Rectangle())
          .onTapGesture { PlayBar.showOnDeckEpisodeDetail() }
        }
      }
      .refreshable { viewModel.refreshQueue() }
      .navigationTitle("Up Next")
      .environment(\.editMode, $viewModel.editMode)
      .animation(.default, value: viewModel.episodeList.filteredEntries)
      .toolbar { toolbar }
      .toolbarRole(.editor)
    }
    .task(viewModel.execute)
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      HStack(spacing: 4) {
        AppIcon.duration.image
          .font(.system(size: 12))
        Text(viewModel.totalQueueTime.shortDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize()
      }
    }
    .sharedBackgroundVisibility(.hidden)

    ToolbarItem(placement: .primaryAction) {
      Menu(
        content: {
          ForEach(viewModel.allSortMethods, id: \.self) { sortMethod in
            sortMethod.appIcon.labelButton {
              viewModel.sort(by: sortMethod)
            }
          }
        },
        label: { AppIcon.sort.image }
      )
    }

    selectableEpisodesToolbarItems(viewModel: viewModel)
  }

  // MARK: - Episode List

  @ViewBuilder
  func upNextListView(_ podcastEpisode: PodcastEpisode) -> some View {
    let episodeListView = EpisodeListView(
      episode: podcastEpisode,
      alwaysShowPodcastImage: userSettings.alwaysShowPodcastImageInUpNext,
      isSelecting: viewModel.episodeList.isSelecting,
      isSelected: $viewModel.episodeList.isSelected[podcastEpisode.id]
    )
    .listRowSeparator()

    if viewModel.episodeList.isSelecting {
      episodeListView
    } else {
      NavigationLink(
        value: Navigation.Destination.episode(DisplayedEpisode(podcastEpisode)),
        label: { episodeListView }
      )
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview("Up Next") {
  UpNextView(viewModel: UpNextViewModel())
    .preview()
    .task {
      do {
        let repo = Container.shared.repo()
        let allThumbnails = PreviewBundle.loadAllThumbnails()

        // Create multiple episodes for this podcast - all queued
        var queueOrder = 0
        var episodes = IdentifiedArrayOf<UnsavedEpisode>()
        for j in 0..<24 {
          let duration = CMTime.seconds(Double.random(in: 1200...3600))
          let episode = try Create.unsavedEpisode(
            title: "Episode \(j + 1) - \(String.random())",
            pubDate: j.daysAgo,
            duration: duration,
            image: allThumbnails.randomElement()!.value.url,
            currentTime: CMTime.seconds(Double.random(in: 0..<duration.seconds)),
            queueOrder: queueOrder,
            cachedFilename: j % 3 == 0 ? "cached_\(j).mp3" : nil
          )
          episodes.append(episode)
          queueOrder += 1
        }

        _ = try await repo.insertSeries(
          UnsavedPodcastSeries(
            unsavedPodcast: try Create.unsavedPodcast(),
            unsavedEpisodes: episodes
          )
        )
      } catch {
        print("Preview error: \(error)")
      }
    }
}
#endif
