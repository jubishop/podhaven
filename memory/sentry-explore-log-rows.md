---
name: "sentry-explore-log-rows"
description: "sentry explore ignores --sort on the logs dataset, so raw log rows repeat and drop across its pages; fetch row-level log attributes from the events API with an explicit sort instead."
type: "reference"
---

# Sentry explore log rows

`sentry explore --dataset logs` with only plain fields, such as `timestamp`,
`message`, `release`, and `user.id`, warns that `--sort` is not supported on
the logs dataset and ignores it. Its pages are then unordered. On November 25,
2026, UTC, with CLI 0.45.0, two such fetches of the same 441 logs each
returned 441 rows, but only 292 and 302 were distinct, and the release counts
disagreed with a `count()` aggregate over the same window.

`sentry log list` returns each log once but offers only its item ID,
timestamp, message, severity, and trace, not attributes like `release`,
`user.id`, or `logSessionID`.

For row-level attributes, query the events API with an explicit sort and
fixed bounds, checking the row count against a `count()` aggregate:

```sh
sentry api "organizations/artisanal-software/events/?dataset=logs&field=sentry.item_id&field=timestamp&field=message&field=release&field=user.id&query=<query>&sort=-timestamp&per_page=1000&start=<iso>&end=<iso>" --json
```

The response wraps the rows as `.body.data`. A window with more rows than
`per_page` needs the cursor from the `Link` header. `fetch_sentry_logs.sh`
pages aggregates rather than raw rows and rejects a repeated group; in that
check, its total matched the events API's.
