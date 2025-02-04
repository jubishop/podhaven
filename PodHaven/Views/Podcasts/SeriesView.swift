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
      HTMLText(viewModel.podcast.description).lineLimit(3).padding()

      Text("Last updated: \(viewModel.podcast.formattedLastUpdate)")

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
      List(viewModel.episodes) { episode in
        NavigationLink(
          value: episode,
          label: {
            EpisodeListView(
              podcastEpisode: PodcastEpisode(
                podcast: viewModel.podcast,
                episode: episode
              )
            )
          }
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
        viewModel: EpisodeViewModel(
          podcastEpisode: PodcastEpisode(
            podcast: viewModel.podcast,
            episode: episode
          )
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
        SeriesView(viewModel: SeriesViewModel(podcast: podcast))
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
