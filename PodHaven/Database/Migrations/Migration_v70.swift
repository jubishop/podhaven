// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV70(_ db: Database) throws {
    try db.execute(sql: "UPDATE episode SET transcript = NULL WHERE transcript IS NOT NULL")

    try db.create(table: "episodeTranscriptionCheckpoint") { t in
      t.primaryKey("episodeId", .integer).references("episode", onDelete: .cascade)
      t.column("checkpointJSON", .text).notNull()
        .check(
          sql: """
            json_valid(checkpointJSON)
            AND json_type(checkpointJSON) IS 'object'
            AND json_type(checkpointJSON, '$.segments') IS 'array'
            AND (
              json_type(checkpointJSON, '$.audioTime') IS 'integer'
              OR json_type(checkpointJSON, '$.audioTime') IS 'real'
            )
            AND (
              json_type(checkpointJSON, '$.duration') IS 'integer'
              OR json_type(checkpointJSON, '$.duration') IS 'real'
            )
            AND json_type(checkpointJSON, '$.locale') IS 'text'
            AND json_type(checkpointJSON, '$.audioSHA256') IS 'text'
            AND length(json_extract(checkpointJSON, '$.audioSHA256')) IS 64
            AND json_extract(checkpointJSON, '$.audioSHA256') NOT GLOB '*[^0-9a-f]*'
            """
        )
    }
  }
}
