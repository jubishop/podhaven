// Copyright Justin Bishop, 2026

import GRDB

// External-content title and description mirrors kept in sync with `episode`
// and `podcast`. Their rowids equal the source ids.

enum EpisodeFTS: TableRecord {
  static let databaseTableName = "episode_fts"
}

// Flattened timed-segment text kept in sync with `episode.transcript`. Its
// rowid equals the episode id.
enum EpisodeTranscriptFTS: TableRecord {
  static let databaseTableName = "episode_transcript_fts"
}

enum PodcastFTS: TableRecord {
  static let databaseTableName = "podcast_fts"
}
