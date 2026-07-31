// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV77(_ db: Database) throws {
    try db.create(virtualTable: "episode_transcript_fts", using: FTS5()) { t in
      t.column("transcript")
    }

    try db.execute(
      sql: """
        INSERT INTO episode_transcript_fts(rowid, transcript)
        SELECT episode.id, COALESCE((
          SELECT group_concat(text, ' ')
          FROM (
            SELECT
              CASE WHEN segment.type = 'object'
                THEN json_extract(segment.value, '$.text')
              END AS text
            FROM json_each(
              CASE WHEN json_valid(episode.transcript) THEN episode.transcript END,
              '$.segments'
            ) AS segment
            ORDER BY CAST(segment.key AS INTEGER)
          )
        ), '')
        FROM episode
        WHERE episode.transcript IS NOT NULL
        """
    )

    try db.execute(
      sql: """
        CREATE TRIGGER episode_transcript_fts_insert
        AFTER INSERT ON episode
        BEGIN
          INSERT INTO episode_transcript_fts(rowid, transcript)
          SELECT NEW.id, COALESCE((
            SELECT group_concat(text, ' ')
            FROM (
              SELECT
                CASE WHEN segment.type = 'object'
                  THEN json_extract(segment.value, '$.text')
                END AS text
              FROM json_each(
                CASE WHEN json_valid(NEW.transcript) THEN NEW.transcript END,
                '$.segments'
              ) AS segment
              ORDER BY CAST(segment.key AS INTEGER)
            )
          ), '')
          WHERE NEW.transcript IS NOT NULL;
        END
        """
    )

    try db.execute(
      sql: """
        CREATE TRIGGER episode_transcript_fts_update
        AFTER UPDATE OF transcript ON episode
        WHEN OLD.transcript IS NOT NEW.transcript
        BEGIN
          DELETE FROM episode_transcript_fts WHERE rowid = OLD.id;
          INSERT INTO episode_transcript_fts(rowid, transcript)
          SELECT NEW.id, COALESCE((
            SELECT group_concat(text, ' ')
            FROM (
              SELECT
                CASE WHEN segment.type = 'object'
                  THEN json_extract(segment.value, '$.text')
                END AS text
              FROM json_each(
                CASE WHEN json_valid(NEW.transcript) THEN NEW.transcript END,
                '$.segments'
              ) AS segment
              ORDER BY CAST(segment.key AS INTEGER)
            )
          ), '')
          WHERE NEW.transcript IS NOT NULL;
        END
        """
    )

    try db.execute(
      sql: """
        CREATE TRIGGER episode_transcript_fts_delete
        AFTER DELETE ON episode
        BEGIN
          DELETE FROM episode_transcript_fts WHERE rowid = OLD.id;
        END
        """
    )
  }
}
