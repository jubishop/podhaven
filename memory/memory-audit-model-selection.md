---
name: "memory-audit-model-selection"
description: "Treat the scheduled memory audit as semantic curation and keep DeepSeek V4 Flash until task-specific evidence supports a replacement within the $0.20 run budget."
type: "feedback"
---

# Memory-audit model selection

Evaluate the scheduled memory audit as retrieval-augmented semantic curation, not as coding-agent work. Keep `deepseek/deepseek-v4-flash-0731` at medium reasoning as the default unless a task-specific comparison demonstrates a meaningful quality improvement while staying within the $0.20 run budget agreed on 2026-09-05.

**Why:** The audit extracts claims from every active note, retrieves current repository and GitHub evidence, classifies each note as keep or archive, consolidates overlap, and produces a structured report. Its iterative tool loop is mechanically agentic, but the substantive work is document analysis and evidence-backed judgment. Terminal and coding-agent benchmarks are therefore weak selection signals.

Historical comparison as of 2026-07-19 (the exploratory $0.50 ceiling below predates the current run budget):

- The latest scheduled run reviewed 14 of 14 active notes successfully in 61 turns and cost $0.123512 through OpenRouter.
- Projected weekly spend at that measured rate is about $0.54 per month or $6.42 per year.
- GPT-5.6 Luna was estimated at roughly $1–$3 for the same audit, above the desired budget.
- A current catalog review found DeepSeek V4 Flash strong in its price class on instruction following and long-context reasoning. GLM 5.2 was the only plausible higher-quality candidate near the $0.50 ceiling, but it had not been evaluated on the actual audit.

Evidence snapshot:

- [Successful scheduled audit](https://github.com/jubishop/podhaven/actions/runs/29647837796)
- [DeepSeek V4 Flash benchmarks and pricing](https://openrouter.ai/deepseek/deepseek-v4-flash/benchmarks)
- [GLM 5.2 benchmarks and pricing](https://openrouter.ai/z-ai/glm-5.2)
- [GPT-5.6 Luna pricing](https://openrouter.ai/openai/gpt-5.6-luna-20260709)

**How to apply:** Rank candidate models primarily by instruction following, long-context comprehension, grounded claim extraction, semantic classification, and synthesis quality. Treat reliable tool calls, structured output, sufficient context, and the report completion contract as gates. Give generic terminal and coding-agent scores little weight.

Before switching, run the candidate without publication against a frozen audit snapshot and compare:

- Per-note claim coverage and evidence validity
- Keep/archive/consolidation verdict correctness
- Missed or invented repository facts
- Report-contract compliance
- Completed-run cost

Prefer the current model unless the candidate produces a clear quality gain within the $0.20 run budget. Do not switch based only on a generic leaderboard or model branding. For an exact cost comparison, retain the input, cached-input, reasoning, and output token breakdown; the published audit artifacts currently retain only total cost.

Revisit this decision when audit quality problems recur, the audit scope changes materially, a candidate wins the frozen comparison, or provider pricing changes enough to alter the tradeoff.
