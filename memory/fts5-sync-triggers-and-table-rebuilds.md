---
name: "fts5-sync-triggers-and-table-rebuilds"
description: "Rebuilding the episode/podcast tables silently breaks the FTS5 search index; the rebuild must recreate the *_fts virtual tables."
type: "reference"
---

# FTS5 sync triggers don't survive a source-table rebuild

Episode/podcast text search is backed by two **external-content FTS5** virtual tables, `episode_fts` and `podcast_fts`, created in the v48 migration (#400). They hold only the search index; the actual text is read from `episode`/`podcast` by `rowid` (which equals the source row's `id`). They're kept current by GRDB's `synchronize(withTable:)`, which installs **AFTER INSERT/UPDATE/DELETE triggers on the source `episode`/`podcast` tables** and back-fills existing rows once at creation.

## The gotcha

The codebase's schema-change pattern for adding/removing/altering a column is the SQLite 12-step **table rebuild**: create a new table, copy rows, drop the old table, rename. See the rebuild migrations (`Migration_v42`/`v44`/`v46`) — each one re-creates the `episode_on_*` indexes afterward because dropping the old table drops its indexes.

Those triggers live on the source table the same way. **A rebuild silently drops the FTS sync triggers**, and there's no error — the index just goes stale: new/edited/deleted episodes stop appearing or disappearing from search results, and RSS refreshes (which UPDATE titles/descriptions) quietly desync it.

## What a future rebuild migration must do

After rebuilding `episode` or `podcast`, drop and recreate the matching virtual table so `synchronize` reinstalls the triggers and rebuilds content:

```swift
try db.drop(table: "episode_fts")
try db.create(virtualTable: "episode_fts", using: FTS5()) { t in
  t.synchronize(withTable: "episode")
  t.column("title")
  t.column("description")
}
```

Same as how the rebuild migrations already re-create the dropped indexes — the FTS tables are one more thing in that list. `Migration_v49` does this for `podcast_fts` after dropping and rebuilding `podcast` (`PodHaven/Database/Migrations/Migration_v49.swift:79-85`).

**Also re-create the v68 update triggers.** v68 replaced the UPDATE sync trigger on each table with a column-restricted one, `__episode_fts_au` / `__podcast_fts_au`, which fire `AFTER UPDATE OF title, description` (`PodHaven/Database/Migrations/Migration_v68.swift:36-64`). The restriction keeps the timestamp-only updates from the `episode_content_updated` / `podcast_content_updated` triggers (same file, lines 8-32) out of FTS sync. A rebuild drops those source-table triggers along with the table. `synchronize` installs GRDB's default update trigger for the same path, which v68 replaced. After `synchronize`, re-run v68's `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER` pairs for the FTS update triggers, and recreate the two content triggers.

## Related

- [task-detached-migration](task-detached-migration.md) — another migration-adjacent reference note.
