// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// Snapshot consumed in two places, with the same shape but different
// origins:
//
// 1. Emitted by the GRDB observation in `Observatory.scoringContextInputs()`.
//    The observation closure does NOT fetch `PartialSignal`, so it always
//    sets `partialSignals: []`. That keeps `playbackCoverage` and
//    `lastPlayedDate` out of GRDB's tracked region — otherwise every
//    3-second `updatePlayback` write would wake the observation. Partial
//    listens reach the engine via the rebuild path below.
//
// 2. Returned by `Repo.latestScoringContextInputs()`, which the engine
//    calls on every debounced rebuild. This path runs `partialSignals` for
//    real.
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
