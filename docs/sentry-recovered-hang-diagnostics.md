---
status: current
---

# Recovered-hang diagnostic delivery

Sentry Cocoa 9.28.0 reports recovered AppHang events with an empty explicit
scope. That path bypasses the initial scope's recent-log attachments.
The event still needs the same bounded app and widget history as other errors.
See [foreground termination diagnostics](sentry-termination-diagnostics.md)
for record attribution, retention, file-status context, and payload limits.

## Temporary hint callback

Use `Options.beforeSendWithHint` to run the existing event filter and enrichment,
then add each missing recent-tail attachment to the outgoing hint. Keep the
initial-scope attachments for ordinary events and native crash delivery.
Deduplicate automatic attachments by their stable filename. Preserve feedback's
full logs and photos. A missing file must not prevent the remaining envelope
from being sent.

Sentry introduced this callback in 9.28.0 as a transitional API and marked its
setter deprecated immediately. Both 9.28.0 and 9.29.0 retain that declaration.
The callback takes precedence over `beforeSend`, so installing both callbacks
does not preserve the old filter automatically.

On September 21, 2026, the user approved this specific deprecation exception
for [#644](https://github.com/jubishop/podhaven/issues/644). Compiler diagnostics
remain enabled. The validation gate accepts only the exact setter diagnostic
at the production callback configuration; all other build and runtime warnings
remain failures. This exception does not authorize private SDK APIs, runtime
workarounds, or broad warning suppression.

## Migration to beforeSend

When a released SDK provides the attachment hint directly to `beforeSend`, use
that supported signature and remove `beforeSendWithHint`. The SDK's deprecation
message describes this as a future major-version change; the replacement is
not available in the checked 9.28.0 or 9.29.0 release. Check the actual released
API before migrating.

At migration, remove the function's `@diagnose` annotation, the matching validation
exception, and its tests. Retain
coverage of the final outgoing envelope, filtering and enrichment, duplicate
prevention, feedback photos/full logs, missing widget files, and the actual iOS
recovered-hang path. Keep the app and widget tail bounds at 128 KiB and 32 KiB.

Sentry 9.29 also deprecates its legacy hang detector in favor of MetricKit.
PodHaven already enables MetricKit. A future detector migration must explicitly
review diagnostic timing, operation-history retention, and coverage; replacing
the detector is separate from renaming the event callback.

## Operation history

Recent NDJSON files retain operation markers within the existing byte limits.
`DefaultsStorable` records the start, successful encoding, and completion of a
write, or an encoding failure. Optional-value removal has start/completion
markers. Detail phases record their start and completion even when they stay
below the performance-warning threshold. Existing navigation messages identify
tab and destination changes.

Each operation has a random ID, a fixed kind, process uptime, elapsed
milliseconds, and a main-thread flag. Detail markers include the episode count;
persistence markers include encoded byte counts. They do not include setting
keys, values, titles, or URLs. Record-level session, build, and timestamp fields
identify the process and revision. Compare uptime only within that session.

Markers retain their operation's caller location, so each detail call site and
persistence boundary has its own existing file-log rate limit. Busy work at one
site does not consume another site's allowance. Repeated work at the same site
can still be suppressed; rate-limit summaries identify that loss.

A start without a completion in the uploaded tail shows work still pending at
the attachment snapshot, a completion outside the retained history, or a
suppressed completion. It does not prove that operation caused the hang. Use
encoded/completed transitions,
thread flags, timestamps, the hang interval, and the captured stack together.
Current-process context describes capture time and must not be relabeled as
hang-time context.

## Controlled iOS verification

Run `bin/sentry-hang-smoke --device <available-iOS-Simulator-UDID>` with the
authenticated Sentry CLI. It builds an isolated app from the current sources,
using the production Sentry configuration and bounded NDJSON writer, with a
seeded widget-tail fixture. A separate
entry point starts real navigation/detail/persistence work and delays one
main-thread persistence call so the SDK detects and reports a recovered hang.
A background persistence call remains pending when the attachment is captured.
Deliberate delays exist only in this integration harness.

The helper downloads attachments from that SDK-generated event and checks exact
download sizes, valid NDJSON, individual/combined bounds, session/build fields,
pre-hang navigation and detail work, the completed foreground write, and the
pending background write. Evidence stays under ignored `.cache/sentry-hang-smoke/`.
The probe uses its own app container, omits the app's configured device identity, and
tags the diagnostic run. It never installs onto a physical device.

Controlled Simulator readback verified the completed foreground persistence
operation, preceding detail phase, and background operation still pending in
the uploaded file. This establishes diagnostic delivery for the controlled
hang.

The historical recursive-property-list hang's caller remains unknown. Its
missing history cannot be restored retroactively. A recurrence should now
provide the same-event files, matching session/build, operation transitions,
thread flags, sizes, timing, and stack needed to distinguish persistence work
from nearby detail/navigation or background activity. This change makes that
evidence available; it does not claim to fix an identified hang cause.

References: [9.28 release](https://github.com/getsentry/sentry-cocoa/releases/tag/9.28.0),
[9.29 callback declaration](https://github.com/getsentry/sentry-cocoa/blob/9.29.0/Sources/Swift/Options.swift#L168-L181),
[9.29 detector deprecation](https://github.com/getsentry/sentry-cocoa/releases/tag/9.29.0).
