# PodHaven - Podcast App

PodHaven is a Swift-based podcast application that allows users to discover, subscribe to, and listen to podcasts.

## Project Requirements

- Xcode 16.3 or later
- Swift 6.10 or later

## Build & Test Commands

### Setup & Build
- Clone the repository: `git clone https://github.com/jubishop/podhaven.git`
- Navigate to project: `cd podhaven`
- Open in Xcode: `open PodHaven.xcodeproj`
- Build with Xcode: Run the project using Xcode's Run button (⌘R)
- Build from terminal: 
  ```
  xcodebuild -project PodHaven.xcodeproj -scheme PodHaven -configuration Debug build
  ```

### Testing
- Run all tests in Xcode: Use ⌘U or Product > Test
- Run all tests from terminal: 
  ```
  xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven
  ```
- Run specific test class:
  ```
  xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven -only-testing:PodHavenTests/[TestClassName]
  ```
- Run individual test method:
  ```
  xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven -only-testing:PodHavenTests/[TestClassName]/[testMethodName]
  ```
- In Xcode UI: Use ⌘6 to open Test Navigator, click diamond icon next to test to run it

## Project Architecture

PodHaven uses Swift and SwiftUI for the UI layer with the following dependencies:
- [GRDB](https://github.com/groue/GRDB.swift): Database management
- [XMLCoder](https://github.com/MaxDesiatov/XMLCoder): For parsing podcast RSS feeds
- [Nuke/NukeUI](https://github.com/kean/Nuke): Image loading and caching
- [Factory](https://github.com/hmlongco/Factory): Dependency injection
- [Tagged](https://github.com/pointfreeco/swift-tagged): Type-safe identifiers
- [Sentry](https://github.com/getsentry/sentry-cocoa): Error reporting (Production builds only)
- [IdentifiedCollections](https://github.com/pointfreeco/swift-identified-collections): Collection utilities
- [OrderedCollections](https://github.com/apple/swift-collections): Foundation collection extensions
- [Semaphore](https://github.com/groue/Semaphore): Concurrency utilities

## PodcastIndex Integration

PodHaven integrates with the [PodcastIndex API](https://podcastindex.org/) for podcast discovery and search functionality:

### API Integration
- Uses RESTful API calls to PodcastIndex.org endpoints
- Authenticated with API key and SHA-1 hashed authorization headers
- Custom URLSession configuration for efficient network requests

### Search Features
- **Term Search**: Find podcasts matching general query terms
- **Title Search**: Search specifically for podcasts by title (with similar results option)
- **Person Search**: Discover podcasts by host or guest name
- **Trending**: Get currently trending podcasts with optional category filtering

### Search Result Models
- Uses domain-specific models that conform to `FeedResultConvertible` and `PodcastResultConvertible` protocols
- Converts API responses into app-specific data structures (`TermResult`, `TitleResult`, `PersonResult`, `TrendingResult`)
- Handles parsing with proper error handling through `SearchError` types

## Dependency Injection

PodHaven uses the FactoryKit package for dependency injection:
- Use `@DynamicInjected` macro in ViewModels for cached dependencies (e.g., `@ObservationIgnored @DynamicInjected(\.repo) private var repo`)
- Use `@InjectedObservable` for observable dependencies in Views (e.g., `@InjectedObservable(\.navigation) private var navigation`)
- Use `@LazyInjected` only for dependencies with `.scope(.unique)` instead of `.scope(.cached)`
- Only use `Container.shared` directly when necessary for actor-isolated properties or in protocols
- Each ViewModel should have an `execute()` function in the Initialization section

### Testing with FactoryKit

Tests utilize the FactoryKit and FactoryTesting packages:
- Mark test suites with `@Suite(..., .container)` to enable container-based dependency injection
- The Container extension implements `AutoRegistering` to override dependencies for testing
- Use `context(.test)` to register test mocks (e.g., `.context(.test) { DataFetchableMock() }.scope(.cached)`)
- In test classes, use `@DynamicInjected` and `@LazyInjected` to access dependencies, following the same patterns as production code

## Error Handling

PodHaven uses a structured approach to error handling:

### Error Protocols
- `ReadableError`: Base protocol for all domain errors, providing readable error messages
- `CatchingError`: Protocol for errors that can catch and transform other errors

### Error Implementation
1. Define domain-specific error enums that conform to `ReadableError`:
   ```swift
   enum SearchError: ReadableError {
     case noResults
     case networkFailure(String)
   }
   ```

2. For errors that need to wrap other errors, also conform to `CatchingError`:
   ```swift
   enum FeedError: ReadableError, CatchingError {
     case invalidURL
     case parsingFailure(String)
     case wrapped(Error)
     
     static func caught(_ error: Error) -> Self {
       .wrapped(error)
     }
   }
   ```

3. Use the `catch` method to automatically wrap errors:
   ```swift
   func fetchFeed() async throws(FeedError) -> Feed {
     try await FeedError.catch {
       // Code that may throw other error types
     }
   }
   ```

4. Use `ErrorKit` utilities for logging and presenting errors

## Logging

PodHaven uses a structured logging system:

### Components
- Uses Apple's `OSLog` for system-level logging
- Integrates with `Sentry` for error reporting in production builds
- Custom `LogLevel` enum with debug, info, warning, critical levels

### Usage

1. Conform types to `LogCategorizable` to define subsystem, category and level:
   ```swift
   extension YourType: LogCategorizable {
     static let subsystem = "com.jubishop.PodHaven"
     static let category = "YourCategory"
     static let level: LogLevel = .info
   }
   ```

2. Initialize and use the Log structure:
   ```swift
   private let log = Log(as: Self.self)
   
   func someFunction() {
     log.debug("Debug message")
     log.info("Info message")
     log.warning("Warning message")
     log.critical("Critical message")
   }
   ```

3. Critical errors are automatically reported to Sentry in production builds

## Code Style Guidelines

- File organization: Each top-level type should be in its own file with the same name
- Imports: Import only what's needed, organize by framework then project imports
- Copyright header: Include "Copyright Justin Bishop, 2025" at file start
- Type names: PascalCase (e.g., `PodcastFeed`, `EpisodeViewModel`)
- Variables/functions: camelCase (e.g., `feedURL`, `makeMigrator()`)
- Section markers: Use `// MARK: - Section Name` for code organization (only for major sections)
- Tagged types: Use for type-safe identifiers (e.g., `Podcast.ID`, `GUID`, `MediaURL`)
- Protocol conformances: List in alphabetical order
- Protocol attributes: Sort alphabetically, followed by a line of whitespace, then functions
- Database operations: Use GRDB's query builder APIs rather than raw SQL
- Concurrency: Use Swift concurrency (async/await) with proper error handling
- Test naming: Descriptive (`testHTMLRegexes`), use #expect for assertions