---
name: Factory v3 actor-isolation pattern
description: How to define and migrate Factory closures for @MainActor / global-actor types after Factory v3.0
type: reference
originSessionId: 004785e6-d902-4676-82f6-2ff941067ffb
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
- Test target's `autoRegister()` is a non-isolated protocol method; if it overrides a `@MainActor` factory (e.g., `uiApplication.context(.test) {...}`), wrap the access in `MainActor.assumeIsolated { _ = uiApplication.context(.test) {...}.scope(.cached) }`. Tests bootstrap on MainActor in practice, so this is safe.

**Test target linker**: Factory v3 makes FactoryTesting `.dynamic` and FactoryKit static. The test target needs both as explicit package product dependencies — FactoryKit isn't transitively visible to the test bundle through FactoryTesting.framework. Pre-existing project setups that only listed FactoryTesting will fail with `Undefined symbols: FactoryKit.Factory.callAsFunction()` at link time.

**swift-log**: same package-update window introduced `LogHandler.log(event: LogEvent)` as the new required impl. The old `log(level:message:metadata:source:file:function:line:)` is deprecated; default impl that forwards to it is `@available(*, deprecated)`.

**Nuke**: `DataLoading` reverted from async-stream to callback-based `loadData(with:didReceiveData:completion:) -> any Cancellable`. Wrap async fakes by spawning a `Task` and returning a Cancellable that cancels it.
