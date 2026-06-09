// Copyright Justin Bishop, 2026

import Foundation

// Cheap wake signal for the embedding drain. The full `episodesNeedingEmbeddings`
// scan is a three-table join over the entire library, far too expensive to re-run
// on every commit. New embedding work only appears when an episode or podcast's
// content changes (or a new row arrives) — both bump `contentUpdatedAt`. Observing
// just the two maxima keeps the tracked region off the playback-path columns, so
// the per-tick `updatePlayback` writes never wake it, and the heavy scan runs once
// per debounced burst in `EmbeddingProcessor` instead.
struct EmbeddingWorkSignal: Equatable, Sendable {
  let latestEpisodeContentUpdate: Date?
  let latestPodcastContentUpdate: Date?
}
