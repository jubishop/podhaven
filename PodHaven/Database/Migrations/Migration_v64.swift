// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV64(_ db: Database) throws {
    // The seeded Smart Lists all received the generic list-music icon when the
    // icon column landed; replace it with a themed Lucide icon per list now that
    // a richer icon set exists. Each row is matched on title AND its exact
    // filter JSON so only an untouched default is upgraded: a list whose icon
    // was already changed (icon <> 'list-music'), whose filter was edited, or
    // whose title was renamed is left alone. The filter strings are the compact
    // combinator/conditions/groups encoding, byte-identical to both the seed
    // migration's stored output and a fresh re-save, so a re-saved-but-unchanged
    // default still matches.
    let upgrades: [(title: String, filter: String, icon: String)] = [
      (
        "Recent Episodes",
        #"{"combinator":"all","conditions":[],"groups":[]}"#,
        "sparkles"
      ),
      (
        "Unqueued",
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isUnqueued"},{"kind":"state","value":"isUnfinished"}],"groups":[]}"#,
        "inbox"
      ),
      (
        "Cached",
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isCached"}],"groups":[]}"#,
        "download"
      ),
      (
        "Saved",
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isSaved"}],"groups":[]}"#,
        "bookmark"
      ),
      (
        "Finished",
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isFinished"}],"groups":[]}"#,
        "circle-check"
      ),
      (
        "Unfinished",
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isUnfinished"},{"kind":"state","value":"isStarted"}],"groups":[]}"#,
        "hourglass"
      ),
      (
        "Previously Queued",
        #"{"combinator":"all","conditions":[{"kind":"state","value":"wasPreviouslyQueued"}],"groups":[]}"#,
        "history"
      ),
      (
        "Liked",
        #"{"combinator":"any","conditions":[{"kind":"state","value":"isLiked"},{"kind":"state","value":"isLoved"}],"groups":[]}"#,
        "heart"
      ),
      (
        "Disliked",
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isDisliked"}],"groups":[]}"#,
        "frown"
      ),
      (
        "Not Interested",
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isNotInterested"}],"groups":[]}"#,
        "meh"
      ),
    ]
    for upgrade in upgrades {
      try db.execute(
        sql: """
          UPDATE smartList SET icon = ?
          WHERE icon = 'list-music' AND title = ? AND filter = ?
          """,
        arguments: [upgrade.icon, upgrade.title, upgrade.filter]
      )
    }
  }
}
