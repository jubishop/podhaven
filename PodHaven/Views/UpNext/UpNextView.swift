// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI

struct UpNextView: View {
  @DynamicInjected(\.alert) private var alert
  @InjectedObservable(\.navigation) private var navigation

  @State private var viewModel: UpNextViewModel

  init(viewModel: UpNextViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.upNext) {
      List {
        ForEach(viewModel.episodeList.filteredEntries) { podcastEpisode in
          upNextListView(podcastEpisode)
            .episodeListRow()
            .episodeSwipeActions(viewModel: viewModel, episode: podcastEpisode)
            .episodeContextMenu(viewModel: viewModel, episode: podcastEpisode)
        }
        .onMove(perform: viewModel.moveEpisode)
      }
      .refreshable { viewModel.refreshQueue() }
      .navigationTitle("Up Next")
      .environment(\.editMode, $viewModel.editMode)
      .animation(.default, value: viewModel.episodeList.filteredEntries)
      .toolbar {
        if !viewModel.isSelecting {
          ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 4) {
              AppIcon.duration.image
                .font(.system(size: 12))
              Text(viewModel.totalQueueDuration.shortDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            }
          }
          .sharedBackgroundVisibility(.hidden)

          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              ForEach(viewModel.allSortMethods, id: \.self) { method in
                Button(
                  action: { viewModel.sort(by: method) },
                  label: { Label(method.rawValue, systemImage: method.systemImageName) }
                )
                .tint(method.menuIconColor)
              }
            } label: {
              AppIcon.sort.image
            }
          }
        }

        selectableEpisodesToolbarItems(
          viewModel: viewModel,
          episodeList: viewModel.episodeList
        )
      }
    }
    .task(viewModel.execute)
  }

  @ViewBuilder
  func upNextListView(_ podcastEpisode: PodcastEpisode) -> some View {
    let episodeListView = EpisodeListView(
      episode: podcastEpisode,
      isSelecting: viewModel.isSelecting,
      isSelected: $viewModel.episodeList.isSelected[podcastEpisode.id]
    )

    if viewModel.isSelecting {
      episodeListView
    } else {
      NavigationLink(
        value: Navigation.Destination.upNextEpisode(podcastEpisode),
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
        var episodes: [UnsavedEpisode] = []
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

        _ = try await repo.insertSeries(try Create.unsavedPodcast(), unsavedEpisodes: episodes)
      } catch {
        print("Preview error: \(error)")
      }
    }
}
#endif
