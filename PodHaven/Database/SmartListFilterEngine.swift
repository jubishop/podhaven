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
    case .tag(let tagCondition):
      return tagExpression(tagCondition)
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
    case .isUncached: return !Episode.cached
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

  // contains/doesNotContain match the value as a phrase: its tokens contiguous
  // and in order (whole words, no prefixes), appearing anywhere in the field,
  // through the FTS5 mirrors (episode_fts/podcast_fts, kept in sync by triggers),
  // scoped to the queried column so a title filter ignores description text.
  // titleOrDescription matches the whole virtual table; an FTS5 phrase never
  // spans columns, so that is exactly the phrase appearing in title or in
  // description. Each mirror's rowid is its source row's id, so the subquery
  // resolves straight back. A value with no tokenizable content yields no
  // pattern: contains then matches nothing and doesNotContain matches everything.
  private static let matchNone = false.sqlExpression

  private static func episodeTextExpression(
    _ field: SmartListFilter.TextField,
    _ op: SmartListFilter.TextOp,
    _ value: String
  ) -> SQLExpression {
    switch op {
    case .contains:
      return episodeTextMatches(field, value) ?? matchNone
    case .doesNotContain:
      guard let matches = episodeTextMatches(field, value) else { return AppDB.noOp }
      return !matches
    }
  }

  private static func episodeTextMatches(
    _ field: SmartListFilter.TextField,
    _ value: String
  ) -> SQLExpression? {
    guard let pattern = FTS5Pattern(matchingPhrase: value) else { return nil }
    return ftsRowIDs(EpisodeFTS.self, field, pattern).contains(Episode.Columns.id)
  }

  private static func podcastTextExpression(
    _ field: SmartListFilter.TextField,
    _ op: SmartListFilter.TextOp,
    _ value: String
  ) -> SQLExpression {
    switch op {
    case .contains:
      return podcastTextMatches(field, value) ?? matchNone
    case .doesNotContain:
      guard let matches = podcastTextMatches(field, value) else { return AppDB.noOp }
      return !matches
    }
  }

  private static func podcastTextMatches(
    _ field: SmartListFilter.TextField,
    _ value: String
  ) -> SQLExpression? {
    guard let pattern = FTS5Pattern(matchingPhrase: value) else { return nil }
    return ftsRowIDs(PodcastFTS.self, field, pattern).contains(Episode.Columns.podcastId)
  }

  // Rowids of the FTS mirror whose indexed text matches `pattern` in `field`.
  // title/description filter a single column; titleOrDescription matches the
  // whole virtual table, which spans both indexed columns.
  private static func ftsRowIDs<Mirror: TableRecord>(
    _ mirror: Mirror.Type,
    _ field: SmartListFilter.TextField,
    _ pattern: FTS5Pattern
  ) -> QueryInterfaceRequest<Mirror> {
    switch field {
    case .title:
      return Mirror.filter(Column("title").match(pattern)).select(Column.rowID)
    case .description:
      return Mirror.filter(Column("description").match(pattern)).select(Column.rowID)
    case .titleOrDescription:
      return Mirror.matching(pattern).select(Column.rowID)
    }
  }

  // MARK: - Tags

  // A Smart List tag condition matches the effective tags of the episode: tags
  // attached directly to the episode OR tags attached to its parent podcast.
  private static func tagExpression(
    _ condition: SmartListFilter.TagCondition
  ) -> SQLExpression {
    switch condition {
    case .hasTag(let tagID):
      return hasEffectiveTag(tagID)
    case .doesNotHaveTag(let tagID):
      return !hasEffectiveTag(tagID)
    case .hasAnyTag:
      return hasEffectiveTag(nil)
    case .hasNoTags:
      return !hasEffectiveTag(nil)
    }
  }

  private static func hasEffectiveTag(_ tagID: Tag.ID?) -> SQLExpression {
    episodeTagMembers(tagID).contains(Episode.Columns.id)
      || podcastTagMembers(tagID).contains(Episode.Columns.podcastId)
  }

  // `episodeTag.episodeId` is NOT NULL, so plain `IN`/`NOT IN` are null-safe. An
  // unresolved tag yields an empty subquery.
  private static func episodeTagMembers(
    _ tagID: Tag.ID?
  ) -> QueryInterfaceRequest<EpisodeTag> {
    let request = EpisodeTag.select(EpisodeTag.Columns.episodeId)
    guard let tagID else { return request }
    return request.filter(EpisodeTag.Columns.tagId == tagID)
  }

  // `episode.podcastId` is NOT NULL (FK with cascade delete), so every episode
  // has a parent podcast and plain `IN`/`NOT IN` are null-safe. An unresolved
  // tag yields an empty subquery.
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
