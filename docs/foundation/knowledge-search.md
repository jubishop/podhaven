---
status: current
---

# Knowledge search

Projects keep knowledge as Markdown in `memory/` and `docs/` and search it
with optional [QMD](https://github.com/tobi/qmd). Each checkout has its own
index, and Git hooks refresh it in the background.

## Search

Use `bin/knowledge`, or `git knowledge` from any subdirectory; setup adds that
alias when the name is free.

```sh
git knowledge search "worktree" -c docs
git knowledge query "how should decisions be recorded" --no-rerank
git knowledge get qmd://docs/development-workflow.md -l 80
git knowledge context list
```

Use keyword `search` for names and known terms and `query` for broader
questions, then read the focused source page; Markdown files are
authoritative. Reading known files, and broadening a successful search that
found nothing, are normal work.

The command passes QMD its configuration, cache, and database paths without
changing the shell environment, and it refuses named indexes. To select an
executable, run `git config --local knowledge.qmdPath /absolute/path/to/qmd`.

`.config/knowledge.json` defines collections, exclusions, and the short
descriptions attached to results. Edit it rather than the generated
`.config/qmd/index.yml`. Collections use `**/*.md` patterns. Each QMD command
receives a temporary copy of the generated configuration, so QMD can rewrite
that copy without affecting freshness checks.

## Search failures

When configured QMD fails, tell the user immediately what failed. Run
`bin/doctor`, inspect `.cache/qmd/index.log`, and attempt a focused repair.
Confirm recovery by repeating the failed lookup successfully; never report
success from a command that failed, timed out, or discarded results.

If repair fails, pause knowledge-dependent work until the user explicitly
approves a fallback. Do not silently substitute `rg`, direct reads, another
index, or another search tool. Unrelated work may continue. A successful
search with no matches is not a failure. Operating without QMD requires an
explicit project decision or user approval; a broken tool never establishes
that choice.

## Refresh and recovery

The `post-checkout`, `post-commit`, `post-merge`, and `post-rewrite` hooks
request background refreshes; they do not observe file saves. After
uncommitted knowledge edits, run `bin/qmd-index` when current results matter;
it waits and reports success or failure. `bin/qmd-index --force` rebuilds
even when inputs match, such as after replacing a custom QMD build that keeps
its release version.

Every lookup verifies sources, configuration, the database, the QMD release,
and the last refresh before returning results. Stale inputs trigger a refresh
that waits up to 60 seconds; set `knowledge.searchRefreshTimeout` in local Git
configuration to change the bound. Results are discarded if the refresh fails
or times out, QMD fails, or sources change during the lookup. Progress goes to
stderr so JSON output stays valid.

One worker per checkout hashes indexed inputs, skips unchanged work, coalesces
bursts of requests, and runs again when files change mid-refresh. Avoid direct
`qmd update` and `qmd embed`, which bypass this coordination. Logs rotate at
about 1 MB and keep one previous file.

## Optional home memory

Personal notes are excluded by default. To include them locally:

```sh
git config --local knowledge.homeMemoryPath /absolute/path/to/personal/notes
bin/qmd-index
```

Linked worktrees share the setting, and it is never committed. Notes are
indexed, not copied. Unset the setting and refresh to remove the collection.

## Worktrees and models

```sh
git worktree add -b feature-name worktrees/feature-name
```

The first checkout prepares a new worktree, and `bin/prep-worktree` repeats
that preparation. Each checkout keeps its own `.cache/qmd/index.sqlite`.
Every project shares model files at `~/.cache/qmd/models`, independent of
`XDG_CACHE_HOME`, through each checkout's `.cache/qmd/models` link. Setup
migrates old local caches after verifying their contents and stops without
deleting anything when files conflict. Never delete the shared model
directory while cleaning up a checkout.

A worktree's `.envrc` is approved automatically only when it matches a primary
checkout file that direnv already allows. After moving a checkout, repair the
worktree, run `bin/doctor`, and rerun `bin/prep-worktree`. Remove a worktree
only after checking for uncommitted and unpushed work, then verify
`git worktree list`.

## Existing hooks

Setup does not replace an active `core.hooksPath` or executable hooks in the
default hooks directory. Integrate through the existing manager instead: each
of the four events calls `bin/knowledge-hook` with the event name and its
original arguments.

```sh
repo_root=$(git rev-parse --show-toplevel) || exit 1
"$repo_root/bin/knowledge-hook" post-commit "$@"
```

Place the call before any unconditional `exit`, and preserve the hook's exit
status, arguments, and stdin; the helper does not read stdin. Then run
`git config --local knowledge.hooks external` and `bin/setup`. Verify each
event in a disposable checkout. `bin/doctor` lists the forwarding events it
has observed, which shows past runs, not that a later edit works.

## Diagnostics

`bin/doctor` and `bin/doctor --json` report hooks, tools and versions,
collections, model locations, the last refresh, and whether inputs are
current, stale, unknown, or unavailable. They never approve environment files,
download models, or rebuild the index. A missing optional tool is a notice;
broken setup or an installed but failing tool fails with recovery steps.
Freshness is not a SQLite integrity scan. If QMD reports database errors, run
`bin/qmd-index --force` and inspect its log.
