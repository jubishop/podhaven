---
status: blocked
---

# Swift Backtrace API for Telemetry

Research note for adopting Swift Evolution SE-0419's `Backtrace` API in PodHaven logging and telemetry. Researched 2026-05-18 against the local toolchain and the app's iOS build targets.

## Status

Do not adopt yet. The Swift backtrace API exists in the current Swift release line, but the public module is not available to PodHaven's `iphoneos` or `iphonesimulator` targets.

This repo is already using Swift 6 language mode (`SWIFT_VERSION = 6.0`), and this machine is on Xcode 26.5 / Apple Swift 6.3.2. `import Runtime` type-checks for the host macOS toolchain, but fails for iOS device and simulator builds with `no such module 'Runtime'`.

## What Swift ships

SE-0419 was accepted and implemented as a public backtrace API. The current Swift changelog lists it under Swift 6.2 as the new `Runtime` module, with a `Backtrace.capture()` API and current support for macOS and Linux.

The proposal text is still useful for the intended shape of the API:

- `Backtrace.capture()` captures frames during normal execution.
- `Backtrace.symbolicated()` can resolve symbols for the captured trace.
- The API is not meant to be an async-signal-safe crash reporter.

That last point matters for PodHaven: the right use is enriching caught non-fatal errors and explicit critical logs, not replacing Sentry's crash reporting.

## Local verification

The local toolchain:

```sh
swift --version
# swift-driver version: 1.148.6 Apple Swift version 6.3.2

xcodebuild -version
# Xcode 26.5
```

macOS type-check succeeds:

```sh
printf 'import Runtime\nlet _ = Backtrace.self\n' | swiftc -typecheck -
```

iOS simulator type-check fails:

```sh
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
printf 'import Runtime\nlet _ = Backtrace.self\n' \
  | xcrun --sdk iphonesimulator swiftc \
      -target arm64-apple-ios26.0-simulator \
      -sdk "$SDK" \
      -typecheck -
# error: no such module 'Runtime'
```

iOS device type-check fails the same way:

```sh
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
printf 'import Runtime\nlet _ = Backtrace.self\n' \
  | xcrun --sdk iphoneos swiftc \
      -target arm64-apple-ios26.0 \
      -sdk "$SDK" \
      -typecheck -
# error: no such module 'Runtime'
```

The older proposal-header module name is not usable either:

```sh
printf 'import _Backtracing\nlet _ = Backtrace.self\n' | swiftc -typecheck -
# error: no such module '_Backtracing'
```

## PodHaven adoption point

When `Runtime` becomes available to iOS targets, keep the adoption narrow:

- Add a small logging helper that captures a bounded backtrace and returns a string or structured metadata.
- Call it from `Logger.caughtError(...)` and `Logger.error(_:)` only for remarkable errors.
- Attach it to `SentryLogHandler` attributes and file logs rather than baking symbolication into every log message.
- Avoid capturing on routine debug/info logs, cancellation, timeout, and expected-control-flow errors.

The first implementation should be defensive:

```swift
import Runtime

enum LogBacktrace {
  static func capture() -> String? {
    do {
      let backtrace = try Backtrace.capture(limit: 32, offset: 1, top: 8)
      return backtrace.symbolicated()?.description ?? backtrace.description
    } catch {
      return nil
    }
  }
}
```

Tune the exact limit and symbolication behavior after measuring runtime cost on device. Symbolication may be too expensive for hot paths or background execution, so the first pass should prefer capture only on error-level events.

## Recheck trigger

Revisit this after a new Xcode or Swift release, or if Apple documents `Runtime` availability for iOS. The quick check is still:

```sh
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
printf 'import Runtime\nlet _ = Backtrace.self\n' \
  | xcrun --sdk iphonesimulator swiftc \
      -target arm64-apple-ios26.0-simulator \
      -sdk "$SDK" \
      -typecheck -
```

Adoption is unblocked only when that command succeeds for the app's supported SDK targets.

## Sources

- [SE-0419: Swift Backtrace API](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0419-backtrace-api.md)
- [Swift changelog](https://raw.githubusercontent.com/swiftlang/swift/main/CHANGELOG.md)
- [Swift 6.3 Released](https://www.swift.org/blog/swift-6.3-released/)
- [Announcing Swift 6.3.2](https://forums.swift.org/t/announcing-swift-6-3-2/86698)
- [Swift Forums: Current availability of the Runtime module](https://forums.swift.org/t/current-availability-of-the-runtime-module/82726)
