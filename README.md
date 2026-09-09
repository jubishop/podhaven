# PodHaven - Your Personal Podcast Hub

[![Swift Tests](https://github.com/jubishop/podhaven/actions/workflows/swift-tests.yml/badge.svg?branch=main)](https://github.com/jubishop/podhaven/actions/workflows/swift-tests.yml?query=branch%3Amain)
[![Python Tests](https://github.com/jubishop/podhaven/actions/workflows/python-tests.yml/badge.svg?branch=main)](https://github.com/jubishop/podhaven/actions/workflows/python-tests.yml?query=branch%3Amain)
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

For repository knowledge and tooling, use `bin/check --documents-only` after
a batch of Markdown edits and `bin/check` for fast static checks. Run
`bin/check --full` after setup or foundation changes, and before a tooling PR
or release. CI runs the full tooling suite. These commands do not build the
Swift app. See the [development workflow](docs/development-workflow.md).

<details>
<summary>Click to expand Build & Test Commands</summary>

### Build for Testing
```sh
xcodebuild build-for-testing -hideShellScriptEnvironment -project PodHaven.xcodeproj -scheme PodHaven -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Run All Tests
Use `Cmd+U` in Xcode, or run the following command in your terminal:
```sh
xcodebuild test -hideShellScriptEnvironment -project PodHaven.xcodeproj -scheme PodHaven -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -testPlan PodHaven -parallel-testing-enabled YES
```

### Run a Specific Test Suite
Swift Testing filters must stay at suite level; method-level filters can report success while
running zero tests.
```sh
xcodebuild test -hideShellScriptEnvironment -project PodHaven.xcodeproj -scheme PodHaven -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PodHavenTests/SomeSuite
```
</details>

## App Version and TestFlight

Print the current app version:

```sh
bin/version
```

Set the next app version across all targets and build configurations:

```sh
bin/version 1.0.1
```

This changes the app version (`MARKETING_VERSION`). The command rejects invalid
or older versions. Use `bin/version --help` for usage.

Commit your changes, then test, archive, and upload a build:

```sh
bin/shipit
```

To also distribute that build to the external Everyone group, supply TestFlight
"What to Test" notes:

```sh
bin/shipit --notes "Improved playback reliability."
```

With `--notes`, the command checks the existing external Everyone group before
building. After upload, it checks processing every 30 seconds for up to 30 minutes,
adds the notes, submits for beta review when needed, and verifies the group
assignment. Testers are notified when Apple makes the build available. Apple beta
review can remain pending after the command finishes. Notes must be nonblank and
at most 4000 bytes.

If processing times out or distribution fails after upload, rerun the same command
from the same clean commit. It reuses the uploaded build. You can also use
`--notes` after an upload-only run of that commit. A single local upload receipt
in Git's metadata directory supports retries; each new upload replaces it.

`bin/shipit` increments the build number automatically. If Apple closes a version
for external beta review, use `bin/version` to set a higher app version, commit it,
and upload a new build. Successful runs also publish the Git tag and GitHub
release and mirror the branch and tag to SourceHut. The existing generated GitHub
release summary remains separate from the supplied TestFlight notes.

Other options:

| Option | Behavior |
| --- | --- |
| `-h`, `--help` | Show usage without building or uploading. |
| `-f`, `--force` | Allow a branch other than `main`. A clean working tree is still required. |
| `--api-key PATH --api-key-id ID --api-issuer-id ID` | Authenticate with an App Store Connect API key. Supply all three options together. |

The API key options can also be set with `ASC_KEY_PATH`, `ASC_KEY_ID`, and
`ASC_ISSUER_ID`. Keep private keys outside the repository. Without a key, uploads
use Xcode's Apple ID login. Distribution uses Fastlane's own Apple ID login and
may request two-factor authentication; `FASTLANE_USER` selects the Apple ID.
An App Manager or Admin role is needed for external distribution. Fastlane is
required only with `--notes`; install it with `brew install fastlane`.

`bin/shipit` and `bin/deploy.sh` are aliases and accept the same options.

## App Store Releases

Release the next minor version with notes from the latest TestFlight build:

```sh
bin/appstore
```

The command requires clean `main`. It increments the minor version (`2.1.2`
becomes `2.2`), commits and pushes the version change, tests, archives, uploads,
waits for that exact build to finish processing, and submits for App Review.
Apple releases it automatically after approval.

Override the release number or public "What's New" notes when needed:

```sh
bin/appstore --notes "Improved playback reliability."
bin/appstore --release 3 --notes "A new major release."
```

`--release` must be strictly greater than the current version and have zero or
one dot. Without `--notes`, the command copies notes from the latest iOS build
with a two-dot TestFlight version. It uses the app's primary language or `en-US`
and stops if the latest build has no usable notes. Public notes must contain
1 to 4000 characters and are used for every existing listing language.

Show the live version, pending versions and reviews, and uploaded builds for the
current local app version without releasing:

```sh
bin/appstore --status
```

To submit an exact existing build, use `--release VERSION --build NUMBER`.
This skips the version change and upload. The build must match that version.

The description, screenshots, and other listing metadata carry over. Only the
build, release setting, and "What's New" text are updated. The command verifies
Apple's saved build, notes, release setting, and submission state before
reporting success. It does not wait for Apple to complete App Review.

The build must be App Store eligible with export compliance already complete.
Apple can still require changes to listing or review information before accepting
a submission; the command reports those errors.

If a run stops, use `bin/appstore --status` to inspect the state, then retry the
same command. It retains the chosen version, notes, and exact build across
retries, including after a failed version push. See
[Versioning and releases](docs/releases.md) for the complete workflow and retry rules.

Fastlane is required (`brew install fastlane`). Authentication uses the same
`--api-key`, `--api-key-id`, and `--api-issuer-id` options and `ASC_*` environment
variables described above. Without a key, it uses Fastlane's Apple ID login.
Use `bin/appstore --help` for all options.

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
