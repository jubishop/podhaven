---
status: current
---

# CarPlay scene lifecycle

CarPlay uses its own `CPTemplateApplicationScene`. Its `CarPlaySceneDelegate`
conforms to `CPTemplateApplicationSceneDelegate`.
The phone continues to use the SwiftUI `WindowGroup`. Automatic scene-manifest
generation overwrites the source manifest with an empty configuration map,
so it is disabled in all three build configurations. The source manifest
preserves the generated `UIApplicationSupportsMultipleScenes = true` value
and adds the CarPlay role. SwiftUI still provides the phone scene at runtime;
no phone scene delegate is replaced.

`PhoneSceneView` reads `scenePhase` inside the phone view. Reading it at the
`App` level would aggregate all scenes and could treat an active CarPlay scene
as phone foreground activity. See [SwiftUI ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase).

## Startup and ownership

`AppLauncher.bootstrap()` initializes the existing database and registers
the shared remote-command pipeline before scene connection. CarPlay installs
its native tab root directly in the connect callback. It then calls
`prepareForBrowsing()`, which starts the existing once-only `StateManager`
observers for queue, tags, and Smart Lists.

Browsing does not call `prepareForPlayback()` or `prepareForForeground()`.
It does not restore a saved media asset, activate audio, resume playback,
change the phone scene phase, request notification permission, or start
recommendation or transcription work. Playback and foreground startup keep
their existing application-owned `AsyncOnce` tasks. Concurrent callers share
those tasks; cancellation of a caller does not cancel application startup.

Each system-created scene delegate retains its own container-built
`CarPlayCoordinator`. A connection retains the interface controller and its
root. Duplicate connect notifications for the same active controller do
nothing. Disconnect clears row handlers and releases the connection. A new
connection has a new identity even when it reuses the controller. Root
completions check both connection and root identity before changing presentation.
Retry callbacks check connection identity; replacing the root clears its old
handlers. An old disconnect cannot release a newer controller.

This foundation has no connection-owned asynchronous tasks or data observers.
The root uses native placeholders. Queue, artwork, selection, and navigation
work belong to subsequent CarPlay issues and must adopt the same connection
lifetime. Shared data observers and the player outlive a CarPlay disconnect.

If root installation fails, the coordinator logs the failure and attempts a
three-tab error root with native Retry rows. Retry starts a new root attempt.
If the error root is also rejected, it logs that failure without looping;
reconnection starts a fresh attempt. No error path depends on a phone alert.

## Protected storage audit

Ordinary locked use means the user has unlocked the device at least once
since restart. Apple's default file protection permits access after that
first unlock, including after the device locks again. This does not grant
access before the first unlock. See [Encrypting your app's files](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files)
and [completeUntilFirstUserAuthentication](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication).

The source audit covers the storage actually used by startup and playback:

| Storage | Creation and access | Protection behavior |
| --- | --- | --- |
| `AppInfo.documentsDirectory/db.sqlite` | `AppDB._onDisk` opens a GRDB `DatabasePool` during bootstrap, before any scene callback. | Neither AppDB nor its GRDB configuration overrides file protection. Opening and migration are synchronous; an inaccessible database is currently fatal. |
| `db.sqlite-wal` and `db.sqlite-shm` | SQLite creates and manages the sidecars for the same database. | No app protection override. Verify both sidecars on hardware with the database, including a cold reopen. |
| `AppInfo.applicationSupportDirectory/episodes` | `CacheManager` creates the directory; `CacheFileStore` moves URLSession downloads into it. Playback reads through the existing cache path. | No protection override or broad directory rewrite. A move can preserve the downloaded file's attributes, so inspect an actual downloaded file on hardware. |
| Standard defaults | `UserDefaults.standard` stores the current episode ID and user settings. | No keychain or custom protected-file layer is involved. |
| App-group defaults and widget snapshots | Existing app-group `UserDefaults` and `FileManaging` writes. | No protection override; CarPlay does not add another settings store or start the widget writer merely to browse. |

The entitlement file has no default-data-protection override. This change
does not lower protection or rewrite existing files. The audit found no
demonstrated need for such a change. A delegate-only protected-data guard
would not fix a bootstrap database failure, so none is added.

Simulator and My Mac evidence cannot establish the protection class or locked
access of an installed iPhone's existing files. Issue #631 owns real-device
acceptance: record the actual database, both sidecars, a downloaded audio
file, and required settings access on a cold launch after first unlock and
relock. Record before-first-unlock restrictions separately. If an existing
file is found to have stronger protection that blocks ordinary locked use,
address that specific path before claiming device acceptance.

## Graphical and behavioral verification

`CarPlaySceneTests` checks the built scene manifest and uses a fake at the
`CPInterfaceController` boundary. Production coordinator logic constructs
real `CPTabBarTemplate`, `CPListTemplate`, and `CPListItem` objects in tests.
Coverage includes cold connection, pending and failed restoration,
simultaneous readiness, paused and playing episodes, duplicate connections,
disconnect before completion, reuse of the same controller, release of the
controller, and failure/retry cleanup.

The Xcode previews show shared titles, icons, placeholder copy, and retry
content with no database or network dependencies. They are content fixtures:
CarPlay owns native template rendering and cannot embed that renderer in a
SwiftUI preview. Actual template layout, tab order, empty views, phone scene
launch, and reconnect must also be inspected in Simulator. Locked access and
vehicle audio behavior remain real-device checks in #631.
