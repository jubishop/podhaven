// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// Snapshot consumed in two places, both built by
// `RecommendationRepo.scoringContextInputs(_:partialSignals:)`:
//
// 1. The GRDB observation in
//    `Observatory.scoringContextInputsWithoutPartialSignals()` passes the
//    default empty closure, so `partialSignals` is always `[]`. That keeps
//    `playbackCoverage` and `lastPlayedDate` out of GRDB's tracked region
//    — otherwise every 3-second `updatePlayback` write would wake the
//    observation. Partial listens reach the engine via the rebuild path
//    below.
//
// 2. The engine's debounced rebuild calls
//    `RecommendationRepo.allScoringContextInputs()`, which passes a real
//    `PartialSignal` fetcher.
//
// `embeddingCount` is a count, not a bool, so a new embedding inserted for
// an unrated/partial-listen episode (which doesn't change
// `signalEmbeddings`) still produces a different value once any rated
// embedding has flipped a hypothetical bool to `true`. Without that,
// `removeDuplicates()` on the observation would swallow the emit.
struct ScoringContextInputs: Sendable, Equatable {
  let ratedSignals: [SignalEpisode]
  let partialSignals: [PartialSignal]
  let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
  let embeddingCount: Int
  let freshnessCadences: [Podcast.ID: FreshnessCadence]

  var hasAnyEmbeddings: Bool { embeddingCount > 0 }
}
