---
description: Update an existing release tag with an AI-generated summary
argument-hint: [tag-name]
allowed-tools: Bash(git tag:*), Bash(git log:*), Bash(git describe:*), Bash(git push:*), Bash(git diff:*), Bash(git rev-parse:*)
---

Determine the target tag. If `$ARGUMENTS` is provided, use that. Otherwise default to the most recent tag:

!`git describe --tags --abbrev=0`

Find the tag immediately before the target tag to determine the range of changes it covers:

!`git tag --sort=version:refname | grep -B1 "^<target-tag>$" | head -1`

Then view the code changes between that previous tag and the target tag:

!`git diff <previous-tag>..<target-tag>`

Replace the existing tag in place at the same commit with a new annotated message:

!`git tag -f -a "<target-tag>" $(git rev-parse "<target-tag>") -m "<message>"`

Then force-push the updated tag to the remote:

!`git push origin "<target-tag>" --force`

## Message style

Summarize the code changes using language a technically savvy end user would understand. Focus on user-facing improvements, new features, and bug fixes rather than internal implementation details. Base your summary strictly on the actual code diff, not commit messages.
