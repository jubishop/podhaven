// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// MARK: - CachedPodcastEntry

@Observable @MainActor
final class CachedPodcastEntry: Identifiable {
  enum Status: Equatable {
    case pending
    case fetching
    case scored
    // Set only by `removePick` after the last pick is dismissed. Terminal —
    // skipped by the scoring-context recovery loop so user-dismissed entries
    // don't resurrect on the next close → open cycle.
    case exhausted
    case failed
    case cancelled
  }

  let feedURL: FeedURL
  let podcastID: Podcast.ID?
  let iTunesID: ITunesPodcastID?
  var status: Status = .pending
  var scoredEpisodes = IdentifiedArrayOf<ScoredEpisode>()
  @ObservationIgnored var fetchToken: DownloadTask?

  var id: FeedURL { feedURL }

  init(feedURL: FeedURL, podcastID: Podcast.ID?, iTunesID: ITunesPodcastID?) {
    self.feedURL = feedURL
    self.podcastID = podcastID
    self.iTunesID = iTunesID
  }

  func cancel() async {
    let token = fetchToken
    fetchToken = nil
    status = .cancelled
    await token?.cancel()
  }
}
