// Copyright Justin Bishop, 2026

import Foundation

// Classifies why an episode counts as a signal for recommendations.
// Explicit ratings take precedence over implicit finished-playback signals.
enum SignalKind: Sendable, Hashable {
  case rating(EpisodeRating)
  case finished
}

struct SignalEpisode: Sendable, Identifiable {
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
}
