---
description: Create and push a release tag with a summary of changes
argument-hint: <tag-name>
allowed-tools: Bash(git tag:*), Bash(git log:*), Bash(git describe:*), Bash(git push:*), Bash(git diff:*), Bash(git branch:*)
---

First, determine the current branch:

!`git branch --show-current`

Then view the actual code changes to analyze:

- If on main branch: view all code changes since the most recent git tag:
  !`git diff $(git describe --tags --abbrev=0)..HEAD`

- If on any other branch: view code changes compared to main:
  !`git diff main`

Create a new annotated git tag named `$ARGUMENTS` with a message that summarizes these code changes using language a technically savvy end user would understand. Focus on user-facing improvements, new features, and bug fixes rather than internal implementation details. Base your summary strictly on the actual code diff, not commit messages.

Then push the new tag to the remote.
