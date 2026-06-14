---
status: shipped
---

# SQLite Smart List Optimizer Maintenance

Research note for the Smart List query-planner work shipped in PR #455. Researched 2026-06-13 against SQLite docs/source, GRDB docs/source, and the PodHaven implementation.

## Status

Keep the current approach:

- `Migration_v59` runs `ANALYZE` once after adding Smart List indexes and replacing the rating index.
- Every database connection applies `PRAGMA analysis_limit=400` in `AppDB.makeConfiguration`.
- `DatabaseMaintainer` runs `AppDB.optimize()` whenever the app backgrounds.
- `AppDB.optimize()` runs `PRAGMA optimize=0x1fffe` through `writeWithoutTransaction`.

The important part is the mask. `0x1fffe` means "SQLite's default optimize mask, plus the all-table eligibility bit." It does not force a full `ANALYZE` of every table. It only makes every ordinary table eligible for SQLite's normal "might benefit from ANALYZE" checks, including the row-count drift check.

## Why this exists

The Smart List performance work created several indexes that matter only if SQLite has current enough planner statistics:

- `episode_on_creationDate`
- `episode_on_duration`
- partial `episode_on_finishDate`
- partial `episode_on_queueDate`
- `episodeTag_on_tagId_episodeId`
- `podcastTag_on_tagId_podcastId`
- `episode_on_rating_pubDate`

`Migration_v59` correctly runs `ANALYZE` after those schema changes. That gives SQLite a good initial `sqlite_stat1` snapshot for existing rows, but those stats do not update as a user's library grows. Without maintenance, a database that receives many new episodes can keep using stale cardinality estimates and lose the intended index wins.

The risk is highest for Smart Lists because the hot path is read-heavy and observation-driven:

1. `Container.makeObservatory()` builds `Observatory(self.appDB().reader)`.
2. `Observatory.listablePodcastEpisodes(filter:order:limit:)` calls `reader.observe`.
3. `AppDB.Reader.observe` wraps the query in `ValueObservation.tracking(...).values(in: appDB.db)`.
4. In production, `AppDB._onDisk` uses `DatabasePool`, not `DatabaseQueue`.
5. GRDB documents `DatabasePool` as one writer SQLite connection plus a pool of read-only SQLite connections.

So Smart List display reads normally run through reader connections, while `AppDB.optimize()` runs on the writer connection. Plain `PRAGMA optimize` partly keys off query-planner history accumulated by the same SQLite connection. That means a writer-side plain optimize can miss tables whose heavy read plans were exercised only by reader connections.

## SQLite behavior that matters

SQLite's current `PRAGMA optimize` decision tree has two separate gates:

- Eligibility gate: should this table be considered for possible analysis?
- Drift gate: if considered, has it never been analyzed or changed enough to re-analyze?

The eligibility gate is where the reader/writer split matters. SQLite considers an ordinary non-system table if one of these is true:

- the `0x10000` mask bit is set;
- an index on the table has no `sqlite_stat1` entry;
- the current connection has previously used `sqlite_stat1` statistics for that table.

The drift gate is still selective. Once a table is considered, SQLite only runs `ANALYZE` if an index lacks stats or the table row count has grown or shrunk by about 10x since the last stats snapshot.

That makes `0x10000` the right fix for PodHaven. It removes the same-connection query-history dependency without turning background maintenance into "analyze everything every time."

## Why `0x1fffe`

SQLite's documented default optimize mask is `0xfffe`/`0x0fffe`. The current meaningful default bits include:

- `0x00002`: run `ANALYZE` on tables that might benefit.
- `0x00010`: use a bounded analysis limit for optimize-triggered analysis.

SQLite's docs often show `PRAGMA optimize=0x10002` for a fresh long-lived connection because that combines "run ANALYZE when useful" with "check every table." For PodHaven's recurring maintenance call, `0x1fffe` is a better expression of the intent:

```text
0x0fffe   SQLite default optimize behavior
0x10000   also check every table for drift
--------
0x1fffe
```

That preserves current and future default-on optimize behaviors while adding the single non-default behavior PodHaven needs.

## What the `400` analysis limit still does

`analysis_limit` controls roughly how many rows SQLite examines per index while running `ANALYZE`. It does not control which tables are checked for drift, and it is not a total row budget for the whole optimize pass.

The `400` constant still has real effect:

- `AppDB.makeConfiguration` runs `PRAGMA analysis_limit=400` for every connection GRDB opens.
- SQLite source currently leaves a lower positive connection analysis limit in place when `PRAGMA optimize` would otherwise use its built-in temporary optimize limit.
- If the connection limit were removed, `0x1fffe` would still keep optimize bounded by SQLite's built-in default; with the connection limit present, PodHaven's stricter `400` cap wins.

So the constant is not obsolete. It is a conservative cap on the cost of each table/index analysis. The tradeoff is normal approximate-ANALYZE behavior: stats may be less exact than a full index scan, but SQLite documents values in this range as usually precise enough and much cheaper.

## Why not just run full `ANALYZE`

Full `ANALYZE` is appropriate immediately after `Migration_v59` creates or replaces indexes, because that migration is a one-time schema change and should seed stats for every existing user database.

It is the wrong recurring maintenance primitive. A full analysis can scan every index and can be expensive on large libraries. `PRAGMA optimize` is designed for periodic app maintenance: most invocations are no-ops or near-no-ops, and the times it does run `ANALYZE`, it limits work.

## Why backgrounding is the trigger

SQLite's primary recommendation for short-lived connections is to run optimize before closing the connection. PodHaven's production database is a long-lived GRDB `DatabasePool`, so connection close is not a useful mobile lifecycle signal.

Backgrounding is the closest practical equivalent:

- it happens far more often than app cold launch;
- it is after a foreground session that may have accumulated inserts, updates, and read workloads;
- it is not on the critical path for opening an episode list;
- `BackgroundTask` gives the app a short window to finish the maintenance write.

Running optimize on launch would also work mechanically, but it would add work to a more user-visible path and would not benefit from the just-finished foreground session's data changes.

## FTS and normal indexes

Smart List text `contains`/`doesNotContain` queries use the external-content FTS5 mirrors from `Migration_v48`:

- `episode_fts`
- `podcast_fts`

Those mirrors are maintained by FTS triggers and are queried through rowid membership subqueries. `PRAGMA optimize`/`ANALYZE` maintenance is mainly about ordinary tables and indexes, not rebuilding FTS virtual-table content.

That means both pieces are required:

- FTS mirrors make text membership fast.
- Ordinary indexes plus current `sqlite_stat1` stats make sort/filter/tag/rating/date plans predictable.

## Local reproduction

This SQLite-only reproduction captures the reader-history issue without any app code. It analyzes a one-row table, grows it to 1000 rows without exercising a query plan that uses its stats, then compares plain optimize with the forced mask.

```sh
sqlite3 :memory: <<'SQL'
CREATE TABLE probe(value INTEGER);
CREATE INDEX probe_value ON probe(value);
INSERT INTO probe VALUES (1);
ANALYZE probe;
WITH RECURSIVE c(x) AS (
  VALUES(2)
  UNION ALL
  SELECT x + 1 FROM c WHERE x < 1000
)
INSERT INTO probe SELECT x FROM c;
SELECT 'before', stat FROM sqlite_stat1 WHERE tbl = 'probe';
PRAGMA optimize;
SELECT 'plain', stat FROM sqlite_stat1 WHERE tbl = 'probe';
PRAGMA optimize=0x1fffe;
SELECT 'forced', stat FROM sqlite_stat1 WHERE tbl = 'probe';
SQL
```

Observed locally with SQLite `3.51.0`:

```text
before|1 1
plain|1 1
forced|1000 1
```

`AppDBOptimizeTests.optimizeChecksAllTables` pins the same behavior inside the app test harness: stale stats remain stale until `AppDB.optimize()` runs the forced all-table eligibility mask.

## Maintenance rules

Keep these rules when changing this area:

- New indexes in migrations should be followed by one migration-time `ANALYZE`, as `Migration_v59` does.
- Recurring app maintenance should use `PRAGMA optimize`, not raw recurring `ANALYZE`.
- Keep `PRAGMA optimize=0x1fffe` unless SQLite changes the meaning of the default mask or the all-table bit.
- Keep `analysis_limit=400` unless we have measured that the limit is too low for real Smart List plans or too high for background runtime.
- If a future DB access path bypasses `AppDB.makeConfiguration`, it must apply the same analysis-limit setup.
- If Smart List reads ever move to a writer-only `DatabaseQueue`, plain optimize would be less risky, but the forced mask would still be safe and more robust.

## Local files

- [`AppDB.swift`](../../PodHaven/Database/AppDB.swift): per-connection analysis limit and forced optimize mask.
- [`DatabaseMaintainer.swift`](../../PodHaven/Database/DatabaseMaintainer.swift): background lifecycle trigger.
- [`Migration_v48.swift`](../../PodHaven/Database/Migrations/Migration_v48.swift): external-content FTS5 mirrors.
- [`Migration_v59.swift`](../../PodHaven/Database/Migrations/Migration_v59.swift): Smart List indexes and migration-time `ANALYZE`.
- [`SmartListFilterEngine.swift`](../../PodHaven/Database/SmartListFilterEngine.swift): FTS membership subqueries and tag/date/duration expressions.
- [`Observatory.swift`](../../PodHaven/Database/Observatory.swift): Smart List reads via `AppDB.Reader`.
- [`AppDBOptimizeTests.swift`](../../PodHavenTests/DatabaseTests/AppDBOptimizeTests.swift): analysis-limit and forced-optimize coverage.

## Sources

- [SQLite PRAGMA optimize](https://www.sqlite.org/pragma.html#pragma_optimize)
- [SQLite ANALYZE and recommended PRAGMA optimize usage](https://www.sqlite.org/lang_analyze.html)
- [SQLite source: `PRAGMA optimize` implementation](https://github.com/sqlite/sqlite/blob/master/src/pragma.c#L2460-L2585)
- [SQLite source: `OP_SqlExec` temporary analysis-limit handling](https://github.com/sqlite/sqlite/blob/master/src/vdbe.c#L7101-L7142)
- [GRDB DatabasePool documentation](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Extension/DatabasePool.md)
- [GRDB concurrency documentation](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Concurrency.md)
