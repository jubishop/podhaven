// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import IdentifiedCollections
import Logging
import SwiftUI

struct PodcastsListView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: PodcastsListViewModel

  private static let log = Log.as(LogSubsystem.PodcastsView.list)

  init(viewModel: PodcastsListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    podcastsView
      .searchable(
        text: $viewModel.podcastList.entryFilter,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Filter podcasts"
      )
      .searchPresentationToolbarBehavior(.avoidHidingContent)
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
      .toolbar { toolbar }
      .toolbarRole(.editor)
      .task(viewModel.execute)
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    sortableDisplayingPodcastsToolbarItems(viewModel: viewModel)
    selectablePodcastsToolbarItems(viewModel: viewModel)
  }

  // MARK: - Grid & List

  @ViewBuilder
  private var podcastsView: some View {
    if viewModel.isLoading {
      loadingView
    } else if viewModel.podcastList.filteredEntries.isEmpty {
      noPodcastsMessage
    } else {
      switch viewModel.displayMode {
      case .grid:
        gridView
      case .list:
        listView
          .animation(.default, value: viewModel.podcastList.filteredEntries)
      }
    }
  }

  private var gridView: some View {
    ScrollView {
      ItemGrid(items: viewModel.podcastList.filteredEntries) { podcastWithEpisodeMetadata in
        NavigationLink(
          value: Navigation.Destination.podcast(
            DisplayedPodcast(podcastWithEpisodeMetadata.podcast)
          ),
          label: {
            PodcastGridView(
              podcast: podcastWithEpisodeMetadata.podcast,
              isSelecting: viewModel.podcastList.isSelecting,
              isSelected: $viewModel.podcastList.isSelected[podcastWithEpisodeMetadata.id]
            )
            .podcastContextMenu(
              viewModel: viewModel,
              podcast: podcastWithEpisodeMetadata.podcast
            )
          }
        )
        .buttonStyle(.plain)
      }
      .padding()
    }
  }

  private var listView: some View {
    List {
      ForEach(viewModel.podcastList.filteredEntries) { podcastWithEpisodeMetadata in
        NavigationLink(
          value: Navigation.Destination.podcast(
            DisplayedPodcast(podcastWithEpisodeMetadata.podcast)
          ),
          label: {
            PodcastListView(
              podcastWithMetadata: podcastWithEpisodeMetadata,
              isSelecting: viewModel.podcastList.isSelecting,
              isSelected: $viewModel.podcastList.isSelected[podcastWithEpisodeMetadata.id]
            )
            .listRowSeparator()
            .podcastContextMenu(
              viewModel: viewModel,
              podcast: podcastWithEpisodeMetadata.podcast
            )
          }
        )
        .listRow()
      }
    }
  }

  // MARK: - Reusable Views

  private var loadingView: some View {
    VStack {
      ProgressView("Loading podcasts...")
        .foregroundColor(.secondary)
        .padding()
      Spacer()
    }
  }

  private var noPodcastsMessage: some View {
    VStack {
      Text("No podcasts match the filters.")
        .foregroundColor(.secondary)
        .padding()
      Spacer()
    }
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
      PodcastsListView(
        viewModel: PodcastsListViewModel(
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
      var queueOrder = 0
      for i in 0..<24 {
        let podcast = try Create.unsavedPodcast(
          title: "Podcast \(i + 1)",
          image: allThumbnails.randomElement()!.value.url,
          subscriptionDate: i < 5 ? Date().addingTimeInterval(-86400 * Double(i)) : nil
        )

        // Create episodes for this podcast with varying dates
        var episodes = IdentifiedArrayOf<UnsavedEpisode>()
        for j in 0..<(3...8).randomElement()! {
          let episode = try Create.unsavedEpisode(
            pubDate: Date().addingTimeInterval(-3600 * 24 * Double(i * 7 + j)),
            duration: CMTime.seconds(Double.random(in: 1800...4500)),
            currentTime: j % 2 == 0 ? CMTime.seconds(Double.random(in: 60...300)) : nil,
            queueOrder: j % 2 == 0
              ? {
                let current = queueOrder
                queueOrder += 1
                return current
              }() : nil,
            cachedFilename: j % 2 == 0 ? "cached_\(i)_\(j).mp3" : nil
          )
          episodes.append(episode)
        }

        _ = try await repo.insertSeries(
          UnsavedPodcastSeries(unsavedPodcast: podcast, unsavedEpisodes: episodes)
        )
      }

      path = ["podcasts"]
    } catch {
      print("Preview error: \(error)")
    }
  }
}
#endif
