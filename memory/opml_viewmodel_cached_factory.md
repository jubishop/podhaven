---
name: opml-viewmodel-cached-factory
description: OPMLViewModel must be a .cached Container factory so ShareService and OPMLView share one instance, or the OPML import-progress sheet never appears.
type: feedback
---

# `OPMLViewModel` must be a `.cached` Container factory

`OPMLViewModel` is a `.cached` `Container` factory with a `fileprivate init`, injected via `@InjectedObservable(\.opmlViewModel)` in `OPMLView` and resolved with `Container.shared.opmlViewModel()` in `ShareService`. Never construct it directly (`OPMLViewModel()` / a view's own `@State`).

**Why:** A shared `.opml` routes through `ShareService.handleOPMLURL`, which runs the import on an `OPMLViewModel`; `OPMLView` presents the progress sheet bound to *its own* `opmlFile`. If those are two different instances, the import runs fine but the view's sheet never updates, so nothing appears (Sentry PODHAVEN-49). One `.cached` instance shared by both fixes it; the `fileprivate init` makes a detached instance impossible to create.

**How to apply:** Keep the factory `.cached`. If you switch it to `.unique`, re-add an accessible `init`, or let a view hold its own `@State` copy "to simplify," the share-import sheet silently breaks again.
