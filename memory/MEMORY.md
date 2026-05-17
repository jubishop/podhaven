<!-- Hot tier, capped at 25. Daily lint enforces by git mtime; demoted pages move to memory/cold/ (still queryable via qmd, not auto-loaded). -->

- [NowPlayingInfo desync bug](project_nowplaying_desync_bug.md) — iOS sends stale backward scrub ~30–33s after AirPods pause in background; 6 incidents, fb43f650 fix DID NOT hold (4/19 recurrence with dict only 2s stale at pause — refutes dict-staleness theory)
- [PlayBar sheet stuck off-screen bug](sheet_presentation_desync.md) — chevron-up failed to present (2026-04-26, non-reproducible); theory is `Sheet.config` stuck non-nil leaving SwiftUI's `isPresented` wedged; fix on PR `worktree-sheetFixes` switches to `.sheet(item:)`
- [Recommendation sort prewarming](recommendation_sort_prewarming.md) — precompute rec scores so PodcastDetail/EpisodesList rec-sort toggles stay snappy.
- [PodcastDetail recommendation-score fan-out OOM](podcast_detail_recommendation_storm.md) — post-landing verification procedure for issue #274 (xctrace simulator + on-device Instruments + log-grep). Diagnosis/fix plan live in #274.

---

Schema and conventions: [memory/README.md](README.md). Append-only timeline: [memory/log.md](log.md). Discovered learnings (post-mortems, library quirks, debugging recipes) live in [knowledge/INDEX.md](../knowledge/INDEX.md) and are loaded on demand via `qmd query` or direct `Read` — not auto-loaded here.
