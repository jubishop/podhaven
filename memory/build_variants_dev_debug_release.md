---
name: build-variants-dev-debug-release
description: PodHaven's three app build variants — Development (.dev), Debug (.debug), Release (production) — their bundle IDs, isolated on-disk data directories, which scheme action builds each, and how runtime environment (separate axis) drives logging.
type: reference
---

# Build variants: Development / Debug / Release

The `PodHaven` Xcode scheme has three build configurations. Each produces a
distinct app with its own bundle ID and its own on-disk data directory, so the
variants never share a database.

| Config | Scheme action | Bundle ID | Data dir under `Documents/` |
|---|---|---|---|
| `Development` | Run | `com.artisanalsoftware.PodHaven.dev` | `PodHavenDev/` |
| `Debug` | Test | `com.artisanalsoftware.PodHaven.debug` | `PodHavenDebug/` |
| `Release` | Profile + Archive | `com.artisanalsoftware.PodHaven` | `Documents/` (root) |

- **Development / `.dev`** — the everyday build @jubishop runs (the scheme's Run action), in the Simulator. Its SQLite DB is `Documents/PodHavenDev/db.sqlite`.
- **Debug / `.debug`** — the bundle ID used when the **Test** action runs (it hosts the `PodHavenTests` target). The app is not launched manually under this variant; in practice its `PodHavenDebug/` data dir stays empty.
- **Release / production** — what ships to TestFlight and the App Store, and what runs on @jubishop's iPhone. Uses root `Documents/db.sqlite` with no subdirectory (the code comment: "preserve existing data"). Bundle ID has no suffix.

`AppInfo.dataDirectoryName` keys off the bundle ID to pick the subdirectory; the production bundle ID returns `nil` → root `Documents`. Widget/share extensions follow the same suffixing (`<bundleID>.PodHavenWidget`, `.PodHavenShare`), with per-variant app groups `group.podhaven.shared[.dev|.debug]`.

## Runtime environment is a separate axis

`AppInfo.environment` (`EnvironmentType`) is *detected at runtime*, independent of the build config: a `.dev` build is `.simulator` in the Simulator or `.iPhoneDev` / `.macDev` on hardware; Release is `.testFlight` or `.appStore`; tests are `.testing`; previews `.preview`.

Environment — not the build config — drives logging (`AppLauncher.configureLogging`):
- `.testing` → skipped (tests bootstrap their own handlers when needed).
- `.preview` → `PrintLogHandler`.
- `.simulator`, `.iPhoneDev`, `.macDev` → `OSLogHandler` + `FileLogHandler` only.
- Release (`.deployed` / `.testFlight` / `.appStore`) → `OSLogHandler` + `FileLogHandler` + Sentry + crash reporting.

## Practical notes

- Simulator container for the dev build: `xcrun simctl get_app_container booted com.artisanalsoftware.PodHaven.dev data` → DB at `<container>/Documents/PodHavenDev/db.sqlite`, logs at `<container>/Documents/PodHavenDev/log.ndjson` (share from Settings → Debug, or copy from that path).
- To load the real device DB into the Simulator: export it on the phone via Settings → Debug → "Share PodHaven Database" (GRDB backup into a self-contained `.sqlite` file), then drop it into the dev build's `PodHavenDev/` directory as `db.sqlite`. The path differs (production uses root `Documents`, dev uses the subdir) but the file is interchangeable. Delete any stale `db.sqlite-wal` / `db.sqlite-shm` in the destination before launching — the app recreates them.

Related: [[device-debug-builds-break-background-scheduling]]
