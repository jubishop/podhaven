// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Logging

// Flat, non-recursive filter value: a top group of conditions plus any number
// of nested groups, each holding only conditions (no deeper recursion). Each
// Condition/TagCondition writes an explicit `kind` discriminator in its Codable
// so new kinds can't break previously-saved JSON.
struct SmartListFilter: Codable, Hashable, Sendable {
  private static let log = Log.as("SmartListFilter")

  var combinator: Combinator
  var conditions: [Condition]
  var groups: [Group]

  init(combinator: Combinator = .all, conditions: [Condition] = [], groups: [Group] = []) {
    self.combinator = combinator
    self.conditions = conditions
    self.groups = groups
  }

  struct Group: Codable, Hashable, Sendable {
    var combinator: Combinator
    var conditions: [Condition]

    init(combinator: Combinator = .all, conditions: [Condition] = []) {
      self.combinator = combinator
      self.conditions = conditions
    }
  }

  enum Combinator: String, Codable, Sendable {
    case all
    case any
  }

  enum TextField: String, Codable, Sendable {
    case title
    case description
  }

  enum TextOp: String, Codable, Sendable, CaseIterable {
    case contains
    case doesNotContain
    case equals
  }

  enum PublishDateOp: String, Codable, Sendable, CaseIterable {
    case withinLast
    case olderThan
  }

  enum StateCondition: String, Codable, Sendable, CaseIterable {
    case isQueued
    case isUnqueued
    case isFinished
    case isUnfinished
    case isStarted
    case isUnstarted
    case isCached
    case isSaved
    case isLoved
    case isLiked
    case isDisliked
    case isNotInterested
    case isRated
    case isUnrated
    case wasPreviouslyQueued
  }

  // Shared by both .episodeTag and .podcastTag — only the join path differs at
  // SQL time. Nested under the Condition's `tag` key so its own `kind` doesn't
  // collide with the Condition discriminator.
  enum TagCondition: Codable, Hashable, Sendable {
    case hasTag(Tag.ID)
    case doesNotHaveTag(Tag.ID)
    case hasAnyTag
    case hasNoTags

    private enum CodingKeys: String, CodingKey {
      case kind
      case tagID
    }
    private enum Kind: String {
      case hasTag
      case doesNotHaveTag
      case hasAnyTag
      case hasNoTags
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let kind = try container.decode(String.self, forKey: .kind)
      switch kind {
      case Kind.hasTag.rawValue:
        self = .hasTag(try container.decode(Tag.ID.self, forKey: .tagID))
      case Kind.doesNotHaveTag.rawValue:
        self = .doesNotHaveTag(try container.decode(Tag.ID.self, forKey: .tagID))
      case Kind.hasAnyTag.rawValue:
        self = .hasAnyTag
      case Kind.hasNoTags.rawValue:
        self = .hasNoTags
      default:
        throw DecodingError.dataCorruptedError(
          forKey: .kind,
          in: container,
          debugDescription: "Unknown SmartListFilter.TagCondition kind '\(kind)'"
        )
      }
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .hasTag(let id):
        try container.encode(Kind.hasTag.rawValue, forKey: .kind)
        try container.encode(id, forKey: .tagID)
      case .doesNotHaveTag(let id):
        try container.encode(Kind.doesNotHaveTag.rawValue, forKey: .kind)
        try container.encode(id, forKey: .tagID)
      case .hasAnyTag:
        try container.encode(Kind.hasAnyTag.rawValue, forKey: .kind)
      case .hasNoTags:
        try container.encode(Kind.hasNoTags.rawValue, forKey: .kind)
      }
    }
  }

  enum Condition: Codable, Hashable, Sendable {
    case episodeText(TextField, TextOp, String)
    case podcastText(TextField, TextOp, String)
    case state(StateCondition)
    case episodeTag(TagCondition)
    case podcastTag(TagCondition)
    case duration(minSeconds: Int?, maxSeconds: Int?)
    case publishDate(PublishDateOp, days: Int)

    private enum CodingKeys: String, CodingKey {
      case kind
      case field
      case op
      case value
      case tag
      case minSeconds
      case maxSeconds
      case days
    }
    private enum Kind: String {
      case episodeText
      case podcastText
      case state
      case episodeTag
      case podcastTag
      case duration
      case publishDate
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let kind = try container.decode(String.self, forKey: .kind)
      switch kind {
      case Kind.episodeText.rawValue:
        self = .episodeText(
          try container.decode(TextField.self, forKey: .field),
          try container.decode(TextOp.self, forKey: .op),
          try container.decode(String.self, forKey: .value)
        )
      case Kind.podcastText.rawValue:
        self = .podcastText(
          try container.decode(TextField.self, forKey: .field),
          try container.decode(TextOp.self, forKey: .op),
          try container.decode(String.self, forKey: .value)
        )
      case Kind.state.rawValue:
        self = .state(try container.decode(StateCondition.self, forKey: .value))
      case Kind.episodeTag.rawValue:
        self = .episodeTag(try container.decode(TagCondition.self, forKey: .tag))
      case Kind.podcastTag.rawValue:
        self = .podcastTag(try container.decode(TagCondition.self, forKey: .tag))
      case Kind.duration.rawValue:
        self = .duration(
          minSeconds: try container.decodeIfPresent(Int.self, forKey: .minSeconds),
          maxSeconds: try container.decodeIfPresent(Int.self, forKey: .maxSeconds)
        )
      case Kind.publishDate.rawValue:
        self = .publishDate(
          try container.decode(PublishDateOp.self, forKey: .op),
          days: try container.decode(Int.self, forKey: .days)
        )
      default:
        throw DecodingError.dataCorruptedError(
          forKey: .kind,
          in: container,
          debugDescription: "Unknown SmartListFilter.Condition kind '\(kind)'"
        )
      }
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .episodeText(let field, let op, let value):
        try container.encode(Kind.episodeText.rawValue, forKey: .kind)
        try container.encode(field, forKey: .field)
        try container.encode(op, forKey: .op)
        try container.encode(value, forKey: .value)
      case .podcastText(let field, let op, let value):
        try container.encode(Kind.podcastText.rawValue, forKey: .kind)
        try container.encode(field, forKey: .field)
        try container.encode(op, forKey: .op)
        try container.encode(value, forKey: .value)
      case .state(let state):
        try container.encode(Kind.state.rawValue, forKey: .kind)
        try container.encode(state, forKey: .value)
      case .episodeTag(let tag):
        try container.encode(Kind.episodeTag.rawValue, forKey: .kind)
        try container.encode(tag, forKey: .tag)
      case .podcastTag(let tag):
        try container.encode(Kind.podcastTag.rawValue, forKey: .kind)
        try container.encode(tag, forKey: .tag)
      case .duration(let minSeconds, let maxSeconds):
        try container.encode(Kind.duration.rawValue, forKey: .kind)
        try container.encodeIfPresent(minSeconds, forKey: .minSeconds)
        try container.encodeIfPresent(maxSeconds, forKey: .maxSeconds)
      case .publishDate(let op, let days):
        try container.encode(Kind.publishDate.rawValue, forKey: .kind)
        try container.encode(op, forKey: .op)
        try container.encode(days, forKey: .days)
      }
    }

    // Whether this condition references `tag` in either tag scope.
    func references(_ tag: Tag.ID) -> Bool {
      switch self {
      case .episodeTag(let condition), .podcastTag(let condition):
        switch condition {
        case .hasTag(let id), .doesNotHaveTag(let id):
          return id == tag
        case .hasAnyTag, .hasNoTags:
          return false
        }
      case .episodeText, .podcastText, .state, .duration, .publishDate:
        return false
      }
    }
  }

  // Drops any condition naming `tag` from the top group and every nested
  // group; an emptied nested group is removed entirely, and an emptied top
  // group falls back to match-all (the engine treats empty top + no groups as
  // no-op).
  func removingTag(_ tag: Tag.ID) -> SmartListFilter {
    var result = self
    result.conditions.removeAll { $0.references(tag) }
    result.groups = result.groups.compactMap { group in
      var group = group
      group.conditions.removeAll { $0.references(tag) }
      return group.conditions.isEmpty ? nil : group
    }
    return result
  }
}

// MARK: - DatabaseValueConvertible

// Bridges the filter to the smartList.filter TEXT column as JSON. GRDB's Codable
// record encoding prefers DatabaseValueConvertible over nested-JSON, so the
// filter stores and reloads through this single, self-contained path.
extension SmartListFilter: DatabaseValueConvertible {
  var databaseValue: DatabaseValue {
    do {
      return String(decoding: try JSONEncoder().encode(self), as: UTF8.self).databaseValue
    } catch {
      Self.log.caughtError("Failed to encode SmartListFilter to JSON", error)
      return .null
    }
  }

  static func fromDatabaseValue(_ dbValue: DatabaseValue) -> SmartListFilter? {
    guard let string = String.fromDatabaseValue(dbValue) else { return nil }
    do {
      return try JSONDecoder().decode(SmartListFilter.self, from: Data(string.utf8))
    } catch {
      log.caughtError("Failed to decode SmartListFilter from JSON", error)
      return nil
    }
  }
}
