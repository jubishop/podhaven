// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// Pure translation of a SmartListFilter into a flat SQLExpression suitable for
// `Observatory.listablePodcastEpisodes(filter:)`. Two-level walk only: the top
// group's conditions, AND/OR'd with each nested group's combined expression as
// one extra term. `referenceDate` is injected so publish-date windows are
// deterministic and testable. All expressions are evaluated against the
// `episode` base table; tag and podcast-text predicates use subqueries since the
// observation request takes only a flat expression (no joins/request builder).
enum SmartListFilterEngine {
  static func sqlExpression(
    for filter: SmartListFilter,
    referenceDate: Date
  ) -> SQLExpression {
    var terms = filter.conditions.map { expression(for: $0, referenceDate: referenceDate) }
    for group in filter.groups where !group.conditions.isEmpty {
      let groupTerms = group.conditions.map { expression(for: $0, referenceDate: referenceDate) }
      terms.append(combine(groupTerms, with: group.combinator))
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

  // SQLite's LIKE is ASCII case-insensitive, so it carries the case-folding;
  // `%`/`_`/`\` in user input are escaped here and matched literally via
  // `ESCAPE '\'` so only the added wildcards act as wildcards.
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
    let column = field == .title ? Episode.Columns.title : Episode.Columns.description
    switch op {
    case .contains:
      return column.like("%\(escapeLike(value))%", escape: "\\")
    case .startsWith:
      return column.like("\(escapeLike(value))%", escape: "\\")
    case .equals:
      return column.collating(.nocase) == value
    case .doesNotContain:
      // NOT (NULL LIKE ?) is NULL, which would drop null-description rows, so
      // include them explicitly.
      return column == nil || !column.like("%\(escapeLike(value))%", escape: "\\")
    }
  }

  // The podcast-text predicate runs in a subquery GRDB auto-aliases, isolating
  // it from the observation request's joined `podcast` scope.
  private static func podcastTextExpression(
    _ field: SmartListFilter.TextField,
    _ op: SmartListFilter.TextOp,
    _ value: String
  ) -> SQLExpression {
    let column = field == .title ? Podcast.Columns.title : Podcast.Columns.description
    let predicate: SQLExpression
    let negate: Bool
    switch op {
    case .contains:
      predicate = column.like("%\(escapeLike(value))%", escape: "\\")
      negate = false
    case .startsWith:
      predicate = column.like("\(escapeLike(value))%", escape: "\\")
      negate = false
    case .equals:
      predicate = column.collating(.nocase) == value
      negate = false
    case .doesNotContain:
      predicate = column.like("%\(escapeLike(value))%", escape: "\\")
      negate = true
    }
    let matches =
      Podcast
      .select(Podcast.Columns.id)
      .filter(predicate)
      .contains(Episode.Columns.podcastId)
    return negate ? !matches : matches
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
