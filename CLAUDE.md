# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Essential Build & Test Commands

### Building
- Open in Xcode: `open PodHaven.xcodeproj`
- Build from terminal: `xcodebuild -project PodHaven.xcodeproj -scheme PodHaven -configuration Debug build`
- Run in Xcode: ⌘R

### Testing
- Run all tests: `xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven`
- Run specific test class: `xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven -only-testing:ParallelTests/[TestClassName]`
- Run individual test: `xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven -only-testing:ParallelTests/[TestClassName]/[testMethodName]`
- In Xcode: ⌘U for all tests, or use Test Navigator (⌘6)

## Core Architecture Patterns

### Dependency Injection (FactoryKit)
- **ViewModels**: Use `@DynamicInjected(\.repo)` for cached dependencies
- **Views**: Use `@InjectedObservable(\.navigation)` for observable dependencies
- **Unique scope**: Use `@LazyInjected` only for `.scope(.unique)` dependencies
- **Testing**: Mark test suites with `@Suite(..., .container)` and use `.context(.test)` for mocks

### Database Layer (GRDB)
- **Models**: Separation between `UnsavedX` (data) and `X` (domain) using `@Saved` macro
- **Repository**: Central `Repo` class handles all database operations
- **Migrations**: Schema changes in `Schema.swift` with versioned migrations
- **Type Safety**: Use `Tagged` types for identifiers (`Podcast.ID`, `GUID`, `MediaURL`)

### Error Handling
- **Domain Errors**: Create enums conforming to `ReadableError` protocol
- **Error Wrapping**: Use `CatchingError` protocol for errors that wrap others
- **Error Catching**: Use `ErrorType.catch { }` pattern for automatic wrapping
- **Logging**: Use `ErrorKit` utilities for error presentation

### Concurrency
- **Actors**: Use Swift actors for thread-safe managers (PlayManager, FeedManager)
- **Async Streams**: Use `AsyncStream` for reactive data flows
- **Structured Concurrency**: Use task groups and proper cancellation
- **MainActor Usage**: Don't use `MainActor.run`

### State Management
- **Observable**: Use `@Observable` classes for reactive view state
- **Shared State**: Use Point-Free's `Sharing` library for persistent state
  - Don't use `UserDefaults` directly.
- **Navigation**: Centralized `Navigation` class with tab-based routing

### System Notifications
- **Dependency Injection**: Use `@DynamicInjected(\.notifications)` for notification handling
- **Production**: Factory returns `NotificationCenter.default.notifications(named:)` AsyncSequence
- **Testing**: Factory returns controllable `AsyncStream` via `Notifier` fake
- **Pattern**: `for await notification in await notifications(name) { ... }` in async contexts
- **Testing**: Use `notifier.continuation(for: name).yield(notification)` to trigger events
- **Examples**: See `PlayManager`, `RefreshManager`, and `FileLogHandler` for system event handling

## Key Architectural Components

### PlayManager (Actor)
- Thread-safe audio playback management
- Wraps `AVQueuePlayer` with custom `PodAVPlayer`
- Handles queue management and command center integration

### FeedManager (Actor)
- Concurrent RSS feed downloading and processing
- Uses `AsyncStream` for streaming results
- Handles parsing failures gracefully

### SearchService
- PodcastIndex API integration with type-safe result models
- Different search types: term, title, person, trending
- Protocol-based network abstraction for testing

### Queue System
- Complex episode queuing with position management
- Database transactions for atomic operations
- SQL-optimized operations for performance

## Development Guidelines

### File Organization
- Each top-level type in its own file with matching name
- Copyright header: "Copyright Justin Bishop, 2025"
- Use `// MARK: - Section Name` for major sections only

### Naming Conventions
- Types: PascalCase (`PodcastFeed`, `EpisodeViewModel`)
- Variables/functions: camelCase (`feedURL`, `makeMigrator()`)
- Protocol conformances: Alphabetical order

### Testing Patterns
- Comprehensive fake implementations for external dependencies
- Test-specific dependency injection with Factory Container override
- In-memory database for fast tests
- Use `#expect` for assertions in Swift Testing

### Code Patterns
- ViewModels should have `execute()` function in Initialization section
- Views should only interact with their ViewModel
- Use GRDB query builder APIs over raw SQL
- Prefer Swift concurrency (async/await) with proper error handling
- Use protocol-oriented design for behavioral abstractions
- **Important Rule**: Don't put functions in View files ever. Put them in their ViewModel, or somewhere even deeper in the stack if it is more generically reusable.

## Requirements
- Xcode 16.3 or later
- Swift 6.10 or later

## Key Dependencies
- GRDB: Database management
- XMLCoder: RSS feed parsing
- Nuke/NukeUI: Image loading and caching
- Factory: Dependency injection
- Tagged: Type-safe identifiers
- Sentry: Error reporting (production only)

## Logging System

### Architecture
- **Centralized Configuration**: Logging is configured in `PodHavenApp.swift` using `LoggingSystem.bootstrap`
- **Environment-specific Handlers**: Different log handlers based on app environment
  - iPhone: `OSLogHandler`, `FileLogHandler`, `CrashReportHandler` (via `MultiplexLogHandler`)
  - Preview: `PrintLogHandler` only
  - Simulator/Mac/AppStore: `OSLogHandler` only

### Log Handlers
- **OSLogHandler**: Native iOS logging via `os.Logger` with subsystem/category structure
- **FileLogHandler**: Structured JSON logs written to `Documents/log.ndjson`
  - NDJSON format with level, timestamp, subsystem, category, message, metadata
  - Automatic cleanup (removes older logs)
  - Background queue for async writing (sync for critical logs)
- **PrintLogHandler**: Simple console output for previews
- **CrashReportHandler**: Sentry integration for critical errors only

### Usage Patterns
- **Logger Creation**: Use `Log.as(categorizable)` or `Log.as(category, level)`
- **Categorization**: Use `LogCategorizable` protocol with subsystem/category/level
- **Error Logging**: Use `log.error(error)` with `ErrorKit` integration
- **Level Mapping**: Custom integer mapping for structured logging

## Code Style

### String Formatting
- When a string is going to force a line beyond 100 columns, break it into multiple lines using """ delimiters.

### Commenting
- Don't add excessive comments beyond `// MARK: - Section Name` style comments

## Code Safety
- Never use `!` to force unwrap optionals in production code.
- Don't use opacity below 1.0 for text

## Github Interactions
- If I ask you to do anything with Github, use the Github CLI (gh)

## Object Logging
- When logging objects that conform to `Stringable` use `.toString`

## Build & Test Policy
- Don't bother trying to build or test

## Code Formatting
- Run swift-format on any files you change
