---
status: current
---

# Memory audit

A weekly local job checks every active [memory](../../memory/README.md) note
against the code and GitHub evidence, archives or updates stale notes, and
commits validated changes to `main`. It is an optional Project Starter
feature: `bin/sync --enable memory-audit` installs `bin/memory-audit`, its
runner and prompt, and this page, and `--disable memory-audit` removes them.
It needs macOS, a GitHub repository as `origin`, and a `main` branch.

## Install

Run `bin/memory-audit install` in the primary checkout to register the weekly
launchd job; it does not run an audit. The job runs at the
[scheduled](#settings) time in the Mac's local time zone, Saturday at 06:00 by
default for every project; their runs [take turns](#taking-turns). A sleeping Mac runs a missed calendar job after wake; the user must
be logged in. The LaunchAgent is
`~/Library/LaunchAgents/<launchAgentLabel>.plist`.

The job starts uv's default `~/.local/bin/python3` through `/bin/sh`, so it
follows Python updates; the installer refuses until
`uv python install --default` has created that interpreter. Tools under an
fnm Node version are scheduled through fnm's default alias, so Node updates
need no reinstall. The installer requires `claude`, `qmd`, `gh`, `git`, `rg`,
and `jq`, and checks that QMD starts with the scheduled `PATH`. Reinstall
after changing the schedule or label, moving the checkout, or changing other
tool locations.

## Settings

An optional `memoryAudit` object in `.config/knowledge.json` holds this
project's settings. `bin/memory-audit settings` prints them with their
defaults filled in, and every command rejects an unknown or invalid setting.

```json
"memoryAudit": {
  "schedule": {"weekday": "Saturday", "hour": 8, "minute": 0},
  "issueLabels": ["bug", "area: tooling"],
  "commitTrailers": {"Deploy": "skip"}
}
```

| Setting | Default | Meaning |
| --- | --- | --- |
| `repository` | `OWNER/NAME` from a github.com `origin` | Where issues, PRs, and the failure issue live. |
| `launchAgentLabel` | `com.<owner>.<name>.memory-audit`, lowercase | The LaunchAgent's label and plist name. |
| `schedule` | `{"weekday": "Saturday", "hour": 6, "minute": 0}` | Weekly start time; any key may be omitted. |
| `issueLabels` | `[]` | Existing labels for a new failure issue. |
| `commitTrailers` | `{}` | Trailers for the audit's commit, such as a deployment skip. |
| `indexHeading` | `Active pages` | The level-two heading in `memory/README.md` over the active-note list. |
| `context` | none | Project context added to the prompt. |
| `lockWaitMinutes` | `180` | How long a run waits for its turn before failing. |

## Taking turns

Audits of different projects on the same Mac run one after another, so they
can share a start time. Each run computes the same per-user lock,
`~/.cache/project-starter/memory-audit.lock`, and waits for it before it
fetches evidence; `latest.json` shows `waiting` meanwhile. The 90-minute model
limit starts only after the run's turn begins. A run that waits longer than
`lockWaitMinutes` fails and reports like any other failure, and the next
scheduled run tries again. A second run of the same project, such as a manual
run during a scheduled one, still skips at once through the project's own
lock.

## Model and evidence

The job runs `claude -p` with `claude-sonnet-5-5` and high effort. It bills
the project's own [API key](#api-key) when one is set, and otherwise the saved
Claude subscription login, whose limits apply. It refuses third-party provider
logins and keeps every other API key out of Claude's environment.
Restricted mode ignores user and project Claude settings and instruction
files, so personal permissions, MCP servers, and hooks do not join the audit.
Claude gets only Bash, Read, Glob, and Grep, and no session is saved. Writes,
network commands, and reads outside the clone need approval, which the job
denies automatically. Beyond Claude Code's built-in read-only commands, only
`jq` and `qmd search` are allowed. Claude runs with
`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, so its tools never receive Anthropic
credentials or other secret-named variables; see [API key](#api-key).

Each run fetches `origin/main` and audits that exact revision in a disposable
clone at `.cache/memory-audit/repository`, so uncommitted work is neither
audited nor touched. Every run reuses that path, replacing any clone an
interrupted run left. Claude Code can record the folder it works in as a
project in `~/.claude.json`, as it does when the project tracks
`.claude/settings.local.json`, and nothing prunes those entries. It also keeps
large tool output under `~/.claude/projects/` until its `cleanupPeriodDays`
sweep, 30 days by default, removes it. One path keeps both to one entry and
one folder per project instead of one per run.

Before the model starts, the runner writes
`artifacts/memory-audit-context.json` in the clone: GitHub issues and PRs from
two bounded lists of up to 1,000 entries each, and the commits since the last
successful audit, or the last seven days on the first run. It also builds a
keyword-only QMD index of the clone's shared collections from
`.config/knowledge.json`, never personal home memory, through the clone's own
`bin/_knowledge.py`. The model makes no network requests or QMD model
downloads.

Unchanged repository, GitHub, and audit inputs skip the model call, except
right after a failed or interrupted run; `--force` always audits. A project
without active notes skips the model too. Model attempts share a 90-minute
limit.

## API key

Each project can bill its audits to its own Anthropic API key instead of the
subscription. Put the key in `.env` at the root of the checkout the job runs
from, the primary checkout:

```sh
MEMORY_AUDIT_ANTHROPIC_API_KEY=sk-ant-api03-...
```

Project Starter's `.gitignore` block ignores `.env`; make it private with
`chmod 600 .env`. The runner reads only that line, quoted or not and with or
without `export`, at the start of each run, so adding, changing, or removing
the key needs no reinstall. No `.env`, no line, or an empty value uses the
subscription. Nothing else sets the key: the variable in the shell or in
`~/.env`, and any `ANTHROPIC_API_KEY`, are ignored. The distinct name keeps
other Anthropic clients from picking up the key. The runner passes it to
Claude as `ANTHROPIC_API_KEY` for the API-key attempt only, after
`claude auth status` confirms that Claude Code will bill it as a first-party
key.

The model never sees the key. Reading `.env` needs approval, which the job
denies. Claude Code otherwise passes its environment to Bash, and the allowed
`jq` could print it with its `env` builtin. So every model attempt runs in
Claude Code's subprocess scrub mode, which bills the key but withholds
`ANTHROPIC_API_KEY` and other secret-named variables from every tool process.
Scrub mode keeps the job's manual permission mode. It also withholds
`XDG_CACHE_HOME`, so the runner names the clone's search index with
`INDEX_PATH`; otherwise `qmd search` would read the user's own index. Each
run first [checks](#tool-boundary-check) that the installed Claude Code still
behaves this way.

When the API refuses the key, the runner reruns that model attempt on the
subscription with no manual step, and the rest of the run stays there. The
rerun shares the attempt's 90-minute limit. These refusals fall back, each
recorded as the fallback's `trigger`:

| Trigger | API response |
| --- | --- |
| `credit-balance` | HTTP 400, "Your credit balance is too low to access the Anthropic API", which Claude Code shortens to "Credit balance is too low". |
| `usage-limit` | HTTP 400, "You have reached your specified API usage limits": the organization's spend limit. |
| `key-rejected` | HTTP 401 or 403: an invalid, revoked, or disabled key. |

Only Claude Code's API error events count, never the model's own text. Any
other failure, such as a rate limit or an outage, fails the run as before, and
so does a fallback without a subscription login. `latest.json` and the run's
`run-meta.json` record the `credential` that ran the model, `api-key` or
`subscription`, and after a fallback a `fallback` object with its `trigger`,
HTTP `status`, and API `message`. The refused attempt's logs stay in the run
folder as `api-key-events.jsonl` and `api-key-claude.log`.

## Tool boundary check

What the model's tools can reach depends on Claude Code behavior that can
change in any release, such as scrub mode, what the `jq` and `qmd search`
allow rules cover, and which variables reach tools. So before every model
run, the runner checks the installed Claude Code with its own model-run and
search setup and the audit's flags. A local stand-in for the Anthropic API
scripts the tool calls, so the check makes no model request, costs nothing,
and takes a few seconds. It runs in a scratch repository under
`.cache/memory-audit/boundary/`, a path that every run reuses like the
clone's, with one note, a bogus `ANTHROPIC_API_KEY`, and two canary
variables, `AUDIT_CANARY` and the secret-named `AUDIT_CANARY_API_KEY`, and
requires that:

- `jq` reads `null` for `ANTHROPIC_API_KEY` and `AUDIT_CANARY_API_KEY`,
  through both `env` and `$ENV`.
- `jq` reads `artifacts/memory-audit-context.json`.
- `qmd search` finds the scratch note in its own index, not the user's.
- `printenv`, `env`, `ps eww`, and `ps -E` are denied, and so are Read, Grep,
  and `cat` of a file outside the repository and Glob in a folder outside it.
- The `jq` and `qmd search` allow rules cover neither a file outside the
  repository, as in `jq -R . ../outside.txt` and
  `jq --rawfile f ../outside.txt -n '$f'`, nor a command chained after them,
  as in `jq -n 1; cat ../outside.txt` and `qmd search … && printenv`.
- No tool output holds the key, either canary, or that outside file.

A breach fails the run before the model starts, so the real key never reaches
a tool. The failure reports like any other, naming Claude Code's version and
each broken requirement, and the run folder keeps the check's logs in
`boundary/`. Fix it in Project Starter's runner and sync the release; the
next run checks again.

## Validation

The model returns one finding per active note and the complete proposed
content of each note it changes. The runner accepts the proposal only when:

- Every active note has exactly one finding with evidence, and the report has
  its required sections and reviewed count.
- Changes only update existing active notes or move them into
  `memory/archive/`, without overwriting an archive.
- The session log shows the model read every active note with the Read tool
  and made at least one source or evidence lookup per note. On 2026-10-10 an
  audit kept all 16 of a project's notes in 32 seconds without reading any.
- Project Starter's metadata, index-coverage, and local-link checks pass on
  the proposed tree.

The model cannot edit `memory/README.md`, archives, ledgers in `memory/`
folders, docs, or code. When it archives a note, the runner removes that
note's entry from the README's `indexHeading` list before validation; updates
leave the README untouched. An archive that would break a link from an
existing archive, a doc, or README text outside the list fails validation, so
that note stays active. After a rejected proposal, the runner restores the
original notes and README and gives Claude one repair attempt with the exact
error. A second rejection fails the run. Both attempts' logs are kept.

## Publishing and failures

When the checks pass and notes changed, the runner commits the change in the
clone with the checkout's Git identity, adds the `commitTrailers`, and pushes
it to `main` on every push URL of `origin`. Git hooks stay off in the clone;
none gates a memory-only commit. If `main` moved during the audit, the commit
is rebased onto it, unless the move changed `memory/`; then the run fails and
the next run audits the new notes. The local checkout is never touched; pull
to see the change.

A failed run shows a macOS notification and opens a GitHub issue titled
`Memory audit failing` with the `issueLabels`, or comments on the open one,
with the error and the run's folder name. If the labels cannot be applied,
the issue opens without them and says why. Invalid settings fail the run with
only the notification. The next successful run closes the issue. A run that
changes nothing stays silent.

## Run and inspect

```sh
bin/memory-audit run
bin/memory-audit run --force
bin/memory-audit settings
cat .cache/memory-audit/latest.json
launchctl print gui/$(id -u)/<launchAgentLabel>
```

`latest.json` records the latest success, failure, or skip, its run folder,
the [credential](#api-key) and any fallback, and any `publishedCommit`. A failure never updates `last-success.json`. Each
run folder keeps `run-meta.json` and the context; the
[tool boundary check](#tool-boundary-check) adds `boundary/`, model attempts add
`events.jsonl`, `claude.log`, and the structured result, and successful runs
add `memory-audit-report.md` and `memory-audit.patch`. The clone and the
boundary check's scratch repository are deleted when the run ends. Run
folders stay local and ignored by Git. Each run deletes run folders older than
60 days, except those the state files name.

## Stop

Run `launchctl bootout gui/$(id -u)/<launchAgentLabel>` and delete the plist
so it does not load at the next login. Do that before
`bin/sync --disable memory-audit`, which removes the runner the job starts.
