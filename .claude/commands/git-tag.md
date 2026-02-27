---
description: Update an existing release tag with an AI-generated summary
argument-hint: [tag-name]
allowed-tools: Bash(git tag:*), Bash(git log:*), Bash(git describe:*), Bash(git push:*), Bash(git diff:*), Bash(git rev-parse:*)
---

## Step 1 — Determine the target tag

If `$ARGUMENTS` is provided, use that as the target tag. Otherwise find the most recent tag:

!`git describe --tags --abbrev=0`

## Step 2 — Find the previous tag

Run `git tag --sort=version:refname` and find the tag immediately before the target tag.

## Step 3 — Diff the changes

Run `git diff <previous-tag>..<target-tag>` (substituting the real tag names).

## Step 4 — Rewrite the tag message

Replace the existing tag in place at the same commit with a new annotated message:

`git tag -f -a "<target-tag>" $(git rev-parse "<target-tag>") -m "<message>"`

Then force-push the updated tag to the remote:

`git push origin "<target-tag>" --force`

## Message style

Summarize the code changes using language a technically savvy end user would understand. Focus on user-facing improvements, new features, and bug fixes rather than internal implementation details. Base your summary strictly on the actual code diff, not commit messages.
