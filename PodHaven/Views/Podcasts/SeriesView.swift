// Copyright Justin Bishop, 2024

import GRDB
import SwiftUI

struct SeriesView: View {
  @State private var viewModel: SeriesViewModel

  init(podcast: Podcast) {
    _viewModel = State(initialValue: SeriesViewModel(podcast: podcast))
  }

  var body: some View {
    VStack {
      if let description = viewModel.podcast.description {
        HTMLText(description).padding()
      }
      List(viewModel.episodes) { episode in
        EpisodeListView(episode: episode)
      }
      .refreshable {
        do {
          try await viewModel.refreshSeries()
        } catch {
          Alert.shared(
            "Failed to refresh series: \(viewModel.podcast.title)",
            report: "Error: \(error)"
          )
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
      await viewModel.observePodcast()
    }
  }
}

#Preview {
  struct SeriesViewPreview: View {
    @State var podcast: Podcast?

    init() {
      self.podcast = try? Repo.shared.db.read { db in
        try Podcast.all().shuffled().fetchOne(db)
      }
    }

    var body: some View {
      Group {
        if let podcast = self.podcast {
          SeriesView(podcast: podcast)
        } else {
          Text("No podcast in DB")
        }
      }
      .task {
        if self.podcast == nil {
          if let podcastSeries = try? await Helpers.loadSeries() {
            self.podcast = podcastSeries.podcast
          }
        }
      }
    }
  }

  return Preview { NavigationStack { SeriesViewPreview() } }
}
