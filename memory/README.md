# Memory

Long-lived repo notes for LLM agents: user guidance, incidents, gotchas, post-mortems, library quirks, debugging recipes, and external refs.

Not auto-loaded; discover pages with `git knowledge`. Before writing, run `git knowledge search` and update an existing related page when possible.

## Scope

- User preferences, feedback, corrections, validated approaches.
- Open incidents and active investigations.
- Gotchas, library quirks, workarounds, post-mortems.
- Pointers to external systems (dashboards, issue projects, email threads).

Do not use memory for:

- Code patterns, conventions, file paths: derivable from the code.
- Git history, recent changes: `git log` / `git blame` are authoritative.
- Intentional architecture / planning: use [`../docs/`](../docs/README.md).
- TODOs and planned work: use GitHub issues.

## Format

Each page is one `.md` file with frontmatter:

```yaml
---
name: kebab-case-slug
description: one-line summary, used in search snippets
type: user | feedback | project | reference
status: active | resolved   # project notes only; omit on other types
---
```

The filename must match `name`: `kebab-case-slug.md`. Each page needs a top-level title. Use ordinary relative Markdown links, including `.md`. Quote descriptions that contain YAML punctuation.

This schema applies to memory **pages**. Tool-managed ledgers under `pr_reviews/` and legacy ledgers under `sentry_feedback/` are exempt — they keep their owning skills' frontmatter; see [PR review ledgers](#pr-review-ledgers) and [Legacy Sentry feedback ledgers](#legacy-sentry-feedback-ledgers).

Types:

- `user`: user facts and preferences.
- `feedback`: user corrections and validated approaches.
- `project`: non-derivable ongoing context; convert relative dates to absolute.
- `reference`: library quirks, external refs, and other durable learnings.

`project` notes must include `status: active` while the incident or investigation is live. Set `status: resolved` and move to `memory/archive/` when verified done.

For `feedback` and `project`, lead with the rule/fact, then:

```
**Why:** <reason: past incident, constraint, strong preference>

**How to apply:** <when/where this kicks in>
```

Use `[Page title](page-name.md)` to cross-link pages.

## Archive

When a note is no longer relevant for day-to-day lookup — resolved incidents, superseded guidance, outdated context — move it to `memory/archive/`. Set `status: resolved` only on project notes; omit status on other types. Archived notes stay in git for history but are excluded from `qmd` indexing — the `memory` collection ignores `archive/**` — so stale pages do not compete with live notes in search.

## PR review ledgers

`memory/pr_reviews/<pr-number>.md` files are tool-managed review ledgers written by the `/review`, `/prfix`, and `/team-review` skills. They use those skills' own frontmatter (`pr`, `title`, `branch`, `base`, `repo`) rather than the page schema above, and are excluded from `qmd` indexing — the `memory` collection ignores `pr_reviews/**` alongside `archive/**`. `/team-review` only appends `pending` findings for a later `/review` pass; don't reformat ledgers to the page schema or hand-edit them; the skills own their lifecycle.

## Legacy Sentry feedback ledgers

Older versions of `analyze-sentry-feedback` wrote `memory/sentry_feedback/<path-safe-slug>.md` files (slug `:` replaced with `-`, e.g. `podhaven-7485822944.md`) as tool-managed triage ledgers. They remain read-only historical records with their original frontmatter (`slug`, `shortId`, `description`, `sentry-status`) and newest-first session log. Current triage uses the matching GitHub issue as its durable record and does not create or update these ledgers. Don't reformat the legacy files to the page schema. They have a separate `sentry-history` collection excluded from default search. During Sentry triage, deliberately search `git knowledge search "symptom or issue ID" -c sentry-history`, then verify old hypotheses against current code.

## Active notes

Run `bin/memory-index` after adding, renaming, or archiving an ordinary note.
The command owns only the list between the markers. Preserve all policy text.
The scheduled audit generates this section after validating the model patch;
the model cannot edit this README. `bin/check` rejects stale generated content.

<!-- ACTIVE_MEMORY_START -->

- [Build variants: Development / Debug / Release](build-variants-dev-debug-release.md): PodHaven's three app build variants — Development (.dev), Debug (.debug), Release (production) — their bundle IDs, isolated on-disk data directories, which scheme action builds each, and how runtime environment (separate axis) drives logging.
- [Device debug builds break background scheduling](device-debug-builds-break-background-scheduling.md): Installing a debug build on @jubishop's iPhone kills iOS background scheduling for every build on that device; the Simulator and TestFlight are the only run targets, and the physical device has no debugger.
- [Factory v3 migration](factory-v3-migration.md): How to define and migrate Factory closures for @MainActor / global-actor types after Factory v3.0
- [FTS5 sync triggers don't survive a source-table rebuild](fts5-sync-triggers-and-table-rebuilds.md): Rebuilding the episode/podcast tables silently breaks the FTS5 search index; the rebuild must recreate the \*_fts virtual tables.
- [Listable projection purity](listable-projection-purity.md): Keep ListableEpisode/ListablePodcastEpisode as rendering-only projections; don't add columns just to make an unrelated caller simpler
- [Lucide icon asset resync](lucide-icon-asset-resync.md): Re-syncing vendored Lucide icons must preserve filter/fingerprint/waves rawValues, which are persisted in tag.icon and smartList.icon
- [Memory-audit model selection](memory-audit-model-selection.md): Treat the scheduled memory audit as semantic curation and keep DeepSeek V4 Flash until task-specific evidence supports a replacement within the $0.20 run budget.
- [Metrickit disk write diagnostics](metrickit-disk-write-diagnostics.md): Why we drop MXDiskWriteException MetricKit diagnostics in Sentry, and why PODHAVEN-3W recurrences are not a PR #355 regression
- [Nowplaying elapsed time desync](nowplaying-elapsed-time-desync.md): Recurring bug where iOS sends a stale backward scrub ~30–33s after AirPods-triggered background pause. 6 confirmed incidents. Both the incident-3 fix (event-driven writes) and the incident-5 fix (fb43f650, periodic CurrentPlaybackDate anchor + playbackState mirror) FAILED to prevent recurrence on 4/19. Response: removed CurrentPlaybackDate entirely (on-demand audio doesn't need it) and added a 30s wall-clock diagnostic snapshot to catch AVPlayer/dict/mediaserverd drift on the next incident.
- [Observation broadcast viewmodel](observation-broadcast-viewmodel.md): Broadcast notifies SwiftUI synchronously for main-actor writes (#399) and one main-turn late for off-main writes; that timing decides whether a @Broadcasted value can be read through an @Observable viewModel computed property
- [\`OPMLViewModel\` must be a \`.cached\` Container factory](opml-viewmodel-cached-factory.md): OPMLViewModel must be a .cached Container factory so ShareService and OPMLView share one instance, or the OPML import-progress sheet never appears.
- [Search recommendation "top picks" latency](search-recommendation-embedding-perf.md): Search "top picks" latency is bound by the serialized embedding actor, not RSS fan-out; the podcast-context vector is computed once per feed.
- [Stalled playback load](stalled-playback-load.md): Investigation notes for feedback podhaven:7514288031, where playback stayed in loading after selecting an episode. Use when a future report says an episode load sat on the loading indicator, especially around PlayManager.performLoad, Queue.unshift, or DB writer access.
- [\`Task.detached\` migration pattern](task-detached-migration.md): Why \`Task.detached\` is banned and how to hop off \`@MainActor\` for CPU work without it.
- [Worktree cache lessons](worktree-setup-hooks.md): Past worktree cache failures, stale SwiftPM artifact paths, and approaches that broke Xcode builds.

<!-- ACTIVE_MEMORY_END -->
