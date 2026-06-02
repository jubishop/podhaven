// Copyright Justin Bishop, 2026

import GRDB

// External-content FTS5 mirrors of `episode` and `podcast`, kept in sync by
// triggers created in the v48 migration. Their `rowid` equals the source row's
// `id`, so a MATCH subquery resolves straight back to episode/podcast ids.

enum EpisodeFTS: TableRecord {
  static let databaseTableName = "episode_fts"
}

enum PodcastFTS: TableRecord {
  static let databaseTableName = "podcast_fts"
}
