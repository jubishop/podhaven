// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV66(_ db: Database) throws {
    // Rebuild cached inferred cadences with the runtime bands in
    // FreshnessCadence.infer. These literals are persisted data semantics:
    // changing runtime bands after this migration ships requires another
    // migration to rewrite existing cached rows.
    try db.execute(
      sql: """
        WITH limitedEpisodes AS (
          SELECT podcastId, pubDate
          FROM (
            SELECT podcastId, pubDate,
              ROW_NUMBER() OVER (PARTITION BY podcastId ORDER BY pubDate DESC) AS rn
            FROM episode
          )
          WHERE rn <= 100
        ),
        episodeCounts AS (
          SELECT podcastId, COUNT(*) AS episodeCount
          FROM limitedEpisodes
          GROUP BY podcastId
        ),
        gaps AS (
          SELECT podcastId,
            (julianday(pubDate)
              - julianday(LAG(pubDate) OVER (PARTITION BY podcastId ORDER BY pubDate ASC)))
              * 24.0 AS gapHours
          FROM limitedEpisodes
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
        ),
        inferred AS (
          SELECT podcast.id AS podcastId,
            CASE
              WHEN COALESCE(episodeCounts.episodeCount, 0) = 0 THEN NULL
              WHEN episodeCounts.episodeCount < 3 THEN 'weekly'
              WHEN medians.medianHours <= 1.5 THEN 'hourly'
              WHEN medians.medianHours <= 18 THEN 'twiceDaily'
              WHEN medians.medianHours <= 36 THEN 'daily'
              WHEN medians.medianHours <= 126 THEN 'twiceWeekly'
              WHEN medians.medianHours <= 252 THEN 'weekly'
              WHEN medians.medianHours <= 1080 THEN 'monthly'
              ELSE 'evergreen'
            END AS cadence
          FROM podcast
          LEFT JOIN episodeCounts ON episodeCounts.podcastId = podcast.id
          LEFT JOIN medians ON medians.podcastId = podcast.id
        )
        UPDATE podcast
        SET inferredFreshnessCadence = (
          SELECT cadence
          FROM inferred
          WHERE inferred.podcastId = podcast.id
        )
        """
    )
  }
}
