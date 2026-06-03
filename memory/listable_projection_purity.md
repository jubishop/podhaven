---
name: listable-projection-purity
description: Keep ListableEpisode/ListablePodcastEpisode as rendering-only projections; don't add columns just to make an unrelated caller simpler
type: feedback
---
`ListableEpisode` / `ListablePodcastEpisode` are deliberately slim list-row projections. Do not add a column/field to them just because it makes some other feature simpler — e.g. adding `podcastId` so a sort can build a `CandidateEpisode` without a DB round-trip. If the data isn't needed to render the row itself, it doesn't belong in the projection.

**Why:** every added field widens the per-row selection across every list surface (Episodes lists, podcast detail, Up Next) and changes the projection's `Hashable`/equality — a cost paid everywhere, to serve one unrelated caller. That erodes the whole reason the slim projection exists, one "harmless" column at a time.

**How to apply:** when a caller needs data the projection lacks (e.g. `Podcast.ID` for recommendation scoring of queued rows), resolve it in the owning layer instead — a focused engine/repo method that fetches what it needs by ID (see `RecommendationEngine.recommendationScores(forEpisodeIDs:)`, which fetches episodes to build `CandidateEpisode`s rather than fattening the row type). Keep the cost contained to that caller.
