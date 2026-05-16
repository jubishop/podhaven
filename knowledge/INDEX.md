# Knowledge index

Catalog of long-form reference pages. One line per page. Grouped by area; alphabetical within a group.

## Swift concurrency & isolation

- [Factory v3 actor-isolation pattern](factory_v3_migration.md) — how to define Factory closures for `@MainActor` / global-actor types after Factory v3.0; test target's `autoRegister` pitfall.
- [Observable + Broadcast observation gap](observation_broadcast_viewmodel.md) — reading `@Broadcasted` SharedState through an `@Observable` viewModel's computed property can silently fail for conditional views; read SharedState directly instead.
- [observationRestartsAfter… CI flake (resolved)](flaky_test_observation_restarts.md) — `Wait.until`'s `.background` poller starved an inner observation `Task {}`; fixed by adding `priority:` param.
- [`Task.detached` migration pattern](task-detached-migration.md) — why `Task.detached` is banned and how to hop off `@MainActor` for CPU work using `nonisolated async` on a value type instead.

## Workflow & tooling

- [Worktree setup hooks](worktree_setup_hooks.md) — git post-checkout hook (preferred), direnv approval, failed approaches, Xcode build optimization for worktrees.
