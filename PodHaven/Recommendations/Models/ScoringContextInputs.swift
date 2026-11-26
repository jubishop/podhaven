// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections
import Tagged

// Built by `RecommendationRepo.scoringContextInputs(_:embeddingRevision:partialSignals:)`
// and consumed in two places: the GRDB observation passes an empty fetcher (so
// `playbackCoverage`/`lastPlayedDate` stay out of the tracked region —
// otherwise every 3-second `updatePlayback` would wake it), and the
// engine's debounced rebuild passes a real `PartialSignal` fetcher.
//
// `signalEmbeddings` and `embeddingCount` cover only the requested embedding
// revision. `embeddingCount` is a count rather than a bool so a new or
// re-embedded row on an unrated/partial-listen episode still produces a
// different value (a bool would stay `true` forever and `removeDuplicates()`
// on the observation would swallow the emit).
struct ScoringContextInputs: Sendable, Equatable {
  let ratedSignals: [SignalEpisode]
  let partialSignals: [PartialSignal]
  let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
  let embeddingCount: Int
  let freshnessCadences: [Podcast.ID: FreshnessCadence]

  var hasAnyEmbeddings: Bool { embeddingCount > 0 }
}
