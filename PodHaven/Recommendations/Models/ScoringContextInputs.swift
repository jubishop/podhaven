// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

struct ScoringContextInputs: Sendable, Equatable {
  let ratedSignals: [SignalEpisode]
  let partialSignals: [PartialSignal]
  let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
  let hasAnyEmbeddings: Bool
  let freshnessCadences: [Podcast.ID: FreshnessCadence]
}
