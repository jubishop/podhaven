# Memory log

Append-only timeline of additions, updates, archives, lint passes, and dated incidents tied to open investigation pages.

Format: `## [YYYY-MM-DD] <kind> | <title>` where `<kind>` ∈ `add | update | archive | lint | incident`.

---

## [2026-05-15] lint | adopt LLM Wiki structure

Restructured `memory/` to align with Karpathy's LLM Wiki pattern (see `memory/README.md`, `knowledge/README.md`). Moved 4 long-form reference pages to `knowledge/`: `factory_v3_migration`, `observation_broadcast_viewmodel`, `flaky_test_observation_restarts`, `worktree_setup_hooks`. They were classified as memory but their content was long-form reference, not currently-active context.

## [2026-05-15] add | memory/log.md and memory/README.md

Added explicit schema page (`README.md`) and this append-only timeline (`log.md`).
