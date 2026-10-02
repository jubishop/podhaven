---
name: "memory-audit-model-selection"
description: "Run memory audits locally with Luna and ChatGPT subscription access; avoid separately billed model APIs."
type: "feedback"
---

# Memory-audit model selection

Use Luna through the local Codex CLI with ChatGPT subscription authentication
for the scheduled memory audit. Do not restore the paid OpenRouter audit or
switch to API-key billing without a new user request.

**Why:** On 2026-10-01, the user chose to replace the GitHub memory audit with
a local launchd job that uses their ChatGPT subscription. This supersedes the
previous DeepSeek/OpenRouter preference and its per-run dollar budget. The
Sentry Feedback workflow should stay on GitHub: it uses no AI model.

**How to apply:** Keep subscription authentication explicit and retain local
reports and proposed patches for human review. Subscription usage limits and
purchased credits still apply. See the [scheduled memory audit workflow](../docs/development-workflow.md#scheduled-memory-audit)
for installation, operation, and failure evidence.

Evaluate audit quality through complete claim coverage, current source and
GitHub evidence, justified keep/archive decisions, valid links, and useful
consolidation. Generic coding benchmarks do not establish memory-curation
quality. Revisit the model only when audit results show a concrete need.
