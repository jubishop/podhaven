// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV78(_ db: Database) throws {
    try db.execute(
      sql: """
        UPDATE episode
        SET transcript = json_set(
          transcript,
          '$.segments',
          json((
            SELECT json_group_array(
              CASE WHEN segment.type IS 'object'
                THEN json(json_set(segment.value, '$.words', json('[]')))
                ELSE segment.value
              END
            )
            FROM json_each(transcript, '$.segments') AS segment
          ))
        )
        WHERE transcript IS NOT NULL
          AND json_valid(transcript)
          AND json_type(transcript, '$.segments') IS 'array'
        """
    )

    try db.execute(
      sql: """
        UPDATE episodeTranscriptionCheckpoint
        SET checkpointJSON = json_set(
          checkpointJSON,
          '$.segments',
          json((
            SELECT json_group_array(
              CASE WHEN segment.type IS 'object'
                THEN json(json_set(segment.value, '$.words', json('[]')))
                ELSE segment.value
              END
            )
            FROM json_each(checkpointJSON, '$.segments') AS segment
          ))
        )
        WHERE json_valid(checkpointJSON)
          AND json_type(checkpointJSON, '$.segments') IS 'array'
        """
    )
  }
}
