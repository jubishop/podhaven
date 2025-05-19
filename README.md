# PodHaven - Podcast App

PodHaven is a Swift-based podcast application that allows users to discover, subscribe to, and listen to podcasts.

## Project Requirements

- Xcode 16.1 or later
- macOS 13.0 or later
- Swift 5.10 or later

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
- GRDB: Database management
- XMLCoder: For parsing podcast RSS feeds
- Nuke/NukeUI: Image loading and caching
- Factory: Dependency injection
- Tagged: Type-safe identifiers
- Sentry: Error reporting (Production builds only)
- IdentifiedCollections: Collection utilities
- OrderedCollections: Foundation collection extensions
- Semaphore: Concurrency utilities

## Dependency Injection

PodHaven uses the Factory package for dependency injection:
- Use `@LazyInjected` macro in classes (e.g., `@LazyInjected private var repo: Repository`)
- Only use `Container.shared` directly in protocols where `@LazyInjected` cannot be used
- Each ViewModel should have an `execute()` function in the Initialization section

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