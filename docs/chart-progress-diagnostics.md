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

`ChartProgressStore` keeps fixed-size, shared memory-mapped files. Each accepted
transition copies a checksummed numeric record before Charts receives the new
input. This path does not JSON-encode, submit logging work, call a file write,
or wait for a flush. Native process termination leaves the shared pages
available to the next process. This is not a power-loss durability guarantee.
The general log handlers and their protection remain unchanged.

| Limit | Bound |
| --- | --- |
| Retained instances per session | 32 |
| Recent states per instance | 8 |
| Recent eviction details | 32 |
| Stored sessions | 4 |
| Mapped bytes per session | 151,552 |
| Total mapped files | 606,208 bytes |
| Exported attachment | 1 MiB |

Every resident instance keeps its latest state, independent of other instances'
update rates. The instance's ring retains preceding input, geometry, animation,
and lifecycle transitions. Unchanged evaluations remain deduplicated. A render
after a changed transaction records current geometry even when the input is
unchanged. Disappearance records remain until capacity pressure needs their
slot. Eviction prefers disappeared instances, then the least recently updated
instance. Returning evicted instances can acquire a new slot.

The export's retention record lists each instance's source, first and last
sequence, latest revision and timestamp, omitted transition count, and terminal
state. Eviction details retain the retired instance's identity, source, sequence,
revision, timestamp, and terminal state. Per-source eviction totals continue
when the detail ring wraps. The export discloses the number of lost eviction
details. Sector truncation and invalid record slots are explicit. A checksum
rejects an interrupted record while preserving other recent states. Capacity
limits mean absence is not evidence of unchanged input.

The Sentry initial scope prepares the current session's mapping. The attachment
hint exports only the event's `log-session-id` session as `chart-progress.ndjson`.
It replaces any older attachment with that filename, so current launch churn
cannot substitute current state. The SDK prepares and caches the native crash
event and attachment after relaunch; transmission can occur later. Up to three
intervening sessions fit the archive. When the requested session is no longer
retained, the attachment explicitly reports that session as unavailable.
An older app build's sampled journal remains readable on upgrade; only rows
matching the requested session enter its attachment.

JSON encoding occurs at event preparation, outside the rendering path. Existing
app and widget attachment bounds remain unchanged. No manual export is needed.
Match session, timestamp, version, build, and commit before using evidence.
`chart_progress_file` describes the selected event session and storage limits;
the uploading process's observation session is distinct. File failures produce
an unavailable attachment and an error log without stopping rendering.

## Cost measurement

`ChartProgressDiagnosticsTests.captureCost` compares changing pre-render capture
against the former encode-plus-synchronous-journal path, including throttled
calls. It measures export separately and reports the fixed file allocation.
The first focused Debug run on the development Mac measured 3,000 samples:
mapped capture median 9.33 μs, p95 11.00 μs; former journal median 11.96 μs,
p95 14.25 μs; export of three instance histories 2.30 ms. These are host
microbenchmarks, not physical-device frame timing or evidence about the reported
playback delay. Repeat the comparison when changing this store or logging policy.

## Controlled verification

Run `bin/sentry-charts-smoke --device <available-iOS-Simulator-UDID>` with Sentry
authentication. The isolated probe renders four fast download rings, two slower playback rings,
OPML sector insertion/removal, and a disappearing ring. It includes row and detail
sizes and near-zero progress. After all seven active rings reach known final
pre-render inputs, it invokes the SDK's controlled native crash immediately.
It then runs a churn-only launch and another launch with chart and general-log
churn before Sentry starts. The script reads the remote event,
downloads its chart attachment, and validates prior-session identity, commit,
source attribution, values, geometry, sector counts, and byte bounds. Evidence
stays in ignored `.cache/sentry-charts-smoke/`.

The probe never installs on a physical iPhone. Non-finite values are checked at
the diagnostic boundary in isolated tests; the probe does not deliberately pass
those values into Charts. Tests also cover per-instance retention, overflow, corruption, source
context, existing cache ownership, and attachment delivery. The original trap
may still need a real recurrence before its cause can be selected.
