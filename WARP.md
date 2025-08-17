# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Essential Build & Test Commands

### Building
- Build from terminal: `xcodebuild -project PodHaven.xcodeproj -scheme PodHaven -configuration Debug build`
- Don't try to build the project unless explicitly asked.

### Testing
- Run all tests: `xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven`
- Run specific test class: `xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven -only-testing:PodHavenTests/[TestClassName]`
- Run individual test: `xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven -only-testing:PodHavenTests/[TestClassName]/[testMethodName]`
- Don't try to run the tests unless explicitly asked.

### Utilities
- Repeat failing tests: `Tools/run_test_until_failure.sh [testMethodName]`
- RSS validation: `Tools/validate_rss.rb [rss_file]`

## Core Architecture

### Database Layer (GRDB)
- **Schema Management**: Database migrations in `PodHaven/Database/Schema.swift` with versioned incremental changes
- **Model Architecture**: Separation between `UnsavedX` (data) and `X` (domain) using `@Saved` macro from local `PodHavenMacros` package
- **Repository Pattern**: Central `Repo` class handles all database operations with type-safe query building
- **Type Safety**: Use `Tagged` types for identifiers (`Podcast.ID`, `Episode.ID`, `GUID`, `MediaURL`)

### Dependency Injection (FactoryKit)
- **ViewModels**: Use `@DynamicInjected(\.repo)` for cached dependencies
- **Views**: Use `@InjectedObservable(\.navigation)` for observable dependencies
- **Unique Scope**: Use `@LazyInjected` only for `.scope(.unique)` dependencies
- **Testing**: Mark test suites with `@Suite(..., .container)` and use `.context(.test)` for mocks

### Concurrency Architecture
- **Actors**: Thread-safe managers using Swift actors (`PlayManager`, `FeedManager`, `RefreshManager`)
- **PlayActor**: Custom global actor for audio playback isolation (`@PlayActor`)
- **Async Streams**: Reactive data flows using `AsyncStream` for real-time updates
- **System Integration**: Uses dependency-injected notification handling for system events

### Key Managers

#### PlayManager (PlayActor)
- Thread-safe audio playback management wrapping `AVPlayer` with custom `PodAVPlayer`
- Handles episode loading, queue management, and command center integration
- Manages now-playing metadata and automatic episode progression
- Uses persistent storage for current episode state restoration

#### FeedManager (Actor)
- Concurrent RSS feed downloading and processing using `AsyncStream`
- Handles feed parsing failures gracefully with structured error reporting
- Supports streaming results for responsive UI updates during bulk operations

#### SearchService
- PodcastIndex API integration with type-safe result models
- Multiple search types: term, title, person, trending podcasts
- Protocol-based network abstraction for comprehensive testing

#### Queue System
- Complex episode queuing with precise position management
- Database transactions ensure atomic operations for queue modifications
- SQL-optimized operations for high-performance queue manipulation

### Error Handling
- **Domain Errors**: Create enums conforming to `ReadableError` protocol
- **Error Wrapping**: Use `CatchingError` protocol for errors that wrap others
- **Error Catching**: Use `ErrorType.catch { }` pattern for automatic wrapping
- **Logging Integration**: Use `ErrorKit` utilities for error presentation and logging

### Logging System
- **Centralized Configuration**: Configured in `PodHavenApp.swift` using `LoggingSystem.bootstrap`
- **Environment Handlers**: Different log handlers based on app environment:
  - iPhone: `OSLogHandler`, `FileLogHandler`, `CrashReportHandler` via `MultiplexLogHandler`
  - Preview: `PrintLogHandler` only
  - Simulator/Mac/AppStore: `OSLogHandler` only
- **Structured Logging**: NDJSON format file logs with level, timestamp, metadata
- **Usage**: Use `LogCategorizable` protocol with subsystem/category/level definitions

### State Management
- **Observable Classes**: Use `@Observable` for reactive view state management
- **Shared State**: Point-Free's `Sharing` library for persistent state (avoid `UserDefaults` directly)
- **Navigation**: Centralized `Navigation` class with tab-based routing using SwiftNavigation

## Development Guidelines

### Code Architecture Patterns
- **ViewModels**: Should have `execute()` function in Initialization section
- **Views**: Only interact with their ViewModel - never put functions in View files
- **File Organization**: Each top-level type in its own file with matching name
- **Copyright**: Include "Copyright Justin Bishop, 2025" at file start

### Dependencies
- **GRDB**: Database management with query builder APIs (avoid raw SQL)
- **XMLCoder**: RSS feed parsing with structured error handling
- **Nuke/NukeUI**: Image loading and caching with async/await support
- **Factory**: Dependency injection with comprehensive testing support
- **Tagged**: Type-safe identifiers preventing ID confusion
- **Sentry**: Error reporting in production builds only
- **Point-Free Libraries**: Navigation, Sharing, IdentifiedCollections for reactive state

### Testing Patterns
- **Swift Testing**: Use `#expect` for assertions in comprehensive test suites
- **Fake Implementations**: Complete fake implementations for external dependencies
- **Container Override**: Test-specific dependency injection with Factory Container
- **In-Memory Database**: Fast tests using GRDB in-memory instances
- **Parallel Execution**: Separate test targets for parallel vs. performance tests

### Code Safety & Style
- **Optionals**: Never use `!` to force unwrap optionals in production code
- **Concurrency**: Use Swift concurrency (async/await) with proper cancellation
- **String Formatting**: Use `"""` delimiters for long strings exceeding 100 columns
- **Naming**: PascalCase types, camelCase variables/functions
- **Protocol Conformances**: List alphabetically with attributes sorted

### Specialized Files
- **Schema.swift**: Contains all database migration logic with detailed change tracking
- **AGENTS.md**: Identical to CLAUDE.md for AI coding assistant guidance
- **Local Package**: `PodHavenMacros` provides `@Saved` and `@ReadableError` macros
- **Share Extension**: `PodHavenShare` handles external podcast URL sharing

### Code Formatting
- Run swift-format on any files you change

## Project Structure
- **PodHaven/**: Main app target with SwiftUI views and business logic
- **PodHavenTests/**: Comprehensive test suite with parallel execution support
- **PodHavenMacros/**: Local Swift Package for custom macros
- **PodHavenShare/**: App extension for handling shared podcast URLs
- **Tools/**: Shell scripts for development and testing utilities

## Requirements
- Xcode 16.3 or later
- Swift 6.10 or later
- iOS 18.0+ deployment target
