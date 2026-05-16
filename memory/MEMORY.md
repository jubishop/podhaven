- [NowPlayingInfo desync bug](project_nowplaying_desync_bug.md) — iOS sends stale backward scrub ~30–33s after AirPods pause in background; 6 incidents, fb43f650 fix DID NOT hold (4/19 recurrence with dict only 2s stale at pause — refutes dict-staleness theory)
- [PlayBar sheet stuck off-screen bug](sheet_presentation_desync.md) — chevron-up failed to present (2026-04-26, non-reproducible); theory is `Sheet.config` stuck non-nil leaving SwiftUI's `isPresented` wedged; fix on PR `worktree-sheetFixes` switches to `.sheet(item:)`
- [Recommendation sort prewarming](recommendation_sort_prewarming.md) — precompute rec scores so PodcastDetail/EpisodesList rec-sort toggles stay snappy.
- [PodcastDetail recommendation-score fan-out OOM](podcast_detail_recommendation_storm.md) — Sentry feedback `podhaven:7485822944` on build 1.0+495 (commit `9e5299de4`); fix planned at #274 (coalescer + split compute/apply + route triggers + dropFirst+initial schedule); validation procedure (xctrace simulator + on-device Instruments) lives in this entry. Not yet implemented.

---

Schema and conventions: [memory/README.md](README.md). Append-only timeline: [memory/log.md](log.md). Long-form reference pages (library quirks, debugging recipes, workflow guides) live in [knowledge/INDEX.md](../knowledge/INDEX.md) and are loaded on demand via `qmd query` or direct `Read` — not auto-loaded here.
