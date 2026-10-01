---
status: current
---

# Local task tracking with td

Use `td` to preserve unfinished work across agent sessions. A useful task saves
repeated investigation, makes an unfinished obligation visible, or lets another
agent resume without asking the user to explain the work again.

Keep shared scope and acceptance criteria in the project's existing issue
tracker. Link the relevant issue URL from the local task instead of copying
the full backlog. Durable lessons belong in `memory/`; accepted designs and
decisions belong in `docs/`.

## When to use a task

Use a task for work with multiple stages, likely interruptions, blockers, or
handoffs between agents. Preserve work that is unfinished when a session ends,
even if it started as a small request. Make tasks optional for straightforward
work completed in one session. Read-only questions, small edits, and filing a
single GitHub issue do not need a task just to record that they happened.

Read and reuse a relevant existing task before creating another. Continue its
record through implementation, verification, and delivery when these serve the
same outcome. Create separate tasks only for distinct outcomes or independently
resumable work; link real prerequisites. Do not create a second backlog or a
task for each workflow command.

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

Before substantive work, inspect the existing tasks. Read the relevant task's
handoff and recent logs, then check them against the current checkout and any
external state the next action depends on. Task records describe observations;
they do not establish that a branch, check result, or deployment is still current.

```sh
td list
td show <id>
```

Reuse that task if it covers the outcome. Otherwise, create one only when the
work meets the criteria above. Use the ID printed by `td create` in subsequent
commands; `<id>` is a placeholder.

```sh
td create "Describe the intended outcome"
td start <id>
td log "Record a meaningful checkpoint and its verification evidence"
```

Record the related issue URL and scope in the task description when applicable.
Use `td log --blocker "..."` and `td block <id>` when work cannot continue.
Log meaningful results, blockers, and changes of direction. Link commits, check
results, or evidence paths rather than repeating their full contents. Do not
narrate every command or duplicate the conversation. `td status` shows current
work; `td monitor` opens the live terminal dashboard.

## Keep the handoff current

Update the handoff when a material change makes its summary or next steps
outdated, and before stopping with unfinished work or transferring it to another
agent. New log entries do not replace an accurate handoff. Keep one concise
snapshot that lets the next agent resume without reconstructing the full log:

```sh
td handoff <id> \
  --done "Completed work and verification evidence" \
  --remaining "Next concrete actions" \
  --decision "Relevant choice and reason" \
  --uncertain "Open question or unverified assumption"
```

Distinguish verified results from assumptions. Include the relevant branch or
worktree, evidence locations, and a resume command when these matter. Replace
obsolete next steps and omit fields that have no useful content.

## Finish and record review

Complete the repository's required checks and review. Record a concise final
result and any separately tracked follow-up, then use `td review <id>` followed
by `td approve` for completed work. Reuse checks and review already performed
for this delivery while their inputs remain unchanged; td does not require an
additional review pass just to move a task through its statuses.

An independent reviewer can run `td approve <id> --reason "..."`. In the
default trusted mode, a real self-review can be recorded with
`td approve <id> --self-review --reason "..."`. When recording another person's
or agent's review, use `--reviewed-by "<who>"` only if they actually reviewed
the work. State the actual review evidence; an approval status is not evidence
by itself. Honor a stricter project review policy when configured.

Reserve `td close` for duplicates, canceled work, or other administrative
closure. Task status does not grant permission to merge, deploy, publish, or
contact other people.

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
