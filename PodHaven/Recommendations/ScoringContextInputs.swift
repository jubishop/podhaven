// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// Snapshot of all DB state that feeds RecommendationEngine.ScoringContext.
// Emitted by `Observatory.scoringContextInputs()` on every relevant change so
// the engine rebuilds its cached context once per change instead of once per
// recommendation request.
//
// Cadence is split into two raw inputs that the engine resolves at
// buildContext time into a single per-podcast cadence map:
//
// - `manualFreshnessCadences`: only podcasts whose row holds an explicit
//   non-nil cadence (the user has overridden auto).
// - `inferenceFreshnessPubDates`: the pubDates the engine needs to infer a
//   cadence for podcasts whose row is nil (auto). Only populated for
//   podcasts that aren't in `manualFreshnessCadences` and have at least one
//   episode; the engine resolves the rest to `FreshnessCadence.default`.
struct ScoringContextInputs: Sendable, Equatable {
  let signals: [SignalEpisode]
  let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
  let hasAnyEmbeddings: Bool
  let manualFreshnessCadences: [Podcast.ID: FreshnessCadence]
  let inferenceFreshnessPubDates: [Podcast.ID: [Date]]
}
