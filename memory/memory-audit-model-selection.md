---
name: "memory-audit-model-selection"
description: "Run memory audits locally with Claude Code and Sonnet, billed to the Anthropic API key all memory audits share, with automatic fallback to the Claude subscription."
type: "feedback"
---

# Memory-audit model selection

Use Sonnet (`claude-sonnet-5-5`, high effort) through the local Claude Code
CLI for the scheduled memory audit, billed to the Anthropic API key that
every adopter's memory-note audit on this Mac shares. The audit falls back to
the Claude subscription when the API refuses the key for spend, out of credit
or at its limit. Do not restore the paid OpenRouter audit.

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
shared with every other adopter's memory-note audit on this Mac. Keep that
name out of PodHaven's `.env`: a line there, even an empty one, overrides the
shared key. See the [scheduled memory audit workflow](../docs/development-workflow.md#scheduled-memory-audit)
and `~/docs/guidance-review.md` for how the audit runs and fails.

Evaluate audit quality through complete claim coverage, current source and
GitHub evidence, justified keep/archive decisions, valid links, and useful
consolidation. Generic coding benchmarks do not establish memory-curation
quality. Revisit the model only when audit results show a concrete need.

**Current runner:** Home's nightly guidance review audits the notes on Sonnet
at high effort, with the shared key and the subscription fallback, and reads
the key from PodHaven's `.env` before `~/.env`
([jubishop/zshrc#343](https://github.com/jubishop/zshrc/issues/343)). It
replaced Project Starter's memory-audit feature, which ran the job from 3.2.0
(commit `e1407934`, issue #759) until 4.0.0 retired it with its runner,
`bin/_memory_audit.py`, and `.cache/memory-audit/latest.json`. When the
guidance review changes, keep Sonnet, the shared key, and the subscription
fallback above.
