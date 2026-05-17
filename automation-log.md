# Automation log

Append-only telemetry from scheduled routines. One line per run, including no-ops.

Format: `## [YYYY-MM-DD HH:MM UTC] <routine-id> | scanned=N changed=M | <one-line detail>`

Routine IDs: `daily-lint`, `cross-link-pass`, `knowledge-writer`, `status-sync`.

`<one-line detail>` should include any "considered but rejected" reasoning when applicable — the cases where the agent almost did something. That's where bad heuristics get caught early.

---
