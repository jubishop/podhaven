// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Logging
import SwiftUI

struct SelectablePodcastsGridView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: SelectablePodcastsGridViewModel

  private static let log = Log.as(LogSubsystem.PodcastsView.standard)

  init(viewModel: SelectablePodcastsGridViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    SearchBar(
      text: $viewModel.podcastList.entryFilter,
      placeholder: "Filter podcasts",
      searchIcon: .filter
    )
    .padding(.horizontal)

    ScrollView {
      ItemGrid(items: viewModel.podcastList.filteredEntries) {
        podcastWithLatestEpisodeDates in
        let podcast = podcastWithLatestEpisodeDates.podcast

        NavigationLink(
          value: Navigation.Destination.podcast(DisplayedPodcast(podcast)),
          label: {
            VStack {
              SquareImage(image: podcast.image)
                .selectable(
                  isSelected: $viewModel.podcastList.isSelected[podcast.id],
                  isSelecting: viewModel.isSelecting
                )
              Text(podcast.title)
                .font(.caption)
                .lineLimit(1)
            }
            .selectablePodcastsGridContextMenu(
              viewModel: viewModel,
              podcast: podcast
            )
          }
        )
        .buttonStyle(.plain)
      }
      .padding()
    }
    .navigationTitle(viewModel.title)
    .refreshable {
      do {
        try await viewModel.refreshPodcasts()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
    .selectablePodcastsGridToolbar(viewModel: viewModel)
    .task(viewModel.execute)
  }
}

// MARK: - Preview

#if DEBUG
#Preview("My Podcasts") {
  @Previewable @State var path: [String] = []

  NavigationStack(path: $path) {
    Button("Go to My Podcasts") {
      path = ["podcasts"]
    }
    .navigationDestination(for: String.self) { _ in
      SelectablePodcastsGridView(
        viewModel: SelectablePodcastsGridViewModel(
          title: "My Podcasts",
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

      // Create sample podcasts with episodes
      for i in 0..<24 {
        let podcast = try Create.unsavedPodcast(
          title: "Podcast \(i + 1)",
          image: allThumbnails.randomElement()!.value.url,
          description: "",
          subscriptionDate: i < 5 ? Date().addingTimeInterval(-86400 * Double(i)) : nil
        )

        // Create episodes for this podcast with varying dates
        var episodes: [UnsavedEpisode] = []
        for j in 0..<(3...8).randomElement()! {
          let episode = try Create.unsavedEpisode(
            title: "Episode \(j + 1) - \(podcast.title)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * Double(i * 7 + j)),
            duration: CMTime.seconds(Double.random(in: 1800...4500)),
            description: "Sample episode description",
            image: allThumbnails.randomElement()!.value.url,
            currentTime: j % 3 == 0 ? CMTime.seconds(Double.random(in: 60...300)) : nil,
            queueOrder: j % 5 == 0 ? j : nil,
            cachedFilename: j % 2 == 0 ? "cached_\(i)_\(j).mp3" : nil
          )
          episodes.append(episode)
        }

        _ = try await repo.insertSeries(podcast, unsavedEpisodes: episodes)
      }

      path = ["podcasts"]
    } catch {
      print("Preview error: \(error)")
    }
  }
}
#endif
