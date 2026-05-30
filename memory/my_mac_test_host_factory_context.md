---
name: my-mac-test-host-factory-context
description: Tests (My Mac and CI) resolved production types instead of fakes because the test target linked a duplicate static copy of FactoryKit, breaking the AutoRegistering conformance lookup. Fixed by removing the test target's direct FactoryKit link.
type: project
---

# My Mac / CI test fakes not resolving — duplicate FactoryKit (RESOLVED)

**Status:** resolved (2026-05-29). Tests on **My Mac** and **CI** randomly resolved production types (e.g. `Sleeper` instead of `FakeSleeper`, on-disk instead of in-memory `AppDB`), causing `Could not cast … Sleeper … to FakeSleeper` fatals and migration crashes.

## Root cause

The `PodHavenTests` target linked **both** `FactoryKit` **and** `FactoryTesting`. `FactoryTesting` depends on `FactoryKit`, so this duplicated FactoryKit in the process:

- App links the shared dynamic `FactoryKit.framework`.
- The test bundle statically linked a **second** copy of FactoryKit (pulled in via `FactoryTesting`), so `_$s10FactoryKit15AutoRegisteringMp` (the `AutoRegistering` protocol descriptor) existed twice — once in the dynamic framework, once inside `PodHavenTests.xctest`.

The `@retroactive AutoRegistering` conformance in `PodHavenTests/Extensions/Container.swift` bound to the test bundle's static descriptor, while FactoryKit's own resolution path (`unsafeCheckAutoRegistration` → `self as? AutoRegistering`, in the dynamic framework) queried the dynamic descriptor. The two never matched, so **`autoRegister()` was never invoked** → `.context(.test)` fakes were never registered → resolution fell through to production closures.

Factory's docs say this explicitly (`FactoryKit.docc/Development/Testing.md`):

> Do not import `FactoryKit` into the Test target. That can lead to duplicate factories and indeterminate behavior.

**Regression trigger:** commit `a4feeab` removed the "Embed Test Frameworks" copy phase. That phase had made `FactoryTesting` an embedded **dynamic** framework, which masked the problem (its FactoryKit references resolved to the single dynamic copy). Without it, Xcode linked `FactoryTesting` (and a static FactoryKit slice) into the test bundle, exposing the duplicate.

## Diagnostics that nailed it

A throwaway `@Test` in the test bundle printed:

- `FactoryContext.current.isTest = true` — test context detection was **never** the problem (the original hypothesis below was wrong).
- `Container().sleeper() = Sleeper` — production resolved.
- `Container() is AutoRegistering = true` — conformance visible **from test-bundle code** (its own descriptor).
- `(explicit as? AutoRegistering)?.autoRegister(); …sleeper() = FakeSleeper` — the hook works when called directly; only the automatic invocation failed.
- `_dyld` image scan + `nm` showed two copies of `_$s10FactoryKit15AutoRegisteringMp` (dynamic framework + test bundle).

## The fix

Remove the test target's **direct** `FactoryKit` link; keep only `FactoryTesting` (which provides the `FactoryKit` module transitively, and shares the host app's single dynamic copy). In `PodHaven.xcodeproj/project.pbxproj`, delete the `PodHavenTests` references to product `FactoryKit` (build file, Frameworks phase entry, `packageProductDependencies`, and the `XCSwiftPackageProductDependency`). `import FactoryKit` in test files still compiles.

After the fix: a single `FactoryKit` image loads, `Container.shared.sleeper()`/`Container().sleeper()` return `FakeSleeper`, and the full My Mac suite passes (1283 tests, 0 failures). Same change fixes CI (the duplicate is destination-independent).

## Prior workarounds (reverted as unnecessary)

The earlier attempts in `AppInfo`/`AppDB`/`AppLauncher` were reverted. They were not needed once the linkage was fixed: the original `AppInfo.detectEnvironment()` already returns `.testing` on My Mac (its `XCTestConfigurationFilePath != nil` check holds — the var is present, just empty-valued), so `AppLauncher.bootstrap()` is already skipped on the host during tests. The full My Mac suite passes (1284 tests, 0 failures) with **only** the pbxproj linkage change. For reference, the reverted attempts were: `AppInfo.isRunningUnderTest`, `AppDB.makeProduction()`/`shouldUseTestDatabase`, and removing eager `initializeAppDB()` from bootstrap.

## Wrong turns (do not repeat)

- The earlier theory that `FactoryContext.current.isTest` was `false` on My Mac was **incorrect** — it was always `true`. Don't chase env-var detection.
- Re-adding the embed phase alone fails to build: `FactoryTesting` is not built as an embeddable framework here ("The file 'FactoryTesting' couldn't be opened…"). The correct fix is dropping the duplicate FactoryKit link, not re-embedding.
- Editing shipped migrations to tolerate a corrupt local Debug DB — wrong layer.

## Related

- [[factory_v3_migration]] — Factory v3 / FactoryTesting packaging.
- [[build-variants-dev-debug-release]] — Run = Development/`.dev`, Test = Debug/`.debug`, separate data dirs.
- [[flaky_test_observation_restarts]] — parallel Swift Testing + DI timing family.
