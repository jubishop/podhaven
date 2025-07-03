// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import SwiftUI

struct PodcastDetailView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: PodcastDetailViewModel

  private static let log = Log.as(LogSubsystem.PodcastsView.detail)

  init(viewModel: PodcastDetailViewModel) {
    Self.log.debug(
      """
      Showing PodcastDetailView
        viewModel: \(viewModel.podcast.toString)
      """
    )
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      HTMLText(viewModel.podcast.description)
        .lineLimit(3)
        .padding(.horizontal)

      Text("Last updated: \(viewModel.podcast.lastUpdate.usShortWithTime)")
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal)

      if !viewModel.podcast.subscribed {
        Button("Subscribe") {
          viewModel.subscribe()
        }
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

      List(viewModel.episodeList.filteredEntries) { episode in
        NavigationLink(
          value: episode,
          label: {
            EpisodeListView(
              viewModel: EpisodeListViewModel(
                isSelected: $viewModel.episodeList.isSelected[episode],
                item: episode,
                isSelecting: viewModel.episodeList.isSelecting
              )
            )
          }
        )
        .episodeQueueableSwipeActions(viewModel: viewModel, episode: episode)
      }
      .animation(.default, value: viewModel.episodeList.filteredEntries)
      .refreshable {
        do {
          try await viewModel.refreshSeries()
        } catch {
          if ErrorKit.baseError(for: error) is CancellationError { return }
          Self.log.error(error)
          alert(ErrorKit.message(for: error))
        }
      }
    }
    .navigationTitle(viewModel.podcast.title)
    .navigationDestination(for: Episode.self) { episode in
      navigation.episodeDetailView(for: episode, podcast: viewModel.podcast)
    }
    .queueableSelectableEpisodesToolbar(viewModel: viewModel, episodeList: $viewModel.episodeList)
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  @Previewable @State var podcast: Podcast?

  NavigationStack {
    if let podcast {
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
    }
  }
  .preview()
  .task {
    podcast = try? await PreviewHelpers.loadSeries().podcast
  }
}
#endif
