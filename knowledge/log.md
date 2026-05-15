# Knowledge log

Append-only timeline of additions, updates, archives, and lint passes for `knowledge/`.

Format: `## [YYYY-MM-DD] <kind> | <title>` where `<kind>` ∈ `add | update | archive | lint`.

---

## [2026-05-15] add | knowledge/ directory created

Initial scaffold: `README.md` (schema), `INDEX.md` (catalog), `log.md` (this file). Migrated 4 reference pages from `memory/` that were misclassified as auto-load memory but were actually long-form reference: `factory_v3_migration`, `observation_broadcast_viewmodel`, `flaky_test_observation_restarts`, `worktree_setup_hooks`.

## [2026-05-15] add | task-detached-migration

Extracted the `Task.detached` workaround pattern from AGENTS.md (Shared Utilities & Helpers section). The *ban* stays auto-loaded in AGENTS.md; the *migration pattern* (`nonisolated async` on a value type) lives here, consulted on demand when refactoring a `Task.detached` call site.
