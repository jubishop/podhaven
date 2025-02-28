# PodHaven Development Guidelines

## Build & Test Commands
- Open in Xcode: `open PodHaven.xcodeproj`
- Run all tests: `xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven`
- Run single test: `xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven -only-testing:PodHavenTests/[TestClassName]/[testMethodName]`
- In Xcode UI: Use ⌘6 to open Test Navigator, click diamond icon next to test to run it

## Code Style
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