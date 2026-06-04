// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// Pure translation of a SmartListFilter into a flat SQLExpression suitable for
// `Observatory.listablePodcastEpisodes(filter:)`. Two-level walk only: the top
// group's conditions, optionally AND/OR'd with a single nested group's combined
// expression. `referenceDate` is injected so publish-date windows are
// deterministic and testable. All expressions are evaluated against the
// `episode` base table; tag and podcast-text predicates use subqueries since the
// observation request takes only a flat expression (no joins/request builder).
enum SmartListFilterEngine {
  static func sqlExpression(
    for filter: SmartListFilter,
    referenceDate: Date
  ) -> SQLExpression {
    var terms = filter.conditions.map { expression(for: $0, referenceDate: referenceDate) }
    if let nested = filter.nested, !nested.conditions.isEmpty {
      let nestedTerms = nested.conditions.map { expression(for: $0, referenceDate: referenceDate) }
      terms.append(combine(nestedTerms, with: nested.combinator))
    }
    return combine(terms, with: filter.combinator)
  }

  // Empty → no-op (match-all). `any` seeds the reduce with the first term rather
  // than a no-op, which would short-circuit the disjunction to always-true.
  private static func combine(
    _ terms: [SQLExpression],
    with combinator: SmartListFilter.Combinator
  ) -> SQLExpression {
    guard let first = terms.first else { return AppDB.noOp }
    switch combinator {
    case .all:
      return terms.dropFirst().reduce(first) { $0 && $1 }
    case .any:
      return terms.dropFirst().reduce(first) { $0 || $1 }
    }
  }

  private static func expression(
    for condition: SmartListFilter.Condition,
    referenceDate: Date
  ) -> SQLExpression {
    switch condition {
    case .episodeText(let field, let op, let value):
      return episodeTextExpression(field, op, value)
    case .podcastText(let field, let op, let value):
      return podcastTextExpression(field, op, value)
    case .state(let state):
      return stateExpression(state)
    case .episodeTag(let tagCondition):
      return episodeTagExpression(tagCondition)
    case .podcastTag(let tagCondition):
      return podcastTagExpression(tagCondition)
    case .duration(let minSeconds, let maxSeconds):
      return durationExpression(minSeconds: minSeconds, maxSeconds: maxSeconds)
    case .publishDate(let op, let days):
      return publishDateExpression(op, days: days, referenceDate: referenceDate)
    }
  }

  // MARK: - State

  private static func stateExpression(_ state: SmartListFilter.StateCondition) -> SQLExpression {
    switch state {
    case .isQueued: return Episode.queued
    case .isUnqueued: return Episode.unqueued
    case .isFinished: return Episode.finished
    case .isUnfinished: return Episode.unfinished
    case .isStarted: return Episode.started
    case .isUnstarted: return Episode.unstarted
    case .isCached: return Episode.cached
    case .isSaved: return Episode.savedInCache
    case .isLoved: return Episode.loved
    case .isLiked: return Episode.liked
    case .isDisliked: return Episode.disliked
    case .isNotInterested: return Episode.notInterested
    case .isRated: return Episode.rated
    case .isUnrated: return !Episode.rated
    case .wasPreviouslyQueued: return Episode.previouslyQueued
    }
  }

  // MARK: - Text

  // SQLite `lower()` ASCII-folds both sides; `%`/`_`/`\` in user input are
  // escaped and matched literally via `ESCAPE '\'` so only the added wildcards
  // act as wildcards.
  private static func escapeLike(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
  }

  private static func episodeTextExpression(
    _ field: SmartListFilter.TextField,
    _ op: SmartListFilter.TextOp,
    _ value: String
  ) -> SQLExpression {
    let column = field == .title ? "episode.title" : "episode.description"
    switch op {
    case .contains:
      return SQL(
        sql: "lower(\(column)) LIKE lower(?) ESCAPE '\\'",
        arguments: ["%\(escapeLike(value))%"]
      )
      .sqlExpression
    case .startsWith:
      return SQL(
        sql: "lower(\(column)) LIKE lower(?) ESCAPE '\\'",
        arguments: ["\(escapeLike(value))%"]
      )
      .sqlExpression
    case .equals:
      return SQL(sql: "lower(\(column)) = lower(?)", arguments: [value]).sqlExpression
    case .doesNotContain:
      // Null-safe: `NOT (NULL LIKE ?)` is NULL, which would wrongly drop
      // null-description rows, so include them explicitly.
      return SQL(
        sql: "(\(column) IS NULL OR NOT (lower(\(column)) LIKE lower(?) ESCAPE '\\'))",
        arguments: ["%\(escapeLike(value))%"]
      )
      .sqlExpression
    }
  }

  private static func podcastTextExpression(
    _ field: SmartListFilter.TextField,
    _ op: SmartListFilter.TextOp,
    _ value: String
  ) -> SQLExpression {
    let column = field == .title ? "p.title" : "p.description"
    // `p` aliases the subquery's own podcast row, isolating it from the
    // observation request's joined `podcast` scope.
    switch op {
    case .contains:
      return SQL(
        sql:
          "episode.podcastId IN (SELECT p.id FROM podcast p WHERE lower(\(column)) LIKE lower(?) ESCAPE '\\')",
        arguments: ["%\(escapeLike(value))%"]
      )
      .sqlExpression
    case .startsWith:
      return SQL(
        sql:
          "episode.podcastId IN (SELECT p.id FROM podcast p WHERE lower(\(column)) LIKE lower(?) ESCAPE '\\')",
        arguments: ["\(escapeLike(value))%"]
      )
      .sqlExpression
    case .equals:
      return SQL(
        sql: "episode.podcastId IN (SELECT p.id FROM podcast p WHERE lower(\(column)) = lower(?))",
        arguments: [value]
      )
      .sqlExpression
    case .doesNotContain:
      return SQL(
        sql:
          "episode.podcastId NOT IN (SELECT p.id FROM podcast p WHERE lower(\(column)) LIKE lower(?) ESCAPE '\\')",
        arguments: ["%\(escapeLike(value))%"]
      )
      .sqlExpression
    }
  }

  // MARK: - Tags

  // `episodeTag.episodeId` is NOT NULL, so plain `IN`/`NOT IN` are null-safe. An
  // unresolved tag yields an empty subquery, so `hasTag` matches nothing.
  private static func episodeTagExpression(
    _ condition: SmartListFilter.TagCondition
  ) -> SQLExpression {
    switch condition {
    case .hasTag(let tagID):
      return episodeTagMembers(tagID).contains(Episode.Columns.id)
    case .doesNotHaveTag(let tagID):
      return !episodeTagMembers(tagID).contains(Episode.Columns.id)
    case .hasAnyTag:
      return episodeTagMembers(nil).contains(Episode.Columns.id)
    case .hasNoTags:
      return !episodeTagMembers(nil).contains(Episode.Columns.id)
    }
  }

  private static func episodeTagMembers(
    _ tagID: Tag.ID?
  ) -> QueryInterfaceRequest<EpisodeTag> {
    let request = EpisodeTag.select(EpisodeTag.Columns.episodeId)
    guard let tagID else { return request }
    return request.filter(EpisodeTag.Columns.tagId == tagID)
  }

  // `episode.podcastId` is NOT NULL (FK with cascade delete), so every episode
  // has a parent podcast and plain `IN`/`NOT IN` are null-safe. An unresolved
  // tag yields an empty subquery, so `hasTag` matches nothing.
  private static func podcastTagExpression(
    _ condition: SmartListFilter.TagCondition
  ) -> SQLExpression {
    switch condition {
    case .hasTag(let tagID):
      return podcastTagMembers(tagID).contains(Episode.Columns.podcastId)
    case .doesNotHaveTag(let tagID):
      return !podcastTagMembers(tagID).contains(Episode.Columns.podcastId)
    case .hasAnyTag:
      return podcastTagMembers(nil).contains(Episode.Columns.podcastId)
    case .hasNoTags:
      return !podcastTagMembers(nil).contains(Episode.Columns.podcastId)
    }
  }

  private static func podcastTagMembers(
    _ tagID: Tag.ID?
  ) -> QueryInterfaceRequest<PodcastTag> {
    let request = PodcastTag.select(PodcastTag.Columns.podcastId)
    guard let tagID else { return request }
    return request.filter(PodcastTag.Columns.tagId == tagID)
  }

  // MARK: - Duration & Publish Date

  // `duration` stores seconds. `min = 0` includes the shortest episodes.
  private static func durationExpression(minSeconds: Int?, maxSeconds: Int?) -> SQLExpression {
    var terms: [SQLExpression] = []
    if let minSeconds { terms.append(Episode.Columns.duration >= Double(minSeconds)) }
    if let maxSeconds { terms.append(Episode.Columns.duration <= Double(maxSeconds)) }
    return combine(terms, with: .all)
  }

  private static func publishDateExpression(
    _ op: SmartListFilter.PublishDateOp,
    days: Int,
    referenceDate: Date
  ) -> SQLExpression {
    let secondsPerDay = 86_400.0
    let cutoff = referenceDate.addingTimeInterval(-Double(days) * secondsPerDay)
    switch op {
    case .withinLast:
      return Episode.Columns.pubDate >= cutoff
    case .olderThan:
      return Episode.Columns.pubDate < cutoff
    }
  }
}
