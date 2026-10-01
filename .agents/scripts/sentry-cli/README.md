# Sentry helper response contracts

These helpers use the installed, authenticated `sentry` CLI. The API contract
was verified with version 0.45.0.

`sentry api <endpoint> --json` returns an HTTP response envelope with an integer
`status`, a `statusText`, and a `body`. `sentry_api_json` in `lib.sh` requires a
successful CLI exit, a 2xx HTTP status, and the expected endpoint payload type.
It writes only the validated `body` to the destination. Bare API arrays,
malformed JSON, missing fields, and unexpected types are errors. Diagnostics
name the endpoint without printing the response body.

The bundle files retain these payload shapes:

| File | Shape |
| --- | --- |
| `issue.json` | Native `issue view --json` object, unchanged |
| `events.json` | Native `issue events --json` object with a `data` list; feedback API fallback wraps the validated event list in `data` |
| `event_<id>.json` | Full event object, including nested `entries[].data` |
| `events_raw.json` | Validated API event list, present only for feedback fallback |
| `tags_<key>.json` | List of tag values and counts |
| `attachments.json` | List of attachment metadata |
| `activities.json` | Object with an `activity` list |
| `notes.json` | List of notes |

Tag distributions, activities, and notes are optional evidence. A failed
request prints its error and an unavailable warning, omits that payload file,
and labels the evidence unavailable in the summary. Missing files do not mean
zero results. Successful empty lists are saved and reported as empty. Required
attachment metadata and feedback fallback failures stop the helper. Feedback
with no events stops with an explicit diagnostic.

Native issue and structured-log commands have separate contracts. They do not
use the API envelope parser. Attachment download endpoints return raw bytes;
downloads bypass JSON parsing and preserve those bytes exactly.

Run the synthetic regression tests with:

```sh
python3 -B .agents/scripts/sentry-cli/test_sentry_helpers.py
```

Keep live smoke evidence in a temporary directory outside the repository.
Never copy real issue fields, feedback, or attachment bytes into test fixtures.
