---
name: lucide-icon-asset-resync
description: Re-syncing vendored Lucide icons must preserve filter/fingerprint/waves rawValues, which are persisted in tag.icon and smartList.icon
type: reference
---

`LucideIcon` (`PodHaven/Database/Models/LucideIcon.swift`) is a `String` enum whose rawValue is the Lucide icon id, which doubles as the namespaced asset name under `PodHaven/Assets.xcassets/LucideIcons/<rawValue>.imageset`. The icons are vendored as local SVGs (lucide-static v1.18.0 at import time), one imageset per case. That rawValue is also what gets persisted: `DatabaseValueConvertible` writes it into the non-null `tag.icon` and `smartList.icon` columns (added in migration v61).

Three vendored ids have been renamed/removed on Lucide `main` but are still valid in the pinned v1.18.0, so nothing is broken today:

- `filter` → upstream is now `funnel`
- `fingerprint`
- `waves`

On a future re-sync from upstream Lucide, renaming those asset folders and their enum cases to the new canonical ids would change their rawValues — and any existing `tag`/`smartList` row that stored `"filter"`, `"fingerprint"`, or `"waves"` would then fail to decode. So a re-sync must keep the old ids decodable: either keep the old names as enum aliases, or add a migration that rewrites the persisted values. Update the asset folder, the enum case, and the persistence path together; do not rename in isolation.

(Origin: maintenance note on issue #466's thread, recorded here because that thread is easy to lose.)
