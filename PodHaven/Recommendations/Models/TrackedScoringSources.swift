// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// What the GRDB observation actually tracks: rated signals, their
// embeddings, the embedding-existence flag, and freshness cadences.
// Deliberately excludes `PartialSignal` so playback-path columns
// (`playbackCoverage`, `lastPlayedDate`) stay out of the tracked region —
// otherwise every 3-second `updatePlayback` write would wake the
// observation and re-run the closure. Partial-listen data is fetched
// instead by the engine's debounced rebuild via `latestScoringContextInputs`
// and by the `onDeck` session-boundary handler.
struct TrackedScoringSources: Sendable, Equatable {
  let ratedSignals: [SignalEpisode]
  let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
  let hasAnyEmbeddings: Bool
  let freshnessCadences: [Podcast.ID: FreshnessCadence]
}
