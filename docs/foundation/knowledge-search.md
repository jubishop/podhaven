---
status: current
---

# Knowledge search

Projects keep knowledge as Markdown in `memory/` and `docs/` and search it,
along with the root `README.md`, with
[QMD](https://github.com/tobi/qmd). Each checkout has its own index, and Git
hooks refresh it in the background.

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
`.config/qmd/index.yml`. A collection's pattern is `**/*.md`, for every
Markdown page under its directory, or one Markdown file name, for that file
alone; a missing file indexes nothing until it returns. The `readme` collection uses `README.md` in the checkout root, so
search returns `qmd://readme/README.md` without indexing other root-level or
nested pages. Each QMD command receives a temporary copy of the generated
configuration, so QMD can rewrite that copy without affecting freshness
checks.

## Required tools

This project runs on the Mac that the home repository sets up, which
installs QMD, direnv, ShellCheck, and Python, so a missing tool means that
setup broke; restore the tool through it rather than work around it. Without
QMD, `bin/setup`, every refresh and lookup, and `bin/doctor` fail. In a
checkout with an `.envrc`, `bin/setup`, `bin/prep-worktree`, and `bin/doctor`
fail without direnv. `bin/doctor` also fails without ShellCheck, which
`bin/check` runs.

## Search failures

When configured QMD fails, follow `~/AGENTS.md` for a failed knowledge
search. To repair it, run `bin/doctor`, inspect `.cache/qmd/index.log`, and
attempt a focused repair. Confirm recovery by repeating the failed lookup
successfully; never report success from a command that failed, timed out, or
discarded results.

A successful search with no matches is not a failure.

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
bursts of requests, and runs again when files change mid-refresh. When inputs
change, it runs QMD's `update`, `embed`, and `cleanup`, so each successful
refresh leaves no embedding chunks for replaced or removed pages, and cleanup
also repacks partly empty vector storage. QMD keeps a collection's pages and
vectors after the configuration drops it, so when a collection leaves
`.config/knowledge.json`, renamed ones included, the refresh deletes the
index and rebuilds it. Lookups during cleanup wait or refuse, as during the
rest of a refresh. Avoid direct `qmd update`, `qmd embed`, and `qmd cleanup`,
which bypass this coordination. Logs rotate at about 1 MB and keep one
previous file.

## Worktrees and models

The `post-checkout` hook prepares a new worktree when Git creates it, and
`bin/prep-worktree` repeats that preparation. Both run the project's
executable `bin/setup-application`, when present, so a new worktree gets its
dependencies, such as a `.venv`; a failure in a new worktree is reported
without stopping Git. Each checkout keeps its own `.cache/qmd/index.sqlite`.
Every project shares model files at `~/.cache/qmd/models`, independent of
`XDG_CACHE_HOME`, through each checkout's `.cache/qmd/models` link. Setup
creates or repairs that link, and stops without deleting anything when a
folder or file holds its place; move what it holds into the shared folder,
remove it, and run setup again. Never delete the shared model directory while
cleaning up a checkout.

A worktree's `.envrc` is approved automatically only when it matches a primary
checkout file that direnv already allows. After moving a checkout, repair the
worktree, run `bin/doctor`, and rerun `bin/prep-worktree`.

## Existing hooks

Setup does not replace an active `core.hooksPath` or executable hooks in the
default hooks directory. Integrate through the existing manager instead: each
of the four refresh events and `pre-push` calls `bin/knowledge-hook` with the
event name and its original arguments.

```sh
repo_root=$(git rev-parse --show-toplevel) || exit 1
"$repo_root/bin/knowledge-hook" post-commit "$@"
```

Place the call before any unconditional `exit`, and preserve the hook's exit
status, arguments, and stdin. The helper reads stdin only for `pre-push`,
which runs the
[pre-push document checks](engineering-policy.md#pre-push-hook): pass it the
hook's stdin, saving a copy first if the hook reads stdin too, and exit
nonzero when the helper does, so Git refuses the push. Then run
`git config --local knowledge.hooks external` and `bin/setup`. Verify each
event in a disposable checkout. `bin/doctor` lists the forwarding events it
has observed, which shows past runs, not that a later edit works.

## Shared hooks

A clone's checkouts share its Git configuration, `core.hooksPath` included.
When that setting names one checkout's `bin/hooks`, such as the primary
checkout's by absolute path, Git runs those hook files in every checkout, and
each one calls the `bin/knowledge-hook` of the checkout it runs in. Setup and
`bin/doctor` accept that path in a checkout of the same clone whose own
`bin/hooks` holds the same files, and setup leaves it unchanged. When a hook
there differs or is missing, `bin/doctor` names the event and setup stops.
Bring whichever checkout is behind to the default branch rather than
repointing `core.hooksPath`, which would change the hooks of every checkout.
A `bin/hooks` outside the clone's checkouts counts as
[existing hooks](#existing-hooks).

## Diagnostics

`bin/doctor` and `bin/doctor --json` report hooks, tools and versions,
collections, model locations, the last refresh, and whether inputs are
current, stale, or unknown. They never approve environment files, download
models, or rebuild the index. A missing [required tool](#required-tools),
broken setup, or an installed but failing tool fails with recovery steps.
Freshness is not a SQLite integrity scan. If QMD reports database errors, run
`bin/qmd-index --force` and inspect its log.
