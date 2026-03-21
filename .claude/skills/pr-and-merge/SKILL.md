---
description: Commit, push, create a PR, watch CI, and merge if green
allowed-tools: Bash(git:*), Bash(gh:*)
disable-model-invocation: true
---

Commit any outstanding changes, open a pull request, monitor CI, and merge when green. Track whether we started on a custom branch or created one — this determines cleanup behavior at the end.

## Step 1 — Determine branch

Run `git branch --show-current` to get the current branch name.

- **If the branch is `main`**: create a new branch with a descriptive name based on the staged/unstaged changes (use `git diff --stat` and `git status` to inform the name). Use kebab-case. Check it out.
  - Set a flag: `CREATED_BRANCH=true`
- **If the branch is anything other than `main`**: use it as-is.
  - Set a flag: `CREATED_BRANCH=false`

## Step 2 — Commit and push

1. Run `git status` and `git diff` to see what needs to be committed.
2. If there are uncommitted changes (staged or unstaged, including untracked files):
   - Stage the relevant files (`git add` — prefer naming specific files over `git add .`).
   - Create a commit with a concise, descriptive message. End the commit message with:
     ```
     Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
     ```
     Use a HEREDOC for the message to preserve formatting.
3. If there are no changes to commit, that's fine — continue.
4. Push the branch to origin: `git push -u origin HEAD`.

## Step 3 — Create a PR

Use `gh pr create` to open a pull request against `main`.

- Keep the title short (under 70 characters).
- Write a body with a `## Summary` section (1–3 bullet points) and a `## Test plan` section.
- End the body with: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
- Use a HEREDOC for the body.
- If a PR already exists for this branch, skip creation and use the existing PR. Detect this by checking `gh pr view --json number` first — if it succeeds, a PR already exists.

## Step 4 — Watch CI

Wait for all CI checks on the PR to finish. Use `gh` commands to monitor the runs (e.g. `gh pr checks`, `gh run watch --exit-status`, etc.). Stop early if any check fails.

## Step 5 — Act on results

### All checks passed

**If `CREATED_BRANCH` is true**:

1. Merge the PR: `gh pr merge <PR_NUMBER> --squash --delete-branch`
2. `git checkout main`
3. `git pull origin main`
4. Report success: the PR was merged, branch cleaned up, and `main` is up to date.

**If `CREATED_BRANCH` is false**:

1. Merge the PR: `gh pr merge <PR_NUMBER> --squash` (no `--delete-branch` — keep the branch intact)
2. Do NOT delete the branch or switch branches.
3. Report success: the PR was merged and the current branch is still checked out.

### Any check failed

1. Report which checks failed and their output/logs if available (use `gh pr checks <PR_NUMBER>` to show the status table).
2. Do NOT merge. Do NOT delete the branch.
3. Stop and await further instructions from the user.

## Rules

- Never force-push.
- Never skip pre-commit hooks (`--no-verify`).
- Never commit files that look like secrets (`.env`, credentials, tokens).
- If any step fails unexpectedly, stop and report the error rather than retrying blindly.
