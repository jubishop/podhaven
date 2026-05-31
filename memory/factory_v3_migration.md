---
name: factory-v3-migration
description: How to define and migrate Factory closures for @MainActor / global-actor types after Factory v3.0
type: reference
---
Factory v3.0 changed the closure typealias from `@Sendable @isolated(any) () -> T` to plain `() -> T`. Old `Factory(self) { @MainActor in Foo() }` no longer compiles.

**Right pattern (per Factory v3 SwiftUI.docc — "Coping With @MainActor"):**

```swift
extension Container {
  @MainActor var foo: Factory<Foo> {
    Factory(self) { Foo() }.scope(.cached)
  }
}
```

The `@MainActor` on the var (not on the closure body) inherits into the closure since it's defined inside an `@MainActor` getter context. Forces callers to be on MainActor before resolving — closure body runs on the right actor.

**Why `MainActor.assumeIsolated { Foo() }` is wrong**: it only papers over the issue. Latent bug surfaces if the factory is ever resolved off-main (we hit this with `PlayManager.podAVPlayer` getter doing `await Container.shared.podAVPlayer()` from cooperative pool — the await hops for the read, but `()` runs back on cooperative pool and traps).

**Cascade caveats**:
- Adding `@MainActor` to a Factory accessor surfaces every off-main caller as a compile error. Often the real bug, but real refactor work.
- For PlayManager-style cases where the type is `@PlayActor` but is heavily `@DynamicInjected` from `@MainActor` view models, marking the accessor `@PlayActor` cascades hard. Workaround: keep accessor non-isolated and make the type's init `nonisolated` (works when init body is empty / properties default-initialize without isolation).
- Test target's `autoRegister()` is a non-isolated protocol method; under Swift Testing it runs on the cooperative pool (whichever actor first resolves any factory in the container — often a non-`@MainActor` test class via `@DynamicInjected`). Wrapping the override in `MainActor.assumeIsolated { _ = uiApplication.context(.test) {...} }` traps with `EXC_BREAKPOINT` (`_dispatch_assert_queue_fail`), which Xcode reports as every test "crashed with signal trap" / 0.000s. Bypass the `@MainActor` accessor instead: construct the registration directly with `Factory<T>(self, key: "<accessorName>") { Assert.fatal(...) }.context(.test) { ... }.scope(.cached)`. The key must literally match the production accessor's `#function` (e.g. `"avPlayer"`, `"uiApplication"`); the default closure is unreachable because `FactoryContext` auto-activates `.test` for xctest processes. If the fake itself is `@MainActor` (e.g. `FakeAVPlayer`), put `MainActor.assumeIsolated { FakeAVPlayer() }` in the `.test` closure body — every test that resolves it is `@MainActor`.

**Test target linker**: Factory v3 makes FactoryTesting `.dynamic` and FactoryKit static. The test target needs both as explicit package product dependencies — FactoryKit isn't transitively visible to the test bundle through FactoryTesting.framework. Pre-existing project setups that only listed FactoryTesting will fail with `Undefined symbols: FactoryKit.Factory.callAsFunction()` at link time.

**swift-log**: same package-update window introduced `LogHandler.log(event: LogEvent)` as the new required impl. The old `log(level:message:metadata:source:file:function:line:)` is deprecated; default impl that forwards to it is `@available(*, deprecated)`.

**Nuke**: `DataLoading` reverted from async-stream to callback-based `loadData(with:didReceiveData:completion:) -> any Cancellable`. Wrap async fakes by spawning a `Task` and returning a Cancellable that cancels it.

## Related

- [[flaky-test-observation-restarts]] — same family of Task/priority inheritance gotchas in the test target, surfaced by `Wait.until`'s `.background` default starving a spawned observation task.
- [[observation-broadcast-viewmodel]] — when `@DynamicInjected` resolves a `@Broadcasted` value through an `@Observable` computed property, observation can silently miss conditional views.
