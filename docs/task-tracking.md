---
status: current
---

# Local task tracking with td

Use `td` for local work items, progress, blockers, and handoffs between agent
sessions. Keep shared scope and acceptance criteria in the project's existing
issue tracker. Link the relevant issue URL from the local task instead of
copying the full backlog. Durable lessons belong in `memory/`; accepted designs
and decisions belong in `docs/`.

## Install and initialize

Install `td` using its [official instructions](https://github.com/marcus/td#installation).
On macOS:

```sh
brew install marcus/tap/td
td version
```

On other supported platforms, use an official release binary or the documented
Go installation. The commands below were verified with td 0.65.0.

Run this once from the primary checkout's root, including after a fresh clone:

```sh
td init
td list
git check-ignore .todos/issues.db
```

Initialization creates the local `.todos/` database and preserves an existing
one. Keep `.todos/` ignored by Git. Install and initialize explicitly; application
startup, CI, and knowledge setup do not install td or create task databases.
If the command is missing or fails, report the problem and repair the setup
before relying on stored task state.

## Start or resume work

At the start of each new agent context, run this once from the repository:

```sh
td usage --new-session -q
```

Use `td usage` for full workflow guidance and `td <command> --help` for command
details. Use `td usage -q` for later refreshes in the same context. Do not rotate
sessions during work to bypass review checks.

For substantive work, find and reuse the existing local task or create one
with a concrete outcome. Small one-step edits and read-only questions do not
need artificial task records. Use the ID printed by `td create` in subsequent
commands; `<id>` below is a placeholder.

```sh
td list
td create "Describe the intended outcome"
td start <id>
td log "Record verified progress and relevant check results"
```

Record the related issue URL and scope in the task description when applicable.
Use `td log --blocker "..."` and `td block <id>` when work cannot continue.
Use dependencies for real prerequisites. `td status` shows current work;
`td monitor` opens the live terminal dashboard.

## Hand off and finish

Before stopping with unfinished work, record enough context to resume:

```sh
td handoff <id> \
  --done "Completed work and verification evidence" \
  --remaining "Next concrete actions" \
  --decision "Relevant choice and reason" \
  --uncertain "Open question or unverified assumption"
```

Keep entries concise and distinguish verified results from assumptions. Omit
fields that have no useful content. Record a final handoff before submitting
completed work with `td review <id>`.

Complete the repository's checks and review requirements before approval.
An independent reviewer can run `td approve <id> --reason "..."`. In the
default trusted mode, a real self-review can be recorded with
`td approve <id> --self-review --reason "..."`. When recording another person's
or agent's review, use `--reviewed-by "<who>"` only if they actually reviewed
the work. Honor a stricter project review policy when configured.

Use `td review` followed by `td approve` for completed work. Reserve `td close`
for duplicates, canceled work, or other administrative closure. Task status
does not grant permission to merge, deploy, publish, or contact other people.

## Worktrees and local data

Linked Git worktrees use the primary checkout's td database. Initialize the
primary checkout first and confirm `td list` shows the same tasks in a linked
worktree. Do not copy `.todos/` into each worktree. For an explicit target,
use `td --work-dir /path/to/primary-checkout list`.

Separate clones and machines have separate state unless td synchronization
is configured deliberately. Git commits and pushes do not back up `.todos/`.
For a portable task export, use `td export --all --output <backup-path>` with a
destination outside the repository. Consult `td import --help` before importing.
Keep local task records and exports out of commits and knowledge indexes.
