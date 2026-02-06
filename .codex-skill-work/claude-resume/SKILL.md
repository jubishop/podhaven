---
name: claude-resume
description: Import and resume Claude Code conversations inside Codex. Use when a user asks to continue work from a prior Claude session, inspect Claude conversation history, or load Claude context into the current Codex chat.
---

# Claude Resume

Use this skill to discover conversations from Claude Code local storage and create a resume packet for Codex.

Claude Code stores per-project conversations as JSONL files under `~/.claude/projects/*/*.jsonl`. The helper script in this skill parses those files and builds a markdown transcript packet.

## Workflow

1. List candidate conversations:
   - `skills/claude-resume/scripts/claude_resume.py list --cwd-contains <path-fragment> --query "<terms>"`
   - Default list size is 15 results unless `--limit` is provided.
   - If the user invokes `$claude-resume` with trailing text (for example `$claude-resume podcast tags`), treat trailing text as query terms and filter to the current repo via `--cwd-contains`.
2. Ask the user which index to import if they did not specify one.
3. Export a resume packet:
   - `skills/claude-resume/scripts/claude_resume.py export --index <n> --cwd-contains <path-fragment> --query "<terms>" --messages 60 --output /tmp/claude-resume.md`
4. Load the packet into context by reading it:
   - `cat /tmp/claude-resume.md`
5. Continue the user task in Codex using the imported context.

## Commands

- List sessions as table:
  - `skills/claude-resume/scripts/claude_resume.py list`
- List sessions filtered by query terms:
  - `skills/claude-resume/scripts/claude_resume.py list --cwd-contains podhaven --query "podcast tags"`
- List sessions as JSON:
  - `skills/claude-resume/scripts/claude_resume.py list --json`
- Export by list index:
  - `skills/claude-resume/scripts/claude_resume.py export --index 3 --messages 80`
- Export by session ID:
  - `skills/claude-resume/scripts/claude_resume.py export --session-id <uuid>`
- Interactive pick:
  - `skills/claude-resume/scripts/claude_resume.py pick --messages 80 --output /tmp/claude-resume.md`

## Notes

- Default search path is `~/.claude/projects`; override with `--projects-dir` if needed.
- `--query` is case-insensitive and matches all space-separated terms.
- Include Claude thinking blocks only if requested via `--include-thinking`.
- Keep `--messages` bounded to avoid flooding context.
