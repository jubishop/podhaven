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

## Code Style Guidelines

- File organization: Group related functionality in subfolders with descriptive names
- Imports: Import only what's needed, organize by framework then project imports
- Copyright header: Include "Copyright Justin Bishop, 2025" at file start
- Type names: PascalCase (e.g., `PodcastFeed`, `EpisodeViewModel`)
- Variables/functions: camelCase (e.g., `feedURL`, `makeMigrator()`)
- Section markers: Use `// MARK: - Section Name` for code organization
- Tagged types: Use for type-safe identifiers (e.g., `Podcast.ID`, `GUID`, `MediaURL`)
- Error handling: Use custom `Err` enum, with descriptive error messages
- Test naming: Descriptive (`testHTMLRegexes`), use #expect for assertions
- Concurrency: Use Swift concurrency (async/await) with proper error handling