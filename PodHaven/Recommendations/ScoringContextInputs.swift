// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// Snapshot of all DB state that feeds RecommendationEngine.ScoringContext.
// Emitted by `Observatory.scoringContextInputs()` on every relevant change so
// the engine rebuilds its cached context once per change instead of once per
// recommendation request.
//
// `freshnessCadences` is already resolved per-podcast: rows with an explicit
// non-nil cadence carry that value, and rows with nil get
// `FreshnessCadence.infer(from:)` applied to their episode pubDates inside
// the observation. Podcasts with no episodes and no manual choice are
// absent — the engine falls back to `FreshnessCadence.default` at scoring
// time. Resolving in the observation (vs. in `buildContext`) lets
// `removeDuplicates()` suppress emissions when episode pubDates shift but
// the inferred cadence doesn't, avoiding pointless engine rebuilds.
struct ScoringContextInputs: Sendable, Equatable {
  let signals: [SignalEpisode]
  let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
  let hasAnyEmbeddings: Bool
  let freshnessCadences: [Podcast.ID: FreshnessCadence]
}
