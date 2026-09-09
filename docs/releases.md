---
status: current
---

# Versioning and releases

App Store versions have zero or one dot, such as `2` or `2.1`. TestFlight
versions have exactly two dots, such as `2.1.1`. Build numbers increase
separately on each new upload.

## Read or change the version

```sh
bin/version
bin/version 2.1.2
```

Without an argument, `bin/version` only prints the current version. Setting a
version requires a fully clean working tree and a branch with a configured
upstream. The command changes all Xcode marketing-version settings, commits
only the project file with a message such as `Change version number to 2.1.2`,
and pushes the current branch to its upstream. It rejects version decreases.

If the push fails, the version commit remains local. Repeat the same
`bin/version` command to retry the push without another commit. Deployment
also retries an unfinished version push before it can upload anything.

## Upload to TestFlight

```sh
bin/shipit --notes "What testers should try"
```

The command requires clean `main`; the existing `--force` option permits
another clean branch. If the current version is an App Store version,
`shipit` first commits and pushes the next TestFlight version:

- `2.1` becomes `2.1.1`.
- `2` becomes `2.0.1`.
- `2.1.2` remains `2.1.2`.

The upload then uses that version and a new build number. With `--notes`, it
waits for processing and assigns the exact build to the external Everyone
group. Without `--notes`, it only tests, archives, and uploads.

Use `bin/version` yourself when you want a different patch version. For
example, `bin/version 2.1.2` followed by `bin/shipit` uploads `2.1.2`.

## Release on the App Store

```sh
bin/appstore
```

Plain `bin/appstore` starts a release. Use `bin/appstore --status` for read-only
status. The default release number increments the minor number and removes the
patch number: `2.1.2` or `2.1` becomes `2.2`, and `2` becomes `2.1`.

The default public notes come from the most recently uploaded iOS TestFlight
build whose version has two dots. The command uses the app's primary language,
or `en-US` if that localization is absent. If that build has no usable notes,
it stops before changing the project and asks for `--notes`. It does not use
notes from an older build. Notes must contain 1 to 4000 characters and are
copied unchanged to every existing App Store listing language.

Use either override when needed:

```sh
bin/appstore --release 3
bin/appstore --notes "Public release notes"
bin/appstore --release 3 --notes "Public release notes"
```

`--release` accepts only zero or one dot and must be strictly greater than the
current local version. For example, `2.1` is equal to `2.1.0` and is rejected.
Use this override for major version changes. A saved release retry can reuse
its original version even after the local version has changed to it.

The release command requires clean `main` and performs these steps:

1. Choose the version and notes, then check App Store Connect for conflicting versions or review submissions.
2. Set, commit, and push the requested version with `bin/version`.
3. Test, archive, and upload using the App Store upload mode.
4. Wait for that exact build to finish processing.
5. Set the public release notes and submit for App Review.
6. Verify the selected build, notes, submission, and automatic release after approval.

Processing is checked every 30 seconds for up to 30 minutes. Apple review
continues after the command finishes. The local version remains at the
requested release number; the next `shipit` starts the next TestFlight patch.

A typical cycle is App Store `2.1`, TestFlight `2.1.1` and `2.1.2`, then App Store `2.2`.
The App Store upload is a fresh build with the release version; it does not
rename an existing TestFlight build.

Uploads retain the existing Git tag, GitHub release, and SourceHut mirror
behavior. The App Store upload mode does not distribute to external
TestFlight testers.

## Retry a release

Repeat the same command after a push, upload, processing, or submission failure.
A checkout-local receipt retains the chosen version, notes, release commit, and
exact build number. A retry does not bump the version again or fetch different
notes. A completed upload is reused even if a newer build later appears in App
Store Connect. An unrelated change to the checkout cannot replace a release
whose upload has not completed.

Repeating a completed automatic release from the same commit with the same
notes verifies the existing submission. After new commits, an automatic release
selects the next minor version. An unfinished release must be retried first.

The command keeps one release receipt in Git metadata. It replaces a completed
receipt when a new release starts and prevents concurrent release commands
in the same checkout. It does not accumulate release history there.

To submit a known existing App Store build explicitly, including when the
local receipt is unavailable and the release number is above the local version:

```sh
bin/appstore --release 2.2 --build 600 --notes "Public release notes"
```

This form requires clean `main`, then waits for and submits only that build.
It does not change the local version or upload again. The build's version must
match `--release`. Omitting `--notes` uses the same TestFlight notes default.

A failed Apple validation, unresolved export-compliance requirement, or
conflicting review needs to be resolved before retrying. The command reports
the failure instead of selecting another build.
