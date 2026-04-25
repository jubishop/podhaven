// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// Snapshot of all DB state that feeds RecommendationEngine.ScoringContext.
// Emitted by `Observatory.scoringContextInputs()` on every relevant change so
// the engine rebuilds its cached context once per change instead of once per
// recommendation request.
struct ScoringContextInputs: Sendable, Equatable {
  let signals: [SignalEpisode]
  let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
  let hasAnyEmbeddings: Bool
}
