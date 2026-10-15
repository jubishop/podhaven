---
status: current
---

# OPML import parse diagnostics

`PodcastOPML.parse(_:)` (`PodHaven/Feed/Models/PodcastOPML.swift`) reports a
parse failure to Sentry after the download passes session validation. Download
failures are outside this path. The error is rethrown unchanged, so the import
alert and `OPMLViewModel` behave as before.

Each capture sends one error event with fingerprint `opml-import-parse-failure`.
Its `opml_import` context holds the file's last path component, total and
attached byte counts, a truncation flag, and the ErrorKit-rendered error. The
event attaches `import.opml`, the first 1 MiB of the imported file, typed as
`text/x-opml`.

OPML files usually list the user's podcast subscriptions and feed URLs, so a
parse failure uploads that content to Sentry. The privacy disclosures must cover
any file a user may choose for import, not only files that contain an `<opml`
marker. A marker check would skip UTF-16 and BOM-encoded files, which are among
the failures this path exists to diagnose.

Captures are limited to one per 15 minutes per process. Failures inside that
window are logged at debug and not sent. The limit is in memory, so a relaunch
can send another capture. Behavior is covered by
`PodHavenTests/OPMLImportDiagnosticsTests.swift`.
