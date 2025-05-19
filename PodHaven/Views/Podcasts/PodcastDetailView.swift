// Copyright Justin Bishop, 2025

import GRDB
import SwiftUI

struct PodcastDetailView: View {
  @Environment(Alert.self) var alert

  @State private var viewModel: PodcastDetailViewModel

  init(viewModel: PodcastDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      HTMLText(viewModel.podcast.description)
        .lineLimit(3)
        .padding(.horizontal)

      Text("Last updated: \(Date.usShortDateFormat.string(from: viewModel.podcast.lastUpdate))")
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
          if viewModel.isRemarkable(error) {
            viewModel.log.report(error)
          } else {
            viewModel.log.info(error)
          }
          alert(ErrorKit.loggableMessage(for: error))
        }
      }
    }
    .navigationTitle(viewModel.podcast.title)
    .navigationDestination(for: Episode.self) { episode in
      EpisodeDetailView(
        viewModel: EpisodeDetailViewModel(
          podcastEpisode: PodcastEpisode(podcast: viewModel.podcast, episode: episode)
        )
      )
    }
    .queueableSelectableEpisodesToolbar(viewModel: viewModel, episodeList: $viewModel.episodeList)
    .task { await viewModel.execute() }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var podcast: Podcast?

  NavigationStack {
    if let podcast = podcast {
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
    }
  }
  .preview()
  .task {
    podcast = try? await PreviewHelpers.loadSeries().podcast
  }
}
#endif
