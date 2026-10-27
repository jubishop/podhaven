---
name: "memory-audit-model-selection"
description: "Run memory audits locally with Claude Code, Haiku, and Claude subscription access; avoid separately billed model APIs."
type: "feedback"
---

# Memory-audit model selection

Use Haiku through the local Claude Code CLI with Claude subscription
authentication for the scheduled memory audit. Do not restore the paid
OpenRouter audit or switch to API-key billing without a new user request.

**Why:** On 2026-10-01, the user chose to replace the GitHub memory audit with
a local launchd job that used Luna through their ChatGPT subscription. This
superseded the previous DeepSeek/OpenRouter preference and its per-run dollar
budget. On 2026-10-09, the user moved the job to Claude Code with Haiku. The
Sentry Intake workflow should stay on GitHub: it uses no AI model.

**How to apply:** Keep subscription authentication explicit and retain local
reports and proposed patches for human review. Subscription usage limits still
apply. See the [scheduled memory audit workflow](../docs/development-workflow.md#scheduled-memory-audit)
for installation, operation, and failure evidence.

Evaluate audit quality through complete claim coverage, current source and
GitHub evidence, justified keep/archive decisions, valid links, and useful
consolidation. Generic coding benchmarks do not establish memory-curation
quality. Revisit the model only when audit results show a concrete need.

**Current runner:** Commit `e1407934` (Project Starter 3.2.0) moved the job onto Project Starter's shared memory-audit feature, which sets `MODEL = "claude-haiku-5-5"` in `bin/_memory_audit.py`. Issue #759 tracks that move and was still open on 2026-10-26. When the shared feature changes, keep the Haiku, subscription-authentication, and no-separately-billed-API constraints above.
