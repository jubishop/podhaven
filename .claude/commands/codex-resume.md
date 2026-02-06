---
description: Resume a Codex conversation in Claude Code
argument-hint: [search-term]
allowed-tools: Bash(python3:*)
---

Load a Codex CLI conversation into this Claude Code session to continue the work where Codex left off. If `$ARGUMENTS` is provided, filter sessions by matching against the working directory, git branch, or first user message.

## Session Storage

Codex sessions are JSONL files at `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.

## JSONL Format Reference

Each line is `{"timestamp": "...", "type": "<type>", "payload": {...}}`.

Key event types:
- `session_meta` (always line 0): `payload.cwd`, `payload.git.branch`, `payload.git.commit_hash`, `payload.timestamp`
- `turn_context`: `payload.model`, `payload.cwd`
- `event_msg` where `payload.type == "user_message"`: the user's input in `payload.message`
- `response_item` where `payload.type == "message"` and `payload.role == "assistant"`: assistant text. `payload.phase` is `"commentary"` (thinking) or `"final_answer"`. Text in `payload.content[].text` (use `output_text` type entries).
- `response_item` where `payload.type == "function_call"`: tool invocation. `payload.name` is the tool name, `payload.arguments` is a JSON string (parse it) with a `cmd` field for shell commands.
- `response_item` where `payload.type == "function_call_output"`: tool result in `payload.output`, matched by `payload.call_id`.
- `response_item` where `payload.type == "custom_tool_call"`: non-shell tools like `apply_patch`. Tool name in `payload.name`, input in `payload.input`.
- `response_item` where `payload.type == "custom_tool_call_output"`: result of custom tool in `payload.output`.
- `compacted`: context compaction occurred. `payload.replacement_history` contains the compacted summary as an array of message objects.

Only the modern format (post-September 2025) needs to be handled. Skip any session file whose line 0 does not have `"type": "session_meta"`.

## Step 1: List Recent Sessions

Write and run a Python script that:
1. Scans `~/.codex/sessions/` recursively for `rollout-*.jsonl` files
2. Sorts by file modification time, newest first
3. For each file (check up to 50), reads only line 0 for `session_meta` (skip if missing), then scans forward to find the first `event_msg` with `payload.type == "user_message"` and the first `turn_context` for the model name
4. Skips any session that has no first user message (empty/abandoned sessions)
5. If a search term was provided via `$ARGUMENTS`, filters by case-insensitive match against cwd, branch, or first user message
6. Collects the **15** most recent matching sessions
7. Outputs a JSON array where each entry has: `path`, `timestamp` (human-readable), `cwd` (with `~` for home), `branch`, `model`, `first_message` (truncated to 100 chars), and `size_kb` (file size)

Print the results as a numbered list in **oldest-first order** (newest at the bottom, closest to the prompt) showing: index, date/time, branch, working directory, model, and first user message. Then ask the user which session to load (by number), or to refine their search.

If 4 or fewer results, use AskUserQuestion with each session as an option (label = date + branch, description = first message truncated). If more than 4, print the numbered list and let the user respond with a number.

## Step 2: Extract the Conversation

Once the user selects a session, write and run a Python script that reads the full session file and outputs a clean markdown transcript. The script should:

1. Print session metadata header (date, model, cwd, branch, commit)
2. Walk through all events and output:
   - `### User` sections for each `user_message`
   - `### Assistant` sections for `final_answer` phase assistant messages (full text)
   - `### Tool: <name>` sections showing the command/input (truncated to 300 chars)
   - Brief `> Output: ...` lines for tool outputs (truncated to 500 chars)
   - `--- context compacted ---` markers for compaction events
3. Skip: `token_count` events, `agent_reasoning` events, `turn_context` events, `commentary` phase messages, `web_search_call` events
4. If the file is over 200KB, only extract the last 100KB (skip early conversation, note that it was truncated)

## Step 3: Summarize and Resume

After reading the extracted transcript, present a concise summary to the user:

- **Goal**: What they were trying to accomplish
- **Progress**: What was done (files created/modified, features implemented, bugs fixed)
- **Current state**: Where things stand, any errors or pending work
- **Key context**: Important decisions made, constraints discovered, patterns established

Then ask what they would like to continue working on from here.
