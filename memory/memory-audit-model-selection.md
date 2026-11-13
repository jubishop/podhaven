---
name: "memory-audit-model-selection"
description: "Run memory audits locally with Claude Code and Sonnet, billed to the Anthropic API key all memory audits share, with automatic fallback to the Claude subscription."
type: "feedback"
---

# Memory-audit model selection

Use Sonnet (`claude-sonnet-5-5`, high effort) through the local Claude Code
CLI for the scheduled memory audit, billed to the Anthropic API key that
every Project Starter memory audit on this Mac shares. The runner falls back to the Claude subscription when the key runs out
of credit, reaches its spend limit, or is rejected. Do not restore the paid
OpenRouter audit.

**Why:** On 2026-10-01, the user chose to replace the GitHub memory audit with
a local launchd job that used Luna through their ChatGPT subscription. This
superseded the previous DeepSeek/OpenRouter preference and its per-run dollar
budget. On 2026-10-09, the user moved the job to Claude Code with Haiku. On
2026-10-28, the user moved it to a PodHaven-only Anthropic API key, to spend
the $200 of API credit their Max plan includes each month, which expires if
unused; that superseded subscription-only billing. They chose Sonnet for
better audits. On 2026-11-13, the user moved every Project Starter memory
audit, PodHaven's and Screenr's included, onto one shared key, so there is one
key to rotate and one in the Console instead of one per project
([jubishop/project-starter#52](https://github.com/jubishop/project-starter/issues/52));
that superseded the PodHaven-only key. The Sentry Intake workflow should stay
on GitHub: it uses no AI model.

**How to apply:** The key is `ANTHROPIC_MEMORY_AUDIT_API_KEY` in `~/.env`,
shared with every other project's audit on this Mac. Keep that name out of
PodHaven's `.env`: a line there, even an empty one, overrides the shared key.
Retain local reports and proposed patches for human review.
`.cache/memory-audit/latest.json` shows the `credential` and `keyFile` each
run used and any `fallback`. See the [scheduled memory audit workflow](../docs/development-workflow.md#scheduled-memory-audit)
for installation, operation, and failure evidence.

Evaluate audit quality through complete claim coverage, current source and
GitHub evidence, justified keep/archive decisions, valid links, and useful
consolidation. Generic coding benchmarks do not establish memory-curation
quality. Revisit the model only when audit results show a concrete need.

**Current runner:** Commit `e1407934` (Project Starter 3.2.0) moved the job onto Project Starter's shared memory-audit feature, and Project Starter 3.3.0 set `MODEL = "claude-sonnet-5-5"` in `bin/_memory_audit.py` with the API key and fallback. Issue #759 tracked that move and closed as completed on 2026-10-25. Project Starter 3.12.0 renamed the key `ANTHROPIC_MEMORY_AUDIT_API_KEY` and reads it from `~/.env` when the checkout's `.env` has no line for it. When the shared feature changes, keep Sonnet, the shared key, and the subscription fallback above.
