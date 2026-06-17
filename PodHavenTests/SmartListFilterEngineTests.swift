// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of SmartListFilterEngine tests", .container)
class SmartListFilterEngineTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  // MARK: - Query Helpers

  private func ids(matching expression: SQLExpression) async throws -> Set<Episode.ID> {
    Set(try await observatory.episodeIDs(filter: expression).get())
  }

  private func ids(for filter: SmartListFilter) async throws -> Set<Episode.ID> {
    try await ids(matching: SmartListFilterEngine.sqlExpression(for: filter))
  }

  // The engine's production target joins `podcast`; episodeIDs(filter:) does not.
  // Run a filter through the joined request to prove the podcast subqueries still
  // resolve to their own inner `podcast` rather than the request's joined one.
  private func listableIDs(for filter: SmartListFilter) async throws -> Set<Episode.ID> {
    let expression = SmartListFilterEngine.sqlExpression(for: filter)
    return Set(try await observatory.listablePodcastEpisodes(filter: expression).get().map(\.id))
  }

  private func all(_ conditions: SmartListFilter.Condition...) -> SmartListFilter {
    SmartListFilter(combinator: .all, conditions: conditions)
  }

  // MARK: - Parity With Hardcoded EpisodesView Filters

  @Test("each of the 10 default filters matches today's hardcoded expression")
  func parityWithHardcodedDefaults() async throws {
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "recent"),
          try Create.unsavedEpisode(guid: "queued", queueOrder: 0, queueDate: Date()),
          try Create.unsavedEpisode(guid: "cached", cachedFilename: "c.mp3"),
          try Create.unsavedEpisode(guid: "saved", cachedFilename: "s.mp3", saveInCache: true),
          try Create.unsavedEpisode(guid: "finished", finishDate: Date()),
          try Create.unsavedEpisode(guid: "started", currentTime: CMTime.seconds(30)),
          try Create.unsavedEpisode(guid: "prevqueued", queueDate: Date()),
          try Create.unsavedEpisode(guid: "loved", rating: .loved),
          try Create.unsavedEpisode(guid: "liked", rating: .liked),
          try Create.unsavedEpisode(guid: "disliked", rating: .disliked),
          try Create.unsavedEpisode(guid: "notinterested", rating: .notInterested),
        ]
      )
    )

    let cases: [(SmartListFilter, SQLExpression)] = [
      (all(), AppDB.noOp),
      (all(.state(.isUnqueued), .state(.isUnfinished)), Episode.unqueued && Episode.unfinished),
      (all(.state(.isCached)), Episode.cached),
      (all(.state(.isSaved)), Episode.savedInCache),
      (all(.state(.isFinished)), Episode.finished),
      (all(.state(.isUnfinished), .state(.isStarted)), Episode.unfinished && Episode.started),
      (all(.state(.wasPreviouslyQueued)), Episode.previouslyQueued),
      (
        SmartListFilter(combinator: .any, conditions: [.state(.isLiked), .state(.isLoved)]),
        Episode.liked || Episode.loved
      ),
      (all(.state(.isDisliked)), Episode.disliked),
      (all(.state(.isNotInterested)), Episode.notInterested),
    ]

    for (filter, hardcoded) in cases {
      let engineIDs = try await ids(for: filter)
      let hardcodedIDs = try await ids(matching: hardcoded)
      #expect(engineIDs == hardcodedIDs)
    }
  }

  @Test("an empty filter matches every episode")
  func emptyFilterMatchesAll() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(), try Create.unsavedEpisode()]
      )
    )
    #expect(try await ids(for: all()) == Set(series.episodes.map(\.id)))
  }

  // MARK: - State

  @Test("uncached is the complement of cached")
  func uncachedState() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "cached", cachedFilename: "c.mp3"),
          try Create.unsavedEpisode(guid: "uncached"),
        ]
      )
    )
    let cached = series.episodes[0].id
    let uncached = series.episodes[1].id

    #expect(try await ids(for: all(.state(.isCached))) == [cached])
    #expect(try await ids(for: all(.state(.isUncached))) == [uncached])
    // Parity with the hardcoded complement of the cached expression.
    let uncachedIDs = try await ids(for: all(.state(.isUncached)))
    let hardcoded = try await ids(matching: !Episode.cached)
    #expect(uncachedIDs == hardcoded)
  }

  // MARK: - Text

  @Test("episode doesNotContain includes null-description rows")
  func doesNotContainIsNullSafe() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "null", description: nil),
          try Create.unsavedEpisode(guid: "bar", description: "all about bar"),
          try Create.unsavedEpisode(guid: "foo", description: "the foo show"),
        ]
      )
    )
    let nullID = series.episodes[0].id
    let barID = series.episodes[1].id

    let matched = try await ids(for: all(.episodeText(.description, .doesNotContain, "foo")))
    // A null-description row is absent from the FTS index, so the NOT IN
    // subquery correctly retains it.
    #expect(matched == [nullID, barID])
  }

  @Test(
    "contains matches whole words and contiguous phrases, never prefixes or out-of-order tokens"
  )
  func containsWholeWordsAndPhrases() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "rock", title: "Rock Anthems"),
          try Create.unsavedEpisode(guid: "rocket", title: "Rocket Science"),
          try Create.unsavedEpisode(guid: "phrase", title: "The Quantum Physics Hour"),
          try Create.unsavedEpisode(guid: "split", title: "Physics of the Quantum World"),
        ]
      )
    )
    let rock = series.episodes[0].id
    let phrase = series.episodes[2].id

    // Whole word, case-insensitive — never a prefix: "rock" matches "Rock" but
    // not "Rocket".
    #expect(try await ids(for: all(.episodeText(.title, .contains, "rock"))) == [rock])

    // A multi-word value matches only as a contiguous, in-order phrase:
    // "quantum physics" hits "The Quantum Physics Hour" but not a title that
    // holds the same words apart and out of order.
    #expect(
      try await ids(for: all(.episodeText(.title, .contains, "quantum physics"))) == [phrase]
    )
  }

  @Test("text match is scoped to the queried field")
  func textFieldScoping() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "titleHit",
            title: "Quantum Physics",
            description: "unrelated"
          ),
          try Create.unsavedEpisode(
            guid: "descHit",
            title: "Daily Show",
            description: "About quantum mechanics"
          ),
        ]
      )
    )
    let titleHit = series.episodes[0].id
    let descHit = series.episodes[1].id

    // "quantum" lives in titleHit's title and descHit's description; each field
    // filter sees only its own column.
    #expect(try await ids(for: all(.episodeText(.title, .contains, "quantum"))) == [titleHit])
    #expect(
      try await ids(for: all(.episodeText(.description, .contains, "quantum"))) == [descHit]
    )
  }

  @Test("title-or-description spans both columns and equals an Any of the two single-field rows")
  func episodeTitleOrDescriptionCombinesColumns() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "titleHit",
            title: "Quantum Physics",
            description: "unrelated"
          ),
          try Create.unsavedEpisode(
            guid: "descHit",
            title: "Daily Show",
            description: "About quantum mechanics"
          ),
          try Create.unsavedEpisode(guid: "miss", title: "Cooking Hour", description: "recipes"),
        ]
      )
    )
    let titleHit = series.episodes[0].id
    let descHit = series.episodes[1].id
    let miss = series.episodes[2].id

    // contains spans both columns: a title-only hit and a description-only hit.
    let combined = try await ids(for: all(.episodeText(.titleOrDescription, .contains, "quantum")))
    #expect(combined == [titleHit, descHit])

    // Identical to one title condition and one description condition OR'd.
    let oneOfEach = try await ids(
      for: SmartListFilter(
        combinator: .any,
        conditions: [
          .episodeText(.title, .contains, "quantum"),
          .episodeText(.description, .contains, "quantum"),
        ]
      )
    )
    #expect(combined == oneOfEach)

    // exclude keeps only rows where neither column contains the term.
    #expect(
      try await ids(for: all(.episodeText(.titleOrDescription, .doesNotContain, "quantum"))) == [
        miss
      ]
    )
  }

  @Test("title-or-description matches a phrase within one column, never split across the two")
  func titleOrDescriptionPhraseDoesNotSpanColumns() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "inTitle",
            title: "Quantum Physics Hour",
            description: "cooking"
          ),
          try Create.unsavedEpisode(
            guid: "inDesc",
            title: "Daily Show",
            description: "a quantum physics deep dive"
          ),
          try Create.unsavedEpisode(
            guid: "split",
            title: "Quantum Computing",
            description: "about physics today"
          ),
        ]
      )
    )
    let inTitle = series.episodes[0].id
    let inDesc = series.episodes[1].id

    // The phrase lives wholly within one column for the first two rows; the
    // third splits the words across title and description, so it must not match.
    let combined = try await ids(
      for: all(.episodeText(.titleOrDescription, .contains, "quantum physics"))
    )
    #expect(combined == [inTitle, inDesc])

    // titleOrDescription is the OR of the two single-column phrase matches, not a
    // whole-document bag of words: the split row is absent from both.
    let oneOfEach = try await ids(
      for: SmartListFilter(
        combinator: .any,
        conditions: [
          .episodeText(.title, .contains, "quantum physics"),
          .episodeText(.description, .contains, "quantum physics"),
        ]
      )
    )
    #expect(combined == oneOfEach)
  }

  @Test("contains with no tokenizable content matches nothing")
  func containsUntokenizable() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "a", title: "Hello")]
      )
    )
    // Punctuation-only input yields no FTS pattern: contains matches nothing,
    // doesNotContain matches everything.
    #expect(try await ids(for: all(.episodeText(.title, .contains, "!!!"))).isEmpty)
    #expect(
      try await ids(for: all(.episodeText(.title, .doesNotContain, "!!!")))
        == Set(series.episodes.map(\.id))
    )
  }

  // MARK: - Nested Precedence

  @Test("a nested any-group inside an all-group is parenthesised correctly")
  func nestedPrecedence() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "tech-loved", title: "Tech Weekly", rating: .loved),
          try Create.unsavedEpisode(guid: "tech-disliked", title: "Tech Daily", rating: .disliked),
          try Create.unsavedEpisode(guid: "garden-loved", title: "Garden Time", rating: .loved),
          try Create.unsavedEpisode(guid: "tech-none", title: "Tech News"),
        ]
      )
    )

    // title contains "tech" AND (loved OR liked) — only the first episode.
    let filter = SmartListFilter(
      combinator: .all,
      conditions: [.episodeText(.title, .contains, "tech")],
      groups: [
        SmartListFilter.Group(
          combinator: .any,
          conditions: [.state(.isLoved), .state(.isLiked)]
        )
      ]
    )
    #expect(try await ids(for: filter) == [series.episodes[0].id])
  }

  @Test("each nested group is its own term in the outer combinator")
  func multipleGroupsCombineIndependently() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "loved-cached",
            cachedFilename: "a.mp3",
            rating: .loved
          ),
          try Create.unsavedEpisode(guid: "loved-only", rating: .loved),
          try Create.unsavedEpisode(guid: "cached-only", cachedFilename: "b.mp3"),
          try Create.unsavedEpisode(guid: "neither"),
        ]
      )
    )

    // (loved OR liked) AND (cached OR saved) — only the first episode.
    let conjoined = SmartListFilter(
      combinator: .all,
      groups: [
        SmartListFilter.Group(combinator: .any, conditions: [.state(.isLoved), .state(.isLiked)]),
        SmartListFilter.Group(combinator: .any, conditions: [.state(.isCached), .state(.isSaved)]),
      ]
    )
    #expect(try await ids(for: conjoined) == [series.episodes[0].id])

    // (loved AND cached) OR (cached AND unstarted) — everything but "loved-only"
    // and "neither".
    let disjoined = SmartListFilter(
      combinator: .any,
      groups: [
        SmartListFilter.Group(combinator: .all, conditions: [.state(.isLoved), .state(.isCached)]),
        SmartListFilter.Group(
          combinator: .all,
          conditions: [.state(.isCached), .state(.isUnstarted)]
        ),
      ]
    )
    #expect(
      try await ids(for: disjoined) == [series.episodes[0].id, series.episodes[2].id]
    )

    // An empty group contributes no term: with combinator any, it must not
    // short-circuit the disjunction to always-true.
    let withEmptyGroup = SmartListFilter(
      combinator: .any,
      groups: [
        SmartListFilter.Group(combinator: .all, conditions: []),
        SmartListFilter.Group(combinator: .all, conditions: [.state(.isLoved)]),
      ]
    )
    #expect(
      try await ids(for: withEmptyGroup) == [series.episodes[0].id, series.episodes[1].id]
    )
  }

  // MARK: - Tags

  @Test("tag conditions use episode or parent-podcast tags")
  func tagConditionsUseEffectiveTags() async throws {
    let episodeTaggedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "episode-tagged")]
      )
    )
    let podcastTaggedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "podcast-tagged")]
      )
    )
    let untaggedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "untagged")]
      )
    )
    let episodeTagged = episodeTaggedSeries.episodes[0].id
    let podcastTagged = podcastTaggedSeries.episodes[0].id
    let untagged = untaggedSeries.episodes[0].id
    let tag = try await repo.insertTag(UnsavedTag(name: "Tech"))
    try await repo.addTag(tag.id, to: episodeTagged)
    try await repo.addTag(tag.id, to: podcastTaggedSeries.id)

    #expect(try await ids(for: all(.tag(.hasTag(tag.id)))) == [episodeTagged, podcastTagged])
    #expect(try await ids(for: all(.tag(.hasAnyTag))) == [episodeTagged, podcastTagged])
    #expect(try await ids(for: all(.tag(.doesNotHaveTag(tag.id)))) == [untagged])
    #expect(try await ids(for: all(.tag(.hasNoTags))) == [untagged])
  }

  @Test("multiple tag conditions compose against effective tags")
  func multipleTagConditionsCompose() async throws {
    let matchingSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "matching")]
      )
    )
    let missingPodcastTagSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "missing-podcast-tag")]
      )
    )
    let matching = matchingSeries.episodes[0].id
    let missingPodcastTag = missingPodcastTagSeries.episodes[0].id
    let interviewTag = try await repo.insertTag(UnsavedTag(name: "Interview"))
    let techTag = try await repo.insertTag(UnsavedTag(name: "Tech"))

    try await repo.addTag(interviewTag.id, to: matching)
    try await repo.addTag(techTag.id, to: matchingSeries.id)
    try await repo.addTag(interviewTag.id, to: missingPodcastTag)

    #expect(
      try await ids(for: all(.tag(.hasTag(interviewTag.id)), .tag(.hasTag(techTag.id))))
        == [matching]
    )
  }

  @Test("an unresolved tag id matches nothing")
  func unresolvedTagMatchesNothing() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let ghost = Tag.ID(rawValue: 999_999)
    #expect(try await ids(for: all(.tag(.hasTag(ghost)))).isEmpty)
    #expect(try await ids(for: all(.tag(.doesNotHaveTag(ghost)))) == Set(series.episodes.map(\.id)))
    #expect(try await ids(for: all()) == Set(series.episodes.map(\.id)))
  }

  // MARK: - Joined Request Parity

  @Test("podcast-text and tag filters hold through the joined listable request")
  func filtersThroughJoinedRequest() async throws {
    let techSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "The Tech Show"),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "tech-ep")]
      )
    )
    let episodeTaggedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "episode-tagged")]
      )
    )
    let gardenSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Garden Hour"),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "garden-ep")]
      )
    )
    let techEp = techSeries.episodes[0].id
    let episodeTagged = episodeTaggedSeries.episodes[0].id
    let gardenEp = gardenSeries.episodes[0].id
    let tag = try await repo.insertTag(UnsavedTag(name: "Tech"))
    try await repo.addTag(tag.id, to: techSeries.id)
    try await repo.addTag(tag.id, to: episodeTagged)

    // The joined request must agree with the unjoined episodeIDs path: the
    // podcast-text subquery resolves to its own inner table, not the request's
    // joined `podcast`.
    #expect(try await ids(for: all(.podcastText(.title, .contains, "tech"))) == [techEp])
    #expect(try await listableIDs(for: all(.podcastText(.title, .contains, "tech"))) == [techEp])
    #expect(
      try await listableIDs(for: all(.podcastText(.title, .doesNotContain, "tech")))
        == [gardenEp, episodeTagged]
    )
    #expect(try await listableIDs(for: all(.tag(.hasTag(tag.id)))) == [techEp, episodeTagged])
    #expect(try await listableIDs(for: all(.tag(.doesNotHaveTag(tag.id)))) == [gardenEp])
  }

  // MARK: - Podcast Text

  @Test("podcast text matches against the parent podcast's title")
  func podcastTextScopes() async throws {
    let techSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "The Tech Show"),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "tech-ep")]
      )
    )
    let gardenSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Garden Hour"),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "garden-ep")]
      )
    )
    let techEp = techSeries.episodes[0].id
    let gardenEp = gardenSeries.episodes[0].id

    #expect(try await ids(for: all(.podcastText(.title, .contains, "tech"))) == [techEp])
    #expect(try await ids(for: all(.podcastText(.title, .doesNotContain, "tech"))) == [gardenEp])
    #expect(try await ids(for: all(.podcastText(.title, .contains, "the tech"))) == [techEp])
  }

  @Test("podcast title-or-description spans both columns through the joined request")
  func podcastTitleOrDescriptionCombinesColumns() async throws {
    let titleSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          title: "Tech Weekly",
          description: "news"
        ),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "title-pod")]
      )
    )
    let descSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          title: "Cooking",
          description: "tech discussion"
        ),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "desc-pod")]
      )
    )
    let missSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          title: "Garden",
          description: "plants"
        ),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "miss-pod")]
      )
    )
    let titleEp = titleSeries.episodes[0].id
    let descEp = descSeries.episodes[0].id
    let missEp = missSeries.episodes[0].id

    #expect(
      try await ids(for: all(.podcastText(.titleOrDescription, .contains, "tech")))
        == [titleEp, descEp]
    )
    #expect(
      try await listableIDs(for: all(.podcastText(.titleOrDescription, .contains, "tech")))
        == [titleEp, descEp]
    )
    #expect(
      try await listableIDs(for: all(.podcastText(.titleOrDescription, .doesNotContain, "tech")))
        == [missEp]
    )
  }

  // MARK: - Duration

  @Test("duration bounds are inclusive and open-ended on nil")
  func durationBounds() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "zero", duration: CMTime.seconds(0)),
          try Create.unsavedEpisode(guid: "half", duration: CMTime.seconds(1800)),
          try Create.unsavedEpisode(guid: "full", duration: CMTime.seconds(3600)),
        ]
      )
    )
    let zero = series.episodes[0].id
    let half = series.episodes[1].id
    let full = series.episodes[2].id

    // min 0 includes the shortest (0-second) episode.
    #expect(
      try await ids(for: all(.duration(minSeconds: 0, maxSeconds: nil))) == [zero, half, full]
    )
    #expect(try await ids(for: all(.duration(minSeconds: 1, maxSeconds: nil))) == [half, full])
    #expect(try await ids(for: all(.duration(minSeconds: nil, maxSeconds: 1800))) == [zero, half])
    #expect(try await ids(for: all(.duration(minSeconds: 1800, maxSeconds: 1800))) == [half])
  }

  // MARK: - Publish Date

  @Test("publish-date windows partition around the current time")
  func publishDateWindows() async throws {
    // The cutoff resolves against SQLite's clock at query time. Anchoring the
    // fixtures to this process's clock and keeping them days clear of the 7-day
    // boundary makes the sub-second skew between the two clocks immaterial.
    let now = Date()
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "fresh",
            pubDate: now.addingTimeInterval(-2 * 86400)
          ),
          try Create.unsavedEpisode(
            guid: "old",
            pubDate: now.addingTimeInterval(-30 * 86400)
          ),
        ]
      )
    )
    let fresh = series.episodes[0].id
    let old = series.episodes[1].id

    #expect(try await ids(for: all(.publishDate(.withinLast, days: 7))) == [fresh])
    #expect(try await ids(for: all(.publishDate(.olderThan, days: 7))) == [old])
  }
}
