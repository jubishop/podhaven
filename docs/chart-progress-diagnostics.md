---
status: current
---

# Chart progress diagnostics

The progress ring retains evidence to investigate a native Charts trap. This
instrumentation does not clamp inputs, remove sectors, or replace Charts. It
does not establish or fix the cause of PODHAVEN-6H.

## Capture boundary

`CircularProgressView` supplies a numeric input description to an app-owned
boundary. The boundary records before it constructs Charts content, including
on its first evaluation. A geometry reader supplies the effective square size.
The model deduplicates unchanged input and geometry; ordinary body evaluations
do not create records. The inner-radius ratio and angular inset describe the
colored sectors. The transparent remainder retains Charts' default radius and
inset configuration.

Each instance gets a random UUID. Input changes advance its revision. Geometry,
transaction, appearance, disappearance, and scene transitions advance its
sequence. An animation-presence flag and the transaction's disabled-animation
flag describe the update. They do not sample intermediate animated sectors.
Geometry is marked as current-render, last-render, or unmeasured, so an input
transaction cannot mislabel the previous layout as its new effective size.

The journal records ordered sector values and temporary color hashes, total,
sum, computed remainder, remainder insertion, and proportions of the total that
Charts actually receives. The total can exceed the requested total when progress
is over-complete. Undefined proportions are omitted. Explicit classifications
distinguish zero, negative, positive, NaN, and both infinities. JSON represents
non-finite numbers as strings. The first eight sectors are retained, with the
original count and complete sum. Current callers use at most three.

Download snapshots include the numerator and denominator from the accepted
cache attempt. They travel with the fraction in one published value, so a stale
attempt cannot replace their context. Playback uses the seconds that produced
the displayed ratio. OPML supplies its counts, including the waiting count.
Preview-only callers use a separate source value. Xcode previews do not write
the journal.

No episode or device IDs, titles, feed URLs, or media URLs enter this schema.
The instance IDs and color hashes identify transient render state only.

## Bounds and crash delivery

`chart-progress.ndjson` uses the existing bounded NDJSON writer, separate from
general logs. Its maximum is 64 KiB and its trimming target is 48 KiB. On the
first write after relaunch, up to 24 KiB of complete prior records are protected
from current-process churn. Existing app and widget attachments retain their
128 KiB and 32 KiB limits. Chart evidence adds at most 64 KiB.

The writer permits an initial burst of 50 records and then one per second at
the chart capture site. Rate-limit records disclose suppression. Sequence gaps
also show missed transitions when a later snapshot is retained. The journal is
a bounded sample, not a complete history. A busy process can lose individual
instances or transitions. Older process history can be evicted by later launches.

Accepted records complete a small synchronous encode and append before Charts
receives the input. This prevents a trap in that update from overtaking a queued
write. The writer reuses its open handle, bounds truncation, and performs no
network operation or fsync on the rendering path. Unchanged evaluations do no
file I/O. File failures are logged without preventing rendering.

The initial Sentry scope includes the file path for native crash delivery. The
attachment hint also supplies it for other events and deduplicates by filename.
Missing chart files do not block an event. No manual feedback submission is
required. Reopening the app lets the SDK upload its native crash report.

Match the event's `log-session-id` tag to each record's `sessionID`. Check record
timestamps, version, build, and commit before using a snapshot. The
`chart_progress_file` context describes file availability in the uploading
process. Its observation session can differ from the crashed session; it is not
proof of attachment ingestion or crash-time geometry.

## Controlled verification

Run `bin/sentry-charts-smoke --device <available-iOS-Simulator-UDID>` with Sentry
authentication. The isolated probe renders row and detail sizes, zero/tiny/
normal/complete/over-complete values, animated updates, and sector insertion and
removal. It invokes the SDK's controlled native crash and relaunches with chart
and general-log churn before Sentry starts. The script reads the remote event,
downloads its chart attachment, and validates prior-session identity, commit,
source attribution, values, geometry, sector counts, and byte bounds. Evidence
stays in ignored `.cache/sentry-charts-smoke/`.

The probe never installs on a physical iPhone. Non-finite values are checked at
the diagnostic boundary in isolated tests; the probe does not deliberately pass
those values into Charts. Tests also cover retention, suppression, source
context, existing cache ownership, and attachment delivery. The original trap
may still need a real recurrence before its cause can be selected.
