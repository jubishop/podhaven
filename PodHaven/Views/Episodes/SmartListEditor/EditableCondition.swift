// Copyright Justin Bishop, 2026

import Foundation

// Mutable editing surface for one SmartListFilter group. Groups and conditions
// carry stable UUID identities so SwiftUI rows survive reorders and removals.
struct EditableGroup: Identifiable, Hashable {
  let id = UUID()
  var combinator: SmartListFilter.Combinator
  var conditions: [EditableCondition]

  init(combinator: SmartListFilter.Combinator = .all, conditions: [EditableCondition] = []) {
    self.combinator = combinator
    self.conditions = conditions
  }

  init(_ group: SmartListFilter.Group) {
    self.combinator = group.combinator
    self.conditions = group.conditions.map(EditableCondition.init)
  }
}

// Mutable editing surface for a single SmartListFilter.Condition. Every kind's
// sub-fields are retained so switching the Kind picker doesn't drop entered
// values; `condition` re-composes from only the fields the current kind uses,
// returning nil while the row is incomplete.
struct EditableCondition: Identifiable, Hashable {
  enum Kind: String, CaseIterable {
    case episodeTitle
    case episodeDescription
    case episodeTitleOrDescription
    case podcastTitle
    case podcastDescription
    case podcastTitleOrDescription
    case state
    case episodeTag
    case podcastTag
    case duration
    case publishDate

    var label: String {
      switch self {
      case .episodeTitle: return "Episode Title"
      case .episodeDescription: return "Episode Description"
      case .episodeTitleOrDescription: return "Episode Title or Description"
      case .podcastTitle: return "Podcast Title"
      case .podcastDescription: return "Podcast Description"
      case .podcastTitleOrDescription: return "Podcast Title or Description"
      case .state: return "State"
      case .episodeTag: return "Episode Tag"
      case .podcastTag: return "Podcast Tag"
      case .duration: return "Duration"
      case .publishDate: return "Publish Date"
      }
    }
  }

  enum TagMembership: String, CaseIterable {
    case hasTag
    case doesNotHaveTag
    case hasAnyTag
    case hasNoTags

    var label: String {
      switch self {
      case .hasTag: return "has tag"
      case .doesNotHaveTag: return "doesn't have tag"
      case .hasAnyTag: return "has any tag"
      case .hasNoTags: return "has no tags"
      }
    }
  }

  let id = UUID()
  var kind: Kind = .episodeTitle
  var textOp: SmartListFilter.TextOp = .contains
  var text: String = ""
  var state: SmartListFilter.StateCondition = .isUnqueued
  var tagMembership: TagMembership = .hasAnyTag
  var tagID: Tag.ID?
  var minMinutesText: String = ""
  var maxMinutesText: String = ""
  var publishDateOp: SmartListFilter.PublishDateOp = .withinLast
  var daysText: String = ""

  init() {}

  init(_ condition: SmartListFilter.Condition) {
    switch condition {
    case .episodeText(let field, let op, let value):
      switch field {
      case .title: kind = .episodeTitle
      case .description: kind = .episodeDescription
      case .titleOrDescription: kind = .episodeTitleOrDescription
      }
      textOp = op
      text = value
    case .podcastText(let field, let op, let value):
      switch field {
      case .title: kind = .podcastTitle
      case .description: kind = .podcastDescription
      case .titleOrDescription: kind = .podcastTitleOrDescription
      }
      textOp = op
      text = value
    case .state(let state):
      kind = .state
      self.state = state
    case .episodeTag(let tagCondition):
      kind = .episodeTag
      apply(tagCondition)
    case .podcastTag(let tagCondition):
      kind = .podcastTag
      apply(tagCondition)
    case .duration(let minSeconds, let maxSeconds):
      kind = .duration
      if let minSeconds { minMinutesText = String(minSeconds / 60) }
      if let maxSeconds { maxMinutesText = String(maxSeconds / 60) }
    case .publishDate(let op, let days):
      kind = .publishDate
      publishDateOp = op
      daysText = String(days)
    }
  }

  private mutating func apply(_ tagCondition: SmartListFilter.TagCondition) {
    switch tagCondition {
    case .hasTag(let id):
      tagMembership = .hasTag
      tagID = id
    case .doesNotHaveTag(let id):
      tagMembership = .doesNotHaveTag
      tagID = id
    case .hasAnyTag:
      tagMembership = .hasAnyTag
    case .hasNoTags:
      tagMembership = .hasNoTags
    }
  }

  // MARK: - Composition

  var condition: SmartListFilter.Condition? {
    switch kind {
    case .episodeTitle:
      guard !trimmedText.isEmpty else { return nil }
      return .episodeText(.title, textOp, trimmedText)
    case .episodeDescription:
      guard !trimmedText.isEmpty else { return nil }
      return .episodeText(.description, textOp, trimmedText)
    case .episodeTitleOrDescription:
      guard !trimmedText.isEmpty else { return nil }
      return .episodeText(.titleOrDescription, textOp, trimmedText)
    case .podcastTitle:
      guard !trimmedText.isEmpty else { return nil }
      return .podcastText(.title, textOp, trimmedText)
    case .podcastDescription:
      guard !trimmedText.isEmpty else { return nil }
      return .podcastText(.description, textOp, trimmedText)
    case .podcastTitleOrDescription:
      guard !trimmedText.isEmpty else { return nil }
      return .podcastText(.titleOrDescription, textOp, trimmedText)
    case .state:
      return .state(state)
    case .episodeTag:
      guard let tagCondition else { return nil }
      return .episodeTag(tagCondition)
    case .podcastTag:
      guard let tagCondition else { return nil }
      return .podcastTag(tagCondition)
    case .duration:
      guard let durationBounds else { return nil }
      return .duration(
        minSeconds: durationBounds.minSeconds,
        maxSeconds: durationBounds.maxSeconds
      )
    case .publishDate:
      guard let days = Self.parseDays(daysText) else { return nil }
      return .publishDate(publishDateOp, days: days)
    }
  }

  var validationMessage: String? {
    guard condition == nil else { return nil }
    switch kind {
    case .episodeTitle, .episodeDescription, .episodeTitleOrDescription,
      .podcastTitle, .podcastDescription, .podcastTitleOrDescription:
      return "Enter text to match"
    case .state:
      return nil
    case .episodeTag, .podcastTag:
      return "Select a tag"
    case .duration:
      return durationValidationMessage
    case .publishDate:
      return "Enter a number of days"
    }
  }

  // MARK: - Field Parsing

  private var trimmedText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var tagCondition: SmartListFilter.TagCondition? {
    switch tagMembership {
    case .hasTag:
      guard let tagID else { return nil }
      return .hasTag(tagID)
    case .doesNotHaveTag:
      guard let tagID else { return nil }
      return .doesNotHaveTag(tagID)
    case .hasAnyTag:
      return .hasAnyTag
    case .hasNoTags:
      return .hasNoTags
    }
  }

  private enum MinutesField: Equatable {
    case empty
    case invalid
    case minutes(Int)
  }

  // Generous ceiling on entered minutes that keeps the seconds conversion far
  // from Int overflow.
  private static let maxMinutes = 1_000_000

  private static func parseMinutes(_ text: String) -> MinutesField {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return .empty }
    guard let minutes = Int(trimmed), (0...maxMinutes).contains(minutes) else { return .invalid }
    return .minutes(minutes)
  }

  private static func parseDays(_ text: String) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let days = Int(trimmed), days >= 1 else { return nil }
    return days
  }

  private struct DurationBounds {
    let minSeconds: Int?
    let maxSeconds: Int?
  }

  private var durationBounds: DurationBounds? {
    let minField = Self.parseMinutes(minMinutesText)
    let maxField = Self.parseMinutes(maxMinutesText)
    switch (minField, maxField) {
    case (.invalid, _), (_, .invalid), (.empty, .empty):
      return nil
    case (.empty, .minutes(let max)):
      return DurationBounds(minSeconds: nil, maxSeconds: max * 60)
    case (.minutes(let min), .empty):
      return DurationBounds(minSeconds: min * 60, maxSeconds: nil)
    case (.minutes(let min), .minutes(let max)):
      guard min <= max else { return nil }
      return DurationBounds(minSeconds: min * 60, maxSeconds: max * 60)
    }
  }

  private var durationValidationMessage: String {
    let minField = Self.parseMinutes(minMinutesText)
    let maxField = Self.parseMinutes(maxMinutesText)
    if minField == .invalid || maxField == .invalid {
      return "Durations must be whole minutes"
    }
    if case (.minutes(let min), .minutes(let max)) = (minField, maxField), min > max {
      return "Minimum duration exceeds maximum"
    }
    return "Enter a minimum or maximum duration"
  }
}
