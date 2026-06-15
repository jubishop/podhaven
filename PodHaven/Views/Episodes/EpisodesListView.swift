// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import IdentifiedCollections
import Logging
import SwiftUI

struct EpisodesListView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.sheet) private var sheet

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
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          LucideNavigationTitle(icon: viewModel.icon, title: viewModel.title)
        }
        ToolbarItem(placement: .topBarLeading) {
          AppIcon.settings.labelButton("Edit Smart List") {
            sheet(id: "smart-list-editor-\(viewModel.smartListID)") {
              SmartListEditorView(
                viewModel: SmartListEditorViewModel(
                  mode: .edit(viewModel.smartListID),
                  title: viewModel.title,
                  filter: viewModel.smartListFilter,
                  alwaysShowPodcastImage: viewModel.alwaysShowPodcastImage,
                  icon: viewModel.icon
                )
              )
            }
          }
        }
        sortableEpisodesToolbarItems(viewModel: viewModel)
        selectableEpisodesToolbarItems(viewModel: viewModel)
      }
      .toolbarRole(.editor)
      .task(viewModel.observeSmartList)
      .task(id: viewModel.displayObservationKey, viewModel.startDisplayObservation)
      .onDisappear { viewModel.disappear() }
  }

  @ViewBuilder
  private var episodesView: some View {
    switch viewModel.loadingState {
    case .loading:
      loadingView(message: "Loading episodes…")
    case .loaded:
      if viewModel.episodeList.filteredEntries.isEmpty {
        emptyEpisodesMessage
      } else {
        listView
      }
    case .failed:
      failureMessage
    }
  }

  private var listView: some View {
    List(viewModel.episodeList.filteredEntries) { podcastEpisode in
      NavigationLink(
        value: Navigation.Destination.listedEpisode(ListedEpisode(podcastEpisode)),
        label: {
          EpisodeListView(
            episode: podcastEpisode,
            alwaysShowPodcastImage: viewModel.alwaysShowPodcastImage,
            isSelecting: viewModel.episodeList.isSelecting,
            isSelected: $viewModel.episodeList.isSelected[podcastEpisode.id]
          )
          .listRowSeparator()
        }
      )
      .listRow()
      .episodeSwipeActions(viewModel: viewModel, episode: podcastEpisode)
      .episodeContextMenu(viewModel: viewModel, episode: podcastEpisode)
    }
  }

  private func loadingView(message: String) -> some View {
    VStack {
      ProgressView(message)
        .foregroundColor(.secondary)
        .padding()
      Spacer()
    }
  }

  private var emptyEpisodesMessage: some View {
    VStack {
      Text(emptyEpisodesMessageText)
        .foregroundColor(.secondary)
        .padding()
      Spacer()
    }
  }

  private var emptyEpisodesMessageText: String {
    switch viewModel.currentSortMethod {
    case .recommendationScore:
      return "No episodes have recommendation scores for these filters."
    default:
      return "No episodes match the filters."
    }
  }

  private var failureMessage: some View {
    VStack {
      Text("Couldn't load episodes.")
        .foregroundColor(.secondary)
        .padding()
      Spacer()
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview("Recent Episodes") {
  @Previewable @State var smartList: SmartList?

  NavigationStack {
    if let smartList {
      EpisodesListView(viewModel: EpisodesListViewModel(smartList: smartList))
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
        guard let thumbnail = allThumbnails.randomElement() else { return }
        let duration = CMTime.seconds(Double.random(in: 1200...3600))
        let episode = try Create.unsavedEpisode(
          title: "Episode \(j + 1) - \(String.random())",
          pubDate: j.daysAgo,
          duration: duration,
          image: thumbnail.value.url,
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

      smartList = try await Container.shared.smartListRepo().fetchAll().first
    } catch {
      print("Preview error: \(error)")
    }
  }
}

#Preview("Rating States") {
  @Previewable @State var smartList: SmartList?

  NavigationStack {
    if let smartList {
      EpisodesListView(viewModel: EpisodesListViewModel(smartList: smartList))
    }
  }
  .preview()
  .task {
    do {
      let repo = Container.shared.repo()
      let allThumbnails = PreviewBundle.loadAllThumbnails()
      let now = Date()

      let cases: [(title: String, rating: EpisodeRating?)] = [
        (title: "Unrated — swipe shows neutral icon", rating: nil),
        (title: "Loved — swipe shows pink heart", rating: .loved),
        (title: "Liked — swipe shows blue thumbs-up", rating: .liked),
        (title: "Disliked — swipe shows gray thumbs-down", rating: .disliked),
        (title: "Not Interested — swipe shows brown stop-hand", rating: .notInterested),
      ]

      var episodes = IdentifiedArrayOf<UnsavedEpisode>()
      for (index, entry) in cases.enumerated() {
        guard let thumbnail = allThumbnails.randomElement() else { return }
        let episode = try Create.unsavedEpisode(
          title: entry.title,
          pubDate: index.daysAgo,
          duration: CMTime.seconds(2400),
          image: thumbnail.value.url,
          rating: entry.rating,
          ratingDate: entry.rating == nil ? nil : now
        )
        episodes.append(episode)
      }

      _ = try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "Rating States"),
          unsavedEpisodes: episodes
        )
      )

      smartList = try await Container.shared.smartListRepo().fetchAll().first
    } catch {
      print("Preview error: \(error)")
    }
  }
}
#endif
