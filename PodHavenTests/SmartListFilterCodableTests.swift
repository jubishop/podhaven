// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of SmartListFilter Codable tests")
struct SmartListFilterCodableTests {
  // The 10 seeded defaults, as values (mirrors Migration_v54's JSON literals).
  private static let defaults: [SmartListFilter] = [
    SmartListFilter(combinator: .all, conditions: [], groups: []),
    SmartListFilter(combinator: .all, conditions: [.state(.isUnqueued), .state(.isUnfinished)]),
    SmartListFilter(combinator: .all, conditions: [.state(.isCached)]),
    SmartListFilter(combinator: .all, conditions: [.state(.isSaved)]),
    SmartListFilter(combinator: .all, conditions: [.state(.isFinished)]),
    SmartListFilter(combinator: .all, conditions: [.state(.isUnfinished), .state(.isStarted)]),
    SmartListFilter(combinator: .all, conditions: [.state(.wasPreviouslyQueued)]),
    SmartListFilter(combinator: .any, conditions: [.state(.isLiked), .state(.isLoved)]),
    SmartListFilter(combinator: .all, conditions: [.state(.isDisliked)]),
    SmartListFilter(combinator: .all, conditions: [.state(.isNotInterested)]),
  ]

  // Exercises every condition kind and multiple nested groups.
  private static let complex = SmartListFilter(
    combinator: .all,
    conditions: [
      .episodeText(.title, .contains, "AI"),
      .episodeText(.titleOrDescription, .contains, "space"),
      .podcastText(.description, .doesNotContain, "sports"),
      .podcastText(.titleOrDescription, .doesNotContain, "ads"),
      .state(.isUnrated),
      .state(.isUncached),
      .tag(.hasTag(Tag.ID(rawValue: 3))),
      .tag(.doesNotHaveTag(Tag.ID(rawValue: 7))),
      .duration(minSeconds: 0, maxSeconds: 3600),
      .publishDate(.withinLast, days: 30),
    ],
    groups: [
      SmartListFilter.Group(
        combinator: .any,
        conditions: [
          .state(.isLoved),
          .tag(.hasAnyTag),
          .tag(.hasNoTags),
          .duration(minSeconds: 600, maxSeconds: nil),
          .publishDate(.olderThan, days: 365),
        ]
      ),
      SmartListFilter.Group(
        combinator: .all,
        conditions: [.state(.isUnqueued), .episodeText(.description, .contains, "Bonus")]
      ),
    ]
  )

  private func roundTrip(_ filter: SmartListFilter) throws {
    // `.sortedKeys` is required for a byte comparison: JSONEncoder's key order is
    // otherwise unspecified, so two encodes of the same value can differ.
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let encoded = try encoder.encode(filter)
    let decoded = try JSONDecoder().decode(SmartListFilter.self, from: encoded)
    #expect(decoded == filter)
    #expect(try encoder.encode(decoded) == encoded)
  }

  @Test("each seeded default round-trips")
  func defaultsRoundTrip() throws {
    for filter in Self.defaults {
      try roundTrip(filter)
    }
  }

  @Test("a filter with multiple nested groups and every kind round-trips")
  func complexRoundTrips() throws {
    try roundTrip(Self.complex)
  }

  @Test("stored JSON (post-v56 shape) decodes to the expected value")
  func storedJSONDecodes() throws {
    let liked = Data(
      #"{"combinator":"any","conditions":[{"kind":"state","value":"isLiked"},{"kind":"state","value":"isLoved"}],"groups":[]}"#
        .utf8
    )
    let decoded = try JSONDecoder().decode(SmartListFilter.self, from: liked)
    #expect(
      decoded
        == SmartListFilter(combinator: .any, conditions: [.state(.isLiked), .state(.isLoved)])
    )
  }

  // The v56 migration rewrites every stored row to carry a `groups` array, so
  // the decoder requires the key rather than tolerating the pre-v56 shape.
  @Test("decoding JSON without a groups key throws")
  func missingGroupsKeyThrows() {
    let legacy = Data(#"{"combinator":"all","conditions":[],"nested":null}"#.utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(SmartListFilter.self, from: legacy)
    }
  }

  @Test("tag conditions nest under `tag` without colliding with the condition kind")
  func tagConditionEncoding() throws {
    let filter = SmartListFilter(
      combinator: .all,
      conditions: [.tag(.hasTag(Tag.ID(rawValue: 42)))]
    )
    let json = try #require(String(data: try JSONEncoder().encode(filter), encoding: .utf8))
    #expect(json.contains(#""kind":"tag""#))
    #expect(json.contains(#""kind":"hasTag""#))
    #expect(json.contains(#""tagID":42"#))
    try roundTrip(filter)
  }

  @Test("decoding an unknown Condition kind throws")
  func unknownConditionKindThrows() {
    let json = Data(#"{"kind":"telepathy","value":"isLoved"}"#.utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(SmartListFilter.Condition.self, from: json)
    }
  }

  @Test("decoding an unknown TagCondition kind throws")
  func unknownTagConditionKindThrows() {
    let json = Data(#"{"kind":"hasMostTags","tagID":1}"#.utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(SmartListFilter.TagCondition.self, from: json)
    }
  }
}
