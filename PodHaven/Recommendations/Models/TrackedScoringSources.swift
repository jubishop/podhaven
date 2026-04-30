// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// What the GRDB observation actually tracks: rated signals, their
// embeddings, the total embedding-row count, and freshness cadences.
// Deliberately excludes `PartialSignal` so playback-path columns
// (`playbackCoverage`, `lastPlayedDate`) stay out of the tracked region —
// otherwise every 3-second `updatePlayback` write would wake the
// observation and re-run the closure. Partial-listen data is fetched
// instead by the engine's debounced rebuild via `latestScoringContextInputs`
// and by the `onDeck` session-boundary handler.
//
// `embeddingCount` is a count rather than a bool so a new embedding for an
// unrated/partial-listen episode still changes this value once any rated
// embedding has set the bool to `true`. Without that, `removeDuplicates()`
// on the observation would swallow the emit and the engine would never
// rebuild with the new vector.
struct TrackedScoringSources: Sendable, Equatable {
  let ratedSignals: [SignalEpisode]
  let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
  let embeddingCount: Int
  let freshnessCadences: [Podcast.ID: FreshnessCadence]
}
