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

### State Management
- **Observable**: Use `@Observable` classes for reactive view state
- **Shared State**: Use Point-Free's `Sharing` library for persistent state
- **Navigation**: Centralized `Navigation` class with tab-based routing

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
- Don't add excessive comments beyond `// MARK: -` style comments

### Naming Conventions
- Types: PascalCase (`PodcastFeed`, `EpisodeViewModel`)
- Variables/functions: camelCase (`feedURL`, `makeMigrator()`)
- Protocol conformances: Alphabetical order

### Testing Patterns
- Comprehensive fake implementations for external dependencies
- Test-specific dependency injection with container override
- In-memory database for fast tests
- Use `#expect` for assertions in Swift Testing

### Code Patterns
- ViewModels should have `execute()` function in Initialization section
- Use GRDB query builder APIs over raw SQL
- Prefer Swift concurrency (async/await) with proper error handling
- Use protocol-oriented design for behavioral abstractions

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

## Code Style

### String Formatting
- When a string is going to force a line beyond 100 columns, break it into multiple lines using """ delimiters.

## Code Safety
- Never use `!` to force unwrap optionals in production code.

## Github Interactions
- If I ask you to do anything with Github, use the Github CLI (gh)