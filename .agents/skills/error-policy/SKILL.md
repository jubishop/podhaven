---
name: error-policy
description: Audit error handling in Swift files against the project error policy
argument-hint: [file or directory path to audit, or blank for full codebase]
user_invocable: true
disable-model-invocation: true
context: fork
---

# Error Policy

Audit the specified Swift files (or the full codebase if no `$ARGUMENTS` provided) against the error handling policy below. Exclude test files (`PodHavenTests/`) and the ShareExtension target.

## Error Handling Policy

### When to catch errors locally

Catch where the code can recover, present a failure, or finish an operation that cannot propagate errors. Recovery can include continuing independent work after one item fails. These responsibilities justify catching even when there is no extra local context.

Add useful local context without hiding the failure. If a catch only adds context, preserve and rethrow the error.

Never turn an error into a value that could be mistaken for success. For example, a failed database query must remain distinguishable from a successful query that found no rows. Returning `nil`, `false`, or `[]` is appropriate only when the operation's contract makes the failure or recovery unambiguous.

### When to let errors propagate

Otherwise, let errors propagate to a caller that owns recovery, failure presentation, or completion of the operation. Extra logging context alone is not a reason to stop propagation.

### Top of call stack

Ensure errors are logged before they stop propagating, except for the silent cancellation checks and sleeps allowed below. Use `caughtError(...)` when logging a caught error. An error that is rethrown remains the responsibility of its caller unless it has already been logged.

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
- `log.caughtError(` — verify the message identifies the failed operation, includes the caught error, and adds useful local context when available
- Throwing functions — verify errors don't silently disappear at call-stack tops

### Step 3 — Evaluate each site

For each site, determine:
1. Does this code own recovery, failure presentation, or completion of an operation that cannot propagate errors? If it only adds context, does it preserve and rethrow the error?
2. Is the do/catch scope **minimal**?
3. Should the error propagate to a caller that owns handling it?
4. Is the error logged before it stops propagating, unless an explicit cancellation exception applies?
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
