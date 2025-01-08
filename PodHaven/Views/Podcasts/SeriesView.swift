// Copyright Justin Bishop, 2025

import GRDB
import SwiftUI

struct SeriesView: View {
  @Environment(Alert.self) var alert
  @State private var viewModel: SeriesViewModel

  init(podcast: Podcast) {
    _viewModel = State(initialValue: SeriesViewModel(podcast: podcast))
  }

  var body: some View {
    VStack {
      HTMLText(viewModel.podcast.description).lineLimit(3).padding()
      Text("Last updated: \(viewModel.podcast.formattedLastUpdate)")
      List(viewModel.episodes) { episode in
        EpisodeListView(
          podcastEpisode: PodcastEpisode(
            podcast: viewModel.podcast,
            episode: episode
          )
        )
      }
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
        podcastEpisode: PodcastEpisode(
          podcast: viewModel.podcast,
          episode: episode
        )
      )
    }
    .task {
      do {
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
    Group {
      if let podcast = podcast {
        SeriesView(podcast: podcast)
      } else {
        Text("No podcast in DB")
      }
    }
  }
  .preview()
  .task {
    podcast = try? await PreviewHelpers.loadSeries().podcast
  }
}
