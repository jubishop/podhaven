// Copyright Justin Bishop, 2025

import GRDB
import SwiftUI

struct SeriesView: View {
  @Environment(Alert.self) var alert

  @State private var viewModel: SeriesViewModel

  init(viewModel: SeriesViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      HTMLText(viewModel.podcast.description)
        .lineLimit(3)
        .padding(.horizontal)

      Text("Last updated: \(viewModel.podcast.formattedLastUpdate)")
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal)

      if !viewModel.podcast.subscribed {
        Button(
          action: {
            Task { try await viewModel.subscribe() }
          },
          label: {
            Text("Subscribe")
          }
        )
      }
      List(viewModel.filteredEpisodes) { episode in
        NavigationLink(
          value: episode,
          label: {
            EpisodeListView(
              viewModel: EpisodeListViewModel(
                isSelected: $viewModel.isSelected[episode],
                episode: episode,
                isSelecting: viewModel.isSelecting
              )
            )
          }
        )
      }
      .searchable(text: $viewModel.episodeFilter)
      .refreshable {
        do {
          try await viewModel.refreshSeries()
        } catch {
          alert.andReport("Failed to refresh series: \(viewModel.podcast.toString)")
        }
      }
    }
    .navigationTitle(viewModel.podcast.title)
    .navigationDestination(for: Episode.self) { episode in
      EpisodeView(
        viewModel: EpisodeViewModel(
          podcastEpisode: PodcastEpisode(
            podcast: viewModel.podcast,
            episode: episode
          )
        )
      )
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        if viewModel.isSelecting {
          Button(
            action: {
              viewModel.isSelecting = false
            },
            label: {
              Text("Done")
            }
          )
          if viewModel.anySelected {
          } else {
          }
        } else {
          Button(
            action: {
              viewModel.isSelecting = true
            },
            label: {
              Text("Select")
            }
          )
        }
      }
    }
    .toolbarRole(.navigationStack)
    .task {
      do {
        try await viewModel.refreshIfStale()
        try await viewModel.observePodcast()
      } catch {
        alert.andReport(error)
      }
    }
  }
}

#Preview {
  @Previewable @State var podcast: Podcast?

  NavigationStack {
    if let podcast = podcast {
      SeriesView(viewModel: SeriesViewModel(podcast: podcast))
    }
  }
  .preview()
  .task {
    podcast = try? await PreviewHelpers.loadSeries().podcast
  }
}
