# PodHaven - Your Personal Podcast Hub

[![Swift Version](https://img.shields.io/badge/Swift-6.10-orange.svg)](https://swift.org)
[![Xcode Version](https://img.shields.io/badge/Xcode-16.3-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-Source%20Available-lightgrey.svg)](LICENSE)

PodHaven is a modern podcast application for iOS, built with Swift and SwiftUI. It provides a clean and intuitive interface for discovering, subscribing to, and listening to your favorite podcasts.

## ✨ Features

- **Discover & Search**: Find new podcasts with a powerful search powered by the [PodcastIndex API](https://podcastindex.org/). Search by title, term, or person.
- **Trending Podcasts**: See what's currently popular and discover new shows.
- **Subscribe & Manage**: Easily subscribe to your favorite podcasts and manage your library.
- **Episode Playback**: A modern audio player to listen to episodes.
- **Playback Queue**: Manage a queue of upcoming episodes.
- **Download for Offline**: Save episodes to your device to listen without an internet connection.
- **OPML Import/Export**: Import your existing podcast subscriptions from another app, or export your library from PodHaven.
- **Share Extension**: Add new podcasts directly from Safari or other apps using the share sheet.
- **Built with SwiftUI**: A modern, responsive interface built entirely with SwiftUI.

## 📸 Screenshots

*Coming soon.*

## 🚀 Getting Started

Follow these instructions to get the project up and running on your local machine for development and testing purposes.

### Prerequisites

- macOS with Xcode 16.3 or later
- Swift 6.10 or later

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

## 🛠️ Build & Test Commands

For more advanced users, here are the commands to build and test from the command line.

<details>
<summary>Click to expand Build & Test Commands</summary>

### Build from Terminal
```sh
xcodebuild -project PodHaven.xcodeproj -scheme PodHaven -configuration Debug build
```

### Run All Tests
Use `Cmd+U` in Xcode, or run the following command in your terminal:
```sh
xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven
```

### Run a Specific Test Class
```sh
xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven -only-testing:PodHavenTests/[TestClassName]
```

### Run an Individual Test Method
```sh
xcodebuild test -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven -only-testing:PodHavenTests/[TestClassName]/[testMethodName]
```
</details>

## 🏛️ Project Architecture

PodHaven is built using modern Swift practices and a clean, modular architecture.

- **UI Layer:** Built with **SwiftUI** for a declarative and responsive user interface.
- **Database:** Uses **GRDB.swift** for fast and safe access to the local SQLite database.
- **Networking:** Leverages **URLSession** for network requests, with **XMLCoder** for parsing podcast RSS feeds.
- **Image Handling:** **Nuke** is used for efficient image loading and caching.
- **Dependency Injection:** **Factory** provides a clean way to manage dependencies throughout the app.
- **Concurrency:** Built from the ground up with Swift's modern concurrency features (`async/await`).

### Dependencies

- [GRDB.swift](https://github.com/groue/GRDB.swift) - Database management
- [XMLCoder](https://github.com/MaxDesiatov/XMLCoder) - RSS feed parsing
- [Nuke](https://github.com/kean/Nuke) - Image loading and caching
- [Factory](https://github.com/hmlongco/Factory) - Dependency injection
- [Tagged](https://github.com/pointfreeco/swift-tagged) - Type-safe identifiers
- [Sentry](https://github.com/getsentry/sentry-cocoa) - Error reporting
- [IdentifiedCollections](https://github.com/pointfreeco/swift-identified-collections) - Collection utilities
- [OrderedCollections](https://github.com/apple/swift-collections) - Foundation collection extensions
- [Semaphore](https://github.com/groue/Semaphore) - Concurrency utilities

## 👨‍💻 Development Practices

<details>
<summary>Click to expand Development Practices</summary>

### Code Style
- **File Organization**: Each top-level type in its own file.
- **Naming Conventions**: `PascalCase` for types, `camelCase` for functions/variables.
- **Section Markers**: Use `// MARK: - Section Name` for organization.
- **Copyright**: All files must include a "Copyright Justin Bishop, 2026" header.

### Error Handling
- A structured approach using `ReadableError` and `CatchingError` protocols to ensure all errors are handled gracefully.

### Logging
- A centralized logging system built on top of Apple's `OSLog` and integrated with `Sentry` for production builds.

</details>

## 🙌 Contributing

Contributions are welcome! If you have a feature request, bug report, or want to contribute to the code, please feel free to open an issue or submit a pull request.

## 📄 License

This project is licensed under a **Source Available License**. You are free to view, study, and contribute to the code, but commercial use, redistribution, and derivative works (outside of contributions) are not permitted. See the [LICENSE](LICENSE) file for full details.

Copyright (c) 2026 Justin Bishop. All rights reserved.