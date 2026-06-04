// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV50(_ db: Database) throws {
    // Cached per-podcast auto-inferred cadence. Manual `freshnessCadence` stays
    // the user override; recommendation scoring resolves
    // `freshnessCadence ?? inferredFreshnessCadence ?? default` as plain column
    // reads instead of rescanning episode pubDates on every observation fire.
    //
    // Hoisted to a `let` so the check closure stays a single `.contains` call —
    // chaining the equalities inline trips SwiftCompiler's type-checker timeout
    // on cold CI builds.
    let allowedCadences = [
      "hourly", "twiceDaily", "daily", "twiceWeekly", "weekly", "monthly", "evergreen",
    ]
    try db.alter(table: "podcast") { t in
      t.add(column: "inferredFreshnessCadence", .text)
        .check { $0 == nil || allowedCadences.contains($0) }
    }

    // One-time backfill mirroring FreshnessCadence.infer in raw SQL (migrations
    // can't call model code). For each podcast, take its 100 most-recent
    // pubDates, bucket the median consecutive gap (in hours) into a cadence.
    // The `gapCount >= 2` guard restricts this to podcasts with >= 3 episodes,
    // matching infer's sparse-input fallback: fewer than 3 episodes stay NULL
    // and resolve to the default cadence, and the live per-podcast recompute
    // fills them in as episodes arrive. Median index `gapCount / 2 + 1` (1-based)
    // matches infer's 0-based `gaps[gaps.count / 2]`; the hour ceilings match
    // FreshnessCadence's published bands.
    try db.execute(
      sql: """
        WITH gaps AS (
          SELECT podcastId,
            (julianday(pubDate)
              - julianday(LAG(pubDate) OVER (PARTITION BY podcastId ORDER BY pubDate ASC)))
              * 24.0 AS gapHours
          FROM (
            SELECT podcastId, pubDate,
              ROW_NUMBER() OVER (PARTITION BY podcastId ORDER BY pubDate DESC) AS rn
            FROM episode
          )
          WHERE rn <= 100
        ),
        ranked AS (
          SELECT podcastId, gapHours,
            ROW_NUMBER() OVER (PARTITION BY podcastId ORDER BY gapHours ASC) AS gapRank,
            COUNT(*) OVER (PARTITION BY podcastId) AS gapCount
          FROM gaps
          WHERE gapHours IS NOT NULL
        ),
        medians AS (
          SELECT podcastId, gapHours AS medianHours
          FROM ranked
          WHERE gapCount >= 2 AND gapRank = gapCount / 2 + 1
        )
        UPDATE podcast SET inferredFreshnessCadence = (
          CASE
            WHEN medians.medianHours <= 3 THEN 'hourly'
            WHEN medians.medianHours <= 16 THEN 'twiceDaily'
            WHEN medians.medianHours <= 36 THEN 'daily'
            WHEN medians.medianHours <= 126 THEN 'twiceWeekly'
            WHEN medians.medianHours <= 252 THEN 'weekly'
            WHEN medians.medianHours <= 1080 THEN 'monthly'
            ELSE 'evergreen'
          END
        )
        FROM medians
        WHERE podcast.id = medians.podcastId
        """
    )
  }
}
