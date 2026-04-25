// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// Snapshot of all DB state that feeds RecommendationEngine.ScoringContext.
// Emitted by `Observatory.scoringContextInputs()` on every relevant change so
// the engine rebuilds its cached context once per change instead of once per
// recommendation request. `freshnessCadences` only contains entries for
// podcasts that have been moved off the default cadence (.weekly); the
// engine resolves missing entries to the default at scoring time.
struct ScoringContextInputs: Sendable, Equatable {
  let signals: [SignalEpisode]
  let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
  let hasAnyEmbeddings: Bool
  let freshnessCadences: [Podcast.ID: FreshnessCadence]
}
