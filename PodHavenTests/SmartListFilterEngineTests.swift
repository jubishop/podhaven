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

  // Fixed so publish-date windows are deterministic.
  private static let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

  // MARK: - Query Helpers

  private func ids(matching expression: SQLExpression) async throws -> Set<Episode.ID> {
    Set(try await observatory.episodeIDs(filter: expression).get())
  }

  private func ids(
    for filter: SmartListFilter,
    referenceDate: Date = SmartListFilterEngineTests.referenceDate
  ) async throws -> Set<Episode.ID> {
    try await ids(
      matching: SmartListFilterEngine.sqlExpression(for: filter, referenceDate: referenceDate)
    )
  }

  // The engine's production target joins `podcast`; episodeIDs(filter:) does not.
  // Run a filter through the joined request to prove the podcast subqueries still
  // resolve to their own inner `podcast` rather than the request's joined one.
  private func listableIDs(
    for filter: SmartListFilter,
    referenceDate: Date = SmartListFilterEngineTests.referenceDate
  ) async throws -> Set<Episode.ID> {
    let expression = SmartListFilterEngine.sqlExpression(for: filter, referenceDate: referenceDate)
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
    // The null-description row would be wrongly dropped by a naive NOT LIKE.
    #expect(matched == [nullID, barID])
  }

  @Test("equals is case-insensitive; startsWith escapes wildcards")
  func equalsAndStartsWith() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "hello", title: "Hello"),
          try Create.unsavedEpisode(guid: "literal", title: "50% off"),
          try Create.unsavedEpisode(guid: "wildcard", title: "50X off"),
        ]
      )
    )
    let helloID = series.episodes[0].id
    let literalID = series.episodes[1].id

    #expect(try await ids(for: all(.episodeText(.title, .equals, "hello"))) == [helloID])
    // `%` in input is escaped, so it only matches the literal "50%…", not "50X…".
    #expect(try await ids(for: all(.episodeText(.title, .startsWith, "50%"))) == [literalID])
  }

  @Test("contains matches a substring case-insensitively")
  func containsSubstring() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "ai", title: "All About AI"),
          try Create.unsavedEpisode(guid: "other", title: "Gardening hour"),
        ]
      )
    )
    #expect(
      try await ids(for: all(.episodeText(.title, .contains, "about")))
        == [series.episodes[0].id]
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
      nested: SmartListFilter.Group(
        combinator: .any,
        conditions: [.state(.isLoved), .state(.isLiked)]
      )
    )
    #expect(try await ids(for: filter) == [series.episodes[0].id])
  }

  // MARK: - Tags (both scopes)

  @Test("episode tag conditions partition and complement correctly")
  func episodeTagScopes() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "tagged"),
          try Create.unsavedEpisode(guid: "untagged"),
        ]
      )
    )
    let tagged = series.episodes[0].id
    let untagged = series.episodes[1].id
    let tag = try await repo.insertTag(UnsavedTag(name: "Interview"))
    try await repo.addTag(tag.id, to: tagged)

    #expect(try await ids(for: all(.episodeTag(.hasTag(tag.id)))) == [tagged])
    #expect(try await ids(for: all(.episodeTag(.doesNotHaveTag(tag.id)))) == [untagged])
    #expect(try await ids(for: all(.episodeTag(.hasAnyTag))) == [tagged])
    #expect(try await ids(for: all(.episodeTag(.hasNoTags))) == [untagged])
  }

  @Test("podcast tag conditions partition by the parent podcast's tags")
  func podcastTagScopes() async throws {
    let seriesA = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "tagged-podcast")]
      )
    )
    let seriesB = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "untagged-podcast")]
      )
    )
    let taggedEp = seriesA.episodes[0].id
    let untaggedEp = seriesB.episodes[0].id
    let tag = try await repo.insertTag(UnsavedTag(name: "Tech"))
    try await repo.addTag(tag.id, to: seriesA.id)

    #expect(try await ids(for: all(.podcastTag(.hasTag(tag.id)))) == [taggedEp])
    #expect(try await ids(for: all(.podcastTag(.hasAnyTag))) == [taggedEp])
    #expect(try await ids(for: all(.podcastTag(.doesNotHaveTag(tag.id)))) == [untaggedEp])
    #expect(try await ids(for: all(.podcastTag(.hasNoTags))) == [untaggedEp])
  }

  @Test("episode-tag and podcast-tag scopes are independent within one filter")
  func tagScopeIndependence() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "both"),
          try Create.unsavedEpisode(guid: "episode-only"),
        ]
      )
    )
    let both = series.episodes[0].id
    let episodeOnly = series.episodes[1].id
    let episodeTag = try await repo.insertTag(UnsavedTag(name: "Interview"))
    let podcastTag = try await repo.insertTag(UnsavedTag(name: "Tech"))

    try await repo.addTag(episodeTag.id, to: both)
    try await repo.addTag(episodeTag.id, to: episodeOnly)
    try await repo.addTag(podcastTag.id, to: series.id)

    // Both episodes carry the Interview episode tag and share the Tech-tagged
    // podcast, so both satisfy "episode Interview AND podcast Tech".
    let filter = all(
      .episodeTag(.hasTag(episodeTag.id)),
      .podcastTag(.hasTag(podcastTag.id))
    )
    #expect(try await ids(for: filter) == [both, episodeOnly])

    // Tag "both" alone with an episode tag: "episode-only" still carries the
    // podcast tag but lacks this episode tag, so it drops out — proving the
    // episode-tag join is evaluated independently of the podcast-tag join.
    let onlyBothTag = try await repo.insertTag(UnsavedTag(name: "Exclusive"))
    try await repo.addTag(onlyBothTag.id, to: both)
    let discriminating = all(
      .episodeTag(.hasTag(onlyBothTag.id)),
      .podcastTag(.hasTag(podcastTag.id))
    )
    #expect(try await ids(for: discriminating) == [both])
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
    #expect(try await ids(for: all(.episodeTag(.hasTag(ghost)))).isEmpty)
    #expect(try await ids(for: all(.podcastTag(.hasTag(ghost)))).isEmpty)
    // The episode still exists; the filter just excludes it.
    #expect(try await ids(for: all()) == Set(series.episodes.map(\.id)))
  }

  // MARK: - Joined Request Parity

  @Test("podcast-text and podcast-tag filters hold through the joined listable request")
  func filtersThroughJoinedRequest() async throws {
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
    let tag = try await repo.insertTag(UnsavedTag(name: "Tech"))
    try await repo.addTag(tag.id, to: techSeries.id)

    // The joined request must agree with the unjoined episodeIDs path: the
    // podcast-text subquery's `podcast` resolves to its own inner table, not the
    // request's joined `podcast`.
    #expect(try await ids(for: all(.podcastText(.title, .contains, "tech"))) == [techEp])
    #expect(try await listableIDs(for: all(.podcastText(.title, .contains, "tech"))) == [techEp])
    #expect(
      try await listableIDs(for: all(.podcastText(.title, .doesNotContain, "tech"))) == [gardenEp]
    )
    #expect(try await listableIDs(for: all(.podcastTag(.hasTag(tag.id)))) == [techEp])
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
    #expect(try await ids(for: all(.podcastText(.title, .startsWith, "the tech"))) == [techEp])
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

  @Test("publish-date windows partition around the reference date")
  func publishDateWindows() async throws {
    let reference = Self.referenceDate
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "fresh",
            pubDate: reference.addingTimeInterval(-2 * 86400)
          ),
          try Create.unsavedEpisode(
            guid: "old",
            pubDate: reference.addingTimeInterval(-30 * 86400)
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
