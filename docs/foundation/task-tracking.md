---
status: current
---

# Task tracking with td

Use [td](https://github.com/marcus/td) to keep unfinished work resumable
across agent sessions. Shared scope and acceptance criteria stay in the
project's issue tracker; link the issue from the task. Durable lessons belong
in `memory/`, and decisions in `docs/`.

## When to use a task

Create or reuse a task for work with multiple stages, likely interruptions,
blockers, or handoffs, and for anything left unfinished when a session ends.
Straightforward work finished in one session, read-only questions, small
edits, and filing a single issue need no task. Carry one task through
implementation, verification, and delivery of the same outcome. Split only
distinct or independently resumable outcomes, and link real prerequisites. Do
not mirror the backlog or create a task per command.

## Install and initialize

Install upstream td from its Homebrew tap; other platforms use an official
release binary. Project Starter 2.0.0 was verified with td 0.66.0.

```sh
brew install marcus/tap/td
td version
```

Initialize once per clone, from the primary checkout's root:

```sh
td init
td list
git check-ignore .todos/issues.db
```

`.todos/` must stay ignored. Setup, CI, and application startup never install
td or create task databases. If td is missing or fails, report it and repair
the setup before relying on task state.

## Start or resume work

Run `td usage --new-session -q` once per new agent context, and `td usage -q`
for later refreshes. Never rotate sessions to bypass review checks. Before
substantive work, read the relevant task's handoff and recent logs with
`td list` and `td show <id>`, then check them against the current checkout and
external state: task records are observations, not proof that a branch, check,
or deployment is still current.

```sh
td create "Describe the intended outcome"
td start <id>
td log "Meaningful checkpoint and its verification evidence"
```

Log results, blockers (`td log --blocker "..."` and `td block <id>`), and
changes of direction. Link commits and evidence instead of copying them, and
do not narrate every command. `td status` shows current work, and
`td monitor` opens a live dashboard.

## Keep the handoff current

Update the handoff when its summary or next steps become outdated, and before
stopping with unfinished work or handing it over:

```sh
td handoff <id> \
  --done "Completed work and verification evidence" \
  --remaining "Next concrete actions" \
  --decision "Relevant choice and reason" \
  --uncertain "Open question or unverified assumption"
```

Separate verified results from assumptions. Include the branch or worktree,
evidence locations, and a resume command when they matter, and omit empty
fields.

## Finish and record review

Complete the repository's required checks and review, log the final result
and any separate follow-up, then run `td review <id>` and `td approve`. Reuse
checks and review already done for unchanged inputs; statuses add no extra
gate. An independent reviewer runs `td approve <id> --reason "..."`, and a
real self-review uses `td approve <id> --self-review --reason "..."`. Add
`--reviewed-by "<who>"` only for a review that actually happened, and honor
stricter project review rules.

Use `td close` only for duplicates, cancellations, and other administrative
closure. Task status never grants permission to merge, deploy, publish, or
contact people.

## Worktrees and local data

Linked worktrees share the primary checkout's database; confirm that
`td list` matches there, and use `td --work-dir /path/to/primary-checkout`
for an explicit target. Never copy `.todos/`. Separate clones and machines
have separate state unless td synchronization is configured deliberately, and
Git does not carry it. Export with `td export --all --output <path>` to a
location outside the repository, and read `td import --help` before
importing. Keep task records and exports out of commits and knowledge indexes.
