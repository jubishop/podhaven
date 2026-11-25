---
status: current
---

# Files app access

The app's `Info.plist` sets `UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace`, so the Files app, and Finder on a
connected Mac, show the app's `Documents` directory on every build, including
App Store builds. That directory holds the logs and the live SQLite database,
`db.sqlite` with its `-wal` and `-shm` files. Development builds keep them in
a subdirectory, as [build variants](../memory/build-variants-dev-debug-release.md)
describes.

App Store builds hide Settings' Debug section, including Share Database and
Share Logs, so Files app access is how logs and the database stay reachable
there.

## Trade-off

Anyone using the unlocked device can delete or replace the live database and
its `-wal` and `-shm` files through the Files app while PodHaven runs. SQLite
does not guard against that, and it can lose data or corrupt the database; see
[How To Corrupt An SQLite Database File](https://www.sqlite.org/howtocorrupt.html).

## Decision

Keep both keys. Decided 2026-11-08 by jubishop in
[jubishop/podhaven#895](https://github.com/jubishop/podhaven/issues/895).
Rejected: turning Files app access off, and moving the live database out of
`Documents`.
