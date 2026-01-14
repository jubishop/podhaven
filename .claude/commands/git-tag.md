---
description: Create and push a release tag with a summary of changes
argument-hint: <tag-name>
allowed-tools: Bash(git tag:*), Bash(git log:*), Bash(git describe:*), Bash(git push:*)
---

View the full commit messages for every change since the most recent git tag:

!`git log $(git describe --tags --abbrev=0)..HEAD --pretty=format:"%h %s%n%n%b"`

Create a new annotated git tag named `$ARGUMENTS` with a message that summarizes these changes using language a technically savvy end user would understand. Focus on user-facing improvements, new features, and bug fixes rather than internal implementation details.

Then push the new tag to the remote.
