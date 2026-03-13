---
description: Audit error handling in Swift files against the project error policy
argument-hint: [file or directory path to audit, or blank for full codebase]
disable-model-invocation: true
context: fork
---

Audit the specified Swift files (or the full codebase if no `$ARGUMENTS` provided) against the error handling policy below. Exclude test files (`PodHavenTests/`) and the ShareExtension target.

## Error Handling Policy

### When to catch errors locally

Catch the error **right there** and log with `caughtError(...)` if the function has **extra informative context derived entirely locally** — i.e. not just a parameter passed into the function that the caller already has, and not information already contained within the error being thrown. Then early return (`return` for void, `return nil/false/[]` etc.).

**Exceptions:**
- If returning nil/false/[] would be **ambiguous with a valid non-error result** (e.g. a DB fetch where `[]` could mean "no results" vs "DB error"), log the extra context alongside the error and **rethrow** — accept potential double-logging.
- If the calling function has **other work to do** even when the called function throws, catch and log on the spot so it can continue rather than early-exit.

### When to let errors propagate

If the function has **no extra local context** beyond what the caller already knows, **don't catch** — let the error propagate up the call stack until a caller that does have useful context catches and logs it.

### Top of call stack

By the very top of any call stack, every error **must** be logged somewhere. Errors must never silently disappear.

### `try?` usage

- Convert all `try?` to a normal `try` with `catch` and `log.error`/`log.caughtError`, unless it's for a **sleep** or **checkCancellation** where task cancellation is a reasonable outcome.
- If the failure isn't exceptional, the log level may be set to `.info` via the `remarkable:` parameter.

### do/catch scope

- Wrap **only the minimal code necessary** for the try calls; let other work execute outside the do/catch.
- A single do/catch may wrap multiple try calls **only if** the catch message clearly describes one thing and wouldn't leave a log reader unsure about what exactly went wrong.

### log.error() enrichment

Check every `log.error()` callsite and consider if it should use `log.caughtError()` instead when there's a caught error object to include.

### Acceptable patterns (no changes needed)

- **String-only `log.error("")`** is fine when there's a genuine error condition but no caught error object.
- **SelectableEpisodeList / SelectablePodcastList** operations on multiple items: OK to just log without alerting for individual failures.
- **Observation failures** in `ViewModel.execute` methods or background looping "observation" functions: OK to just log without alerting.
- **Share target**: nonstandard imports are OK.
- **Sleep / checkCancellation** in task-cancellation scenarios: no logging needed.

## Audit Steps

### Step 1 — Scope

If `$ARGUMENTS` is provided, limit the audit to those files/directories. Otherwise audit all production Swift files under `PodHaven/` (exclude `PodHavenTests/` and `ShareExtension/`).

### Step 2 — Find all error handling sites

Search the scoped files for:
- `try?` — check each against the sleep/checkCancellation exemption
- `do {` / `} catch` — check scope minimality and catch quality
- `log.error(` — check if a caught error object is available and `caughtError` should be used instead
- `log.caughtError(` — verify the context message adds locally-derived information
- Throwing functions — verify errors don't silently disappear at call-stack tops

### Step 3 — Evaluate each site

For each site, determine:
1. Does the catch have **locally-derived context** that justifies catching here?
2. Is the do/catch scope **minimal**?
3. Could the error **propagate instead** because the caller has equal or better context?
4. At the top of the call stack, is the error **always logged**?
5. Would the return value on error be **ambiguous** with a valid result?
6. Does the function have **other work** that should continue despite the error?

### Step 4 — Consider reorganization

Flag any cases where rearranging function structure would improve error handling clarity. For example:
- Splitting a function that catches too broadly
- Extracting a throwing helper so the catch can be more targeted
- Moving a catch higher or lower in the call stack

### Step 5 — Report

For each violation or improvement found:
1. File path and line number
2. Current code (brief excerpt)
3. Which policy rule is violated
4. Suggested fix

If **no violations** are found, report that the audited code is compliant.

If you encounter any scenario you're **uncertain** about, stop and ask the user rather than guessing.
