# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## GIT

- **IMPORTANT: Unless explicitly asked don't git commit your changes.**

## Essential Build & Test Commands

### Building
- Build from terminal: `xcodebuild -project PodHaven.xcodeproj -scheme PodHaven -configuration Debug build`
- **IMPORTANT: Don't try to build the project unless explicitly asked.**

### Testing
- Run all tests: `xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven`
- Run specific test class: `xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven -only-testing:PodHavenTests/[TestClassName]`
- Run individual test: `xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven -only-testing:PodHavenTests/[TestClassName]/[testMethodName]`
- **IMPORTANT: Don't try to run the tests unless explicitly asked.**

**IMPORTANT: If you do try to build or test: use the MCP Tools build_macos and test_macos**

### Utilities
- Repeat failing tests: `Tools/run_test_until_failure.sh [testMethodName]`
- RSS validation: `Tools/validate_rss.rb [rss_file]`

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
- **Unique Scope**: Use `@LazyInjected` only for `.scope(.unique)` dependencies
- **Testing**: Mark test suites with `@Suite(..., .container)` and use `.context(.test)` for mocks
- **Context-Aware Registration**: Use `context(.preview)` and `context(.test)` for environment-specific implementations
- **Factory Scopes**: `.scope(.cached)` for singleton-like behavior, `.scope(.unique)` for new instances

### Concurrency Architecture
- **Actors**: Thread-safe managers using Swift actors (`PlayManager`, `FeedManager`, `RefreshManager`)
- **PlayActor**: Custom global actor for audio playback isolation (`@PlayActor`)
- **Async Streams**: Reactive data flows using `AsyncStream` for real-time updates
- **System Integration**: Uses dependency-injected notification handling for system events
- **Task Management**: Proper task cancellation and lifecycle handling with structured concurrency
- **Error Propagation**: Type-safe error handling with specialized `throw`/`catch` patterns

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
- Dedicated URL session configuration for search operations
- Secure API key handling with SHA-1 authorization hash

#### Queue System
- Complex episode queuing with precise position management
- Database transactions ensure atomic operations for queue modifications
- SQL-optimized operations for high-performance queue manipulation
- Flexible queue position management (unshift, insert, replace, dequeue)
- Last-queued timestamp tracking for history preservation

#### CacheManager (Actor)
- Episode audio file caching and management
- Handles download progress tracking and storage
- Automatic cache cleanup based on storage policies
- Supports both individual and bulk episode caching

#### RefreshManager (Actor)
- Automated RSS feed refresh scheduling
- Handles background updates for subscribed podcasts
- Manages refresh intervals and failure retry logic
- Coordinates with FeedManager for bulk operations

#### ShareService
- Handles incoming podcast URL sharing from external apps
- Deep link processing for podcast discovery
- Integration with iOS share extension functionality
- URL validation and feed auto-subscription

### Error Handling
- **Domain Errors**: Create enums conforming to `ReadableError` protocol
- **Error Wrapping**: Use `CatchingError` protocol for errors that wrap others
- **Error Catching**: Use `ErrorType.catch { }` pattern for automatic wrapping
- **Logging Integration**: Use `ErrorKit` utilities for error presentation and logging
- **ReadableError Macro**: Custom Swift macro for streamlined error handling with readable messages
- **Specialized Error Types**: Domain-specific error types (CacheError, FeedError, PlaybackError, etc.)

### Logging System
- **Centralized Configuration**: Configured in `PodHavenApp.swift` using `LoggingSystem.bootstrap`
- **Environment Handlers**: Different log handlers based on app environment:
  - iPhone: `OSLogHandler`, `FileLogHandler`, `CrashReportHandler` via `MultiplexLogHandler`
  - Preview: `PrintLogHandler` only
  - Simulator/Mac/AppStore: `OSLogHandler` only
  - Testing: Configured for OSLogHandler only
  - AppStore: Uses SwiftLogNoOpLogHandler for production builds
- **Structured Logging**: NDJSON format file logs with level, timestamp, metadata
- **Usage**: Use `LogCategorizable` protocol with subsystem/category/level definitions
- **Custom Log Handlers**: Specialized handlers for different outputs (console, file, crash reports)
- **Environment-Specific Logging**: Appropriate verbosity based on app environment

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
- **Avoid Sleep**: Prefer structured async testing over sleep-based tests

### Code Safety & Style
- **Optionals**: Never use `!` to force unwrap optionals in production code
- **Concurrency**: Use Swift concurrency (async/await) with proper cancellation
- **String Formatting**: Use `"""` delimiters for long strings exceeding 100 columns
- **Naming**: PascalCase types, camelCase variables/functions
- **Protocol Conformances**: List alphabetically with attributes sorted
- **MARK Comments**: Use `// MARK: - Section Name` for code organization
- **Self Usage**: Explicit `self` only when required by the compiler
- **Assert Usage**: Use `Assert.fatal()` for unrecoverable errors, not standard `assert()`
- **Error Handling**: Always use structured error handling with domain-specific types

### Specialized Files
- **Schema.swift**: Contains all database migration logic with detailed change tracking
- **AGENTS.md**: Identical to CLAUDE.md for AI coding assistant guidance
- **Local Package**: `PodHavenMacros` provides `@Saved` and `@ReadableError` macros
- **Share Extension**: `PodHavenShare` handles external podcast URL sharing

### Code Formatting
- Run swift-format on any files you change

## Detailed Project Structure

### PodHaven/ (Main App)
- **Cache/**: Episode file caching and download management
- **Database/**: GRDB models, repository pattern, schema migrations
  - **Models/**: Domain models with `@Saved` wrapper pattern
  - **Protocols/**: Database access protocols and displayable interfaces
- **Environment/**: App-wide state management (Navigation, Alert, Sheet, etc.)
- **Errors/**: Domain-specific error types with readable messages
- **Extensions/**: Type extensions for enhanced functionality
- **Feed/**: RSS feed parsing, management, and refresh coordination
- **Logging/**: Structured logging system with multiple handlers
- **Play/**: Audio playback management with AVPlayer integration
  - **Extensions/**: AVPlayer and MediaPlayer framework extensions
  - **Models/**: Playback state and episode asset models
  - **Protocols/**: Audio playback abstraction protocols
  - **Utility/**: Command center, interruption handling, audio utilities
- **Search/**: PodcastIndex API integration and search functionality
- **Share/**: URL sharing and deep linking support
- **UseCases/**: Business logic use cases and selectable list patterns
- **Utility/**: Helper utilities and general-purpose functions
- **Views/**: SwiftUI views organized by feature
  - **Components/**: Reusable UI components
  - **Episodes/**: Episode-related views and view models
  - **Play Bar/**: Playback control interface
  - **Podcasts/**: Podcast management and display views
  - **Search/**: Search interface and trending discovery
  - **Settings/**: App settings and OPML import/export
  - **UpNext/**: Queue management interface
  - **ViewModifiers/**: Reusable view modifiers for common patterns

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

### Tools/
- Shell scripts for development and testing utilities
- Test automation and RSS feed validation

## Requirements
- Xcode 16.3 or later
- Swift 6.10 or later
- iOS 18.0+ deployment target
- macOS 15.0+ for development and macros
