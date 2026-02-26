---
description: Run tests and fix any failures
argument-hint: [specific test class or method, e.g. ParallelTests/SomeTestClass/testMethod]
allowed-tools: Bash(xcodebuild:*), Bash(swift-format:*), Read, Edit, Write, Glob, Grep, Task
---

Run the project's tests and, if any fail, diagnose and fix the failures. Repeat until all tests pass or you determine the failure is not fixable without user input.

## Step 1 — Run tests

If `$ARGUMENTS` is provided, run only the specified test:

```
xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:$ARGUMENTS 2>&1
```

Otherwise, run all tests via the test plan:

```
xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -testPlan PodHaven -parallel-testing-enabled YES 2>&1
```

## Step 2 — Parse results

Examine the xcodebuild output for:
- **Build errors**: compilation failures that prevent tests from running
- **Test failures**: lines containing `failed` or `Test .* failed`
- **Crash logs or assertion failures**

If all tests pass (`** TEST SUCCEEDED **`), report success and stop.

## Step 3 — Diagnose and fix

For each failure:

1. Identify the failing test file and method from the output.
2. Read the failing test code and the production code it exercises.
3. Determine whether the fix belongs in **production code** or **test code**:
   - If the test expectation is correct and production code is wrong, fix the production code.
   - If production behavior is correct and the test expectation is stale or wrong, fix the test.
   - If a build error prevents compilation, fix the build error first.
4. Apply the fix using Edit.
5. Run `swift-format` on every file you modified:
   ```
   swift-format format --in-place <file>
   ```

## Step 4 — Re-run and verify

After applying fixes, re-run the same test scope from Step 1. Repeat Steps 2–4 until:
- All tests pass, or
- You've attempted 3 fix-and-rerun cycles without progress

## Rules

- Follow all coding standards from AGENTS.md (no force-unwraps, use `Assert`, `ReadableError`, `//` comments, etc.).
- Tests use Swift Testing (`@Suite`, `#expect`). Never introduce XCTest APIs.
- Tests must never use `Task.sleep`. Use `Wait.until` for async conditions.
- Tests may use `sleeper.sleep` only to advance artificial time.
- Do not create commits or modify unrelated code.
- If a failure requires architectural changes or is ambiguous, stop and explain the situation instead of guessing.
