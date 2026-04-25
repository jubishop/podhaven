// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// Snapshot feeding RecommendationEngine's cached ScoringContext, emitted
// by `Observatory.scoringContextInputs()`. Cadences are pre-resolved so
// `removeDuplicates` can suppress emissions when episode pubDates shift
// without changing the inferred cadence.
struct ScoringContextInputs: Sendable, Equatable {
  let signals: [SignalEpisode]
  let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
  let hasAnyEmbeddings: Bool
  let freshnessCadences: [Podcast.ID: FreshnessCadence]
}
