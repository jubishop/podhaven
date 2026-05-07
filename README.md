# PodHaven - Your Personal Podcast Hub

[![Tests](https://github.com/jubishop/podhaven/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/jubishop/podhaven/actions/workflows/tests.yml?query=branch%3Amain)
[![Swift Version](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Xcode Version](https://img.shields.io/badge/Xcode-26-blue.svg)](https://developer.apple.com/xcode/)
[![Platform](https://img.shields.io/badge/iOS-26-lightblue.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/License-Source%20Available-lightgrey.svg)](LICENSE)

PodHaven is a modern podcast application for iOS, built with Swift and SwiftUI. It provides a clean and intuitive interface for discovering, subscribing to, and listening to your favorite podcasts.

Website: [artisanalsoftware.com/podhaven](https://artisanalsoftware.com/podhaven)

## Features

- **Discover & Search**: Find new podcasts powered by the [iTunes Search API](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/).
- **Trending Podcasts**: Browse top podcasts across 18 genre categories using Apple's rankings.
- **Subscribe & Manage**: Easily subscribe to your favorite podcasts and manage your library.
- **Tags**: Organize podcasts and episodes with custom tags.
- **Episode Playback**: A modern audio player with background playback, lock screen controls, and playback position tracking.
- **Playback Queue**: Manage a queue of upcoming episodes.
- **Download for Offline**: Save episodes to your device to listen without an internet connection.
- **OPML Import/Export**: Import your existing podcast subscriptions from another app, or export your library from PodHaven.
- **Share Extension**: Add new podcasts directly from Safari or other apps using the share sheet.
- **Widgets**: Home screen widgets for quick access to your podcasts.
- **New Episode Notifications**: Get notified when subscribed podcasts publish new episodes, with per-podcast control and rich artwork attachments.
- **Background Refresh**: Automatic feed updates in the background.

## Getting Started

### Prerequisites

- macOS with Xcode 26 or later
- Swift 6.2 or later

### Installation

1.  **Clone the repository:**
    ```sh
    git clone https://github.com/jubishop/podhaven.git
    ```
2.  **Navigate to the project directory:**
    ```sh
    cd podhaven
    ```
3.  **Open the project in Xcode:**
    ```sh
    open PodHaven.xcodeproj
    ```
4.  **Build the project:**
    Press `Cmd+R` in Xcode to build and run the app in the simulator.

## Build & Test Commands

For more advanced users, here are the commands to build and test from the command line.

<details>
<summary>Click to expand Build & Test Commands</summary>

### Build for Testing
```sh
xcodebuild build-for-testing -project PodHaven.xcodeproj -scheme PodHaven -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Run All Tests
Use `Cmd+U` in Xcode, or run the following command in your terminal:
```sh
xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -testPlan PodHaven -parallel-testing-enabled YES
```

### Run a Specific Test Class
```sh
xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PodHavenTests/SomeTestClass
```

### Run an Individual Test Method
```sh
xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PodHavenTests/SomeTestClass/testMethod
```
</details>

## Project Architecture

PodHaven is built using modern Swift practices and a clean, modular architecture.

- **UI Layer:** Built entirely with **SwiftUI** for a declarative and responsive user interface.
- **State Management:** Uses Swift's **Observation** framework (`@Observable`) with **Factory** for dependency injection.
- **Database:** Uses **GRDB.swift** for fast and safe access to the local SQLite database, preferring the QueryInterface API over raw SQL.
- **Networking:** Leverages **URLSession** with the **iTunes Search API** for podcast discovery, and **XMLCoder** for parsing RSS feeds.
- **Image Handling:** **Nuke** for efficient image loading and caching.
- **Concurrency:** Built from the ground up with Swift's modern structured concurrency (`async/await`).
- **Macros:** Custom Swift macros for `ReadableError` conformance and state management.
- **Error Handling:** Structured approach using `ReadableError` protocol and `ErrorKit`, with **Sentry** integration for production error reporting.
- **Logging:** Centralized logging via Apple's `OSLog` with structured file logging and Sentry forwarding.

### Targets

| Target | Description |
|--------|-------------|
| **PodHaven** | Main iOS app |
| **PodhavenShare** | Share extension for adding podcasts from other apps |
| **PodHavenWidget** | Home screen widget extension |
| **PodHavenMacros** | Swift macro compilation target |
| **PodHavenTests** | Parallelized test suite |

### Dependencies

| Package | Purpose |
|---------|---------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database management |
| [XMLCoder](https://github.com/MaxDesiatov/XMLCoder) | RSS feed parsing |
| [Nuke](https://github.com/kean/Nuke) | Image loading and caching |
| [Factory](https://github.com/hmlongco/Factory) | Dependency injection |
| [Tagged](https://github.com/pointfreeco/swift-tagged) | Type-safe identifiers |
| [Sentry](https://github.com/getsentry/sentry-cocoa) | Error reporting and crash analytics |
| [IdentifiedCollections](https://github.com/pointfreeco/swift-identified-collections) | Collection utilities |
| [OrderedCollections](https://github.com/apple/swift-collections) | Foundation collection extensions |
| [Semaphore](https://github.com/groue/Semaphore) | Concurrency utilities |
| [swift-sharing](https://github.com/pointfreeco/swift-sharing) | Shared state management |
| [swift-log](https://github.com/apple/swift-log) | Structured logging |
| [swift-navigation](https://github.com/pointfreeco/swift-navigation) | Navigation utilities |
| [swift-algorithms](https://github.com/apple/swift-algorithms) | Algorithm utilities |

### Testing

Tests use the **Swift Testing** framework with the `@Suite` / `#expect` DSL. The test plan runs all suites in parallel. An in-memory GRDB database (`AppDB.inMemory()`) powers repository tests, and Factory overrides with `.context(.test)` provide test fakes.

## Contributing

Contributions are welcome! If you have a feature request, bug report, or want to contribute to the code, please feel free to open an issue or submit a pull request.

## License

This project is licensed under a **Source Available License**. You are free to view, study, and contribute to the code, but commercial use, redistribution, and derivative works (outside of contributions) are not permitted. See the [LICENSE](LICENSE) file for full details.

Copyright (c) 2026 Justin Bishop. All rights reserved.
