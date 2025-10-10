// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI

struct EpisodesListView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: EpisodesListViewModel

  init(viewModel: EpisodesListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    List(viewModel.episodeList.filteredEntries) { podcastEpisode in
      NavigationLink(
        value: Navigation.Destination.episode(DisplayedEpisode(podcastEpisode)),
        label: {
          EpisodeListView(
            episode: podcastEpisode,
            isSelecting: viewModel.isSelecting,
            isSelected: $viewModel.episodeList.isSelected[podcastEpisode.id]
          )
        }
      )
      .episodeListRow()
      .episodeSwipeActions(viewModel: viewModel, episode: podcastEpisode)
      .episodeContextMenu(viewModel: viewModel, episode: podcastEpisode) {
        AppIcon.showPodcast.labelButton {
          viewModel.showPodcast(podcastEpisode)
        }
      }
    }
    .searchable(
      text: $viewModel.episodeList.entryFilter,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Filter episodes"
    )
    .animation(.default, value: viewModel.episodeList.filteredEntries)
    .navigationTitle(viewModel.title)
    .toolbar {
      selectableEpisodesToolbarItems(
        viewModel: viewModel,
        episodeList: viewModel.episodeList
      )
    }
    .toolbarRole(.editor)
    .task(viewModel.execute)
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
          filter: AppDB.NoOp,
          order: Episode.Columns.pubDate.desc,
          limit: 20
        )
      )
    }
  }
  .preview()
  .task {
    do {
      let repo = Container.shared.repo()
      let allThumbnails = PreviewBundle.loadAllThumbnails()

      // Create sample podcasts and episodes
      for i in 0..<5 {
        let podcast = try Create.unsavedPodcast(
          title: "Podcast \(i + 1)",
          image: allThumbnails.randomElement()!.value.url,
          description: "Sample podcast description \(i + 1)",
          subscriptionDate: Date()
        )

        // Create multiple episodes for this podcast
        var episodes: [UnsavedEpisode] = []
        for j in 0..<4 {
          let episode = try Create.unsavedEpisode(
            title: "Episode \(j + 1) - \(podcast.title)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * Double(i * 4 + j)),
            duration: CMTime.seconds(Double.random(in: 1200...3600)),
            description: "Sample episode description",
            image: allThumbnails.randomElement()!.value.url,
            currentTime: j % 3 == 0 ? CMTime.seconds(300) : nil,
            queueOrder: j % 4 == 0 ? j : nil,
            cachedFilename: j % 2 == 0 ? "cached_\(i)_\(j).mp3" : nil
          )
          episodes.append(episode)
        }

        _ = try await repo.insertSeries(podcast, unsavedEpisodes: episodes)
      }

      path = ["episodes"]
    } catch {
      print("Preview error: \(error)")
    }
  }
}
#endif
