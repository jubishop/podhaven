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
      List(Array(viewModel.episodes)) { episode in
        EpisodeListView(episode: episode)
      }
      .refreshable {
        let feedTask = await FeedManager.shared.addURL(
          viewModel.podcast.feedURL
        )
        let feedResult = await feedTask.feedParsed()
        switch feedResult {
        case .failure(let error):
          Alert.shared(error.errorDescription)
        case .success(let feedData):
          // TODO: Save new data
          print("Got feeddata: \(feedData)")
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
      await viewModel.observePodcasts()
    }
  }
}

#Preview {
  struct SeriesViewPreview: View {
    let podcast: Podcast
    init() {
      self.podcast = try! PodcastRepository.shared.db.read { db in
        try! Podcast.fetchOne(db)!
      }
    }

    var body: some View {
      SeriesView(podcast: podcast)
    }
  }

  return Preview { NavigationStack { SeriesViewPreview() } }
}
