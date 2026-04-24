// Copyright Justin Bishop, 2026

import Foundation

// Classifies why an episode counts as a signal for recommendations.
// Explicit ratings take precedence over implicit finished-playback signals.
enum SignalKind: Sendable, Hashable {
  case rating(EpisodeRating)
  case finished
}

struct SignalEpisode: Sendable, Identifiable, Equatable {
  let episode: Episode
  let kind: SignalKind

  var id: Episode.ID { episode.id }

  init(episode: Episode, kind: SignalKind) {
    self.episode = episode
    self.kind = kind
  }

  init(from episode: Episode) {
    self.episode = episode
    if let rating = episode.rating {
      self.kind = .rating(rating)
    } else {
      self.kind = .finished
    }
  }

  // Episode itself isn't Equatable (UnsavedEpisode synthesizes wouldn't
  // compose), so compare only the columns the recommendation engine reads:
  // identity, podcast membership, signal kind, and the dates that drive
  // temporal decay. Other Episode columns (currentTime, queueOrder, etc.)
  // intentionally don't bust observation equality — they shouldn't trigger
  // a centroid rebuild.
  static func == (lhs: SignalEpisode, rhs: SignalEpisode) -> Bool {
    lhs.episode.id == rhs.episode.id
      && lhs.episode.podcastID == rhs.episode.podcastID
      && lhs.kind == rhs.kind
      && lhs.episode.ratingDate == rhs.episode.ratingDate
      && lhs.episode.finishDate == rhs.episode.finishDate
  }
}
