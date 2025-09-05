# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## GIT

- **IMPORTANT: Unless explicitly asked don't git commit your changes.**

## Essential Build & Test Commands

### Building
- **IMPORTANT: Don't try to build the project unless explicitly asked.**

### Testing
- **IMPORTANT: Don't try to run the tests unless explicitly asked.**

**IMPORTANT: If you do try to build or test: use the MCP Tools build_macos and test_macos**

## Core Architecture

### Database Layer (GRDB)
- **Schema Management**: Database migrations in `PodHaven/Database/Schema.swift` with versioned incremental changes
- **Model Architecture**: Separation between `UnsavedX` (data) and `X` (domain) using `@Saved` macro from local `PodHavenMacros` package
- **Repository Pattern**: Central `Repo` class handles all database operations with type-safe query building
- **Type Safety**: Use `Tagged` types for identifiers (`Podcast.ID`, `Episode.ID`, `GUID`, `MediaURL`)
- **Persistence Framework**: GRDB provides robust SQLite access with query builder APIs
- **Transaction Safety**: Database operations use GRDB transactions for atomicity

### Dependency Injection (FactoryKit)
- **ViewModels**: Use `@DynamicInjected(\.repo)` for cached dependencies
- **Views**: Use `@InjectedObservable(\.navigation)` for observable dependencies
- **Testing**: Mark test suites with `@Suite(..., .container)` and use `.context(.test)` for mocks
- **Context-Aware Registration**: Use `context(.preview)` and `context(.test)` for environment-specific implementations
- **Factory Scopes**: `.scope(.cached)` for singleton-like behavior

### Concurrency Architecture
- **Async Streams**: Reactive data flows using `AsyncStream` for real-time updates
- **Task Management**: Proper task cancellation and lifecycle handling with structured concurrency

### Error Handling
- **Domain Errors**: Create enums conforming to `ReadableError` protocol
- **Error Wrapping**: Use `CatchingError` protocol for errors that wrap others
- **Error Catching**: Use `ErrorType.catch { }` pattern for automatic wrapping
- **Logging Integration**: Use `ErrorKit` utilities for error presentation and logging
- **ReadableError Macro**: Custom Swift macro for streamlined error handling with readable messages

### Logging System
- **Centralized Configuration**: Configured in `PodHavenApp.swift` using `LoggingSystem.bootstrap`
- **Environment Handlers**: Different log handlers based on app environment:
  - TestFlight/iPhone/Mac: `OSLogHandler`, `FileLogHandler`, `CrashReportHandler` via `MultiplexLogHandler`
  - Preview: `PrintLogHandler` only
  - Simulator/Testing: `OSLogHandler` only
  - AppStore: Uses SwiftLogNoOpLogHandler for production builds
- **Structured Logging**: NDJSON format file logs with level, timestamp, metadata
- **Usage**: Use `LogCategorizable` protocol with subsystem/category/level definitions

### State Management
- **Observable Classes**: Use `@Observable` for reactive view state management
- **Shared State**: Point-Free's `Sharing` library for persistent state (avoid `UserDefaults` directly)
- **Navigation**: Centralized `Navigation` class with tab-based routing using SwiftNavigation
- **Custom Alert & Sheet Systems**: Standardized alert and sheet presentation with type-safe models
- **Observable Patterns**: `@InjectedObservable` for dependency-injected observable state
- **Stateful View Models**: Separation of business logic from view rendering

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
- **FactoryKit**: Modern dependency injection with comprehensive testing support
- **FactoryTesting**: Extensions for test-specific dependency injection
- **Tagged**: Type-safe identifiers preventing ID confusion
- **Sentry**: Error reporting in production builds only
- **Point-Free Libraries**: SwiftNavigation, Sharing, IdentifiedCollections for reactive state
- **Logging**: Swift-log integration for structured logging
- **OrderedCollections**: Foundation collection extensions for specialized data structures
- **Semaphore**: Concurrency utilities for coordination

### Testing Patterns
- **Swift Testing**: Use `#expect` for assertions in comprehensive test suites
- **Fake Implementations**: Complete fake implementations for external dependencies
- **Container Override**: Test-specific dependency injection with FactoryKit Container
- **In-Memory Database**: Fast tests using GRDB in-memory instances
- **Parallel Execution**: Separate test targets for parallel vs. performance tests
- **Suite Annotation**: Use `@Suite("description", .container)` to enable DI in test suites
- **Test Creation Helpers**: Utility functions like `Create.unsavedPodcast()` for test data
- **Explicit Test Steps**: Clear, numbered test steps with meaningful assertions
- **Avoid Sleep**: Prefer structured async testing over sleep-based tests.  Use `Sleeper`.

### Code Safety & Style
- **Optionals**: Never use `!` to force unwrap optionals in production code
- **Concurrency**: Use Swift concurrency (async/await) with proper cancellation
- **String Formatting**: Use `"""` delimiters for long strings exceeding 100 columns
- **Naming**: PascalCase types, camelCase variables/functions
- **Protocol Conformances**: List alphabetically with attributes sorted
- **MARK Comments**: Use `// MARK: - Section Name` for code organization
- **Self Usage**: Explicit `self` only when required by the compiler
- **Assert Usage**: Use `Assert.fatal()`, and `Assert.precondition()`.
- **Error Handling**: Always use structured error handling with domain-specific types

### Specialized Files
- **Schema.swift**: Contains all database migration logic with detailed change tracking
- **Local Package**: `PodHavenMacros` provides `@Saved` and `@ReadableError` macros
- **Share Extension**: `PodHavenShare` handles external podcast URL sharing

### Code Formatting
- **IMPORTANT: Run swift-format on any files you change**

## External Project Structure

### PodHavenTests/ (Test Suite)
- Parallel execution test suite using Swift Testing framework
- Test targets: `ParallelTests` and `PerformanceTests`
- Mock implementations and test data creation helpers
- Comprehensive coverage of managers, models, and business logic

### PodHavenMacros/ (Swift Package)
- Custom Swift macros for domain-specific functionality
- `@Saved` macro for model wrapper pattern
- `@ReadableError` macro for error handling
- Uses SwiftSyntax for macro implementation

### PodHavenShare/ (App Extension)
- iOS share extension for handling external podcast URLs
- Processes shared URLs and integrates with main app
- Minimal UI for quick podcast subscription
