// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import Foundation
import GRDB
import Logging

@MainActor
final class CarPlaySmartListDetail {
  private enum State {
    case loading, failed
    case ready([ListablePodcastEpisode], fallback: Bool)
  }
  private struct RankingKey: Equatable, Sendable {
    let candidates: [CandidateEpisode]
    let revision: Int
    let available: Bool
  }
  private struct Ranking: Sendable {
    let ids: [Episode.ID]
    let fallback: Bool
  }

  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  private static let log = Log.as("CarPlaySmartListDetail")
  let list: CarPlayEpisodeList
  private(set) var definition: SmartList
  private var state = State.loading
  private var observation: Task<Void, Never>?
  private var hydration: Task<Void, Never>?
  private var candidates: [CandidateEpisode]?
  private var ranking: Ranking?
  var restricted = false { didSet { render() } }

  init(_ definition: SmartList, selection: CarPlaySelection) {
    self.definition = definition
    list = CarPlayEpisodeList(
      template: CPListTemplate(title: "Episodes", sections: []),
      selection: selection
    )
  }

  func update(_ definition: SmartList) {
    let changed =
      self.definition.filter != definition.filter
      || self.definition.sortMethod != definition.sortMethod
    self.definition = definition
    if changed {
      list.resetPage()
      start()
    } else {
      render()
    }
  }

  func start() {
    observation?.cancel()
    hydration?.cancel()
    scoring.cancel()
    candidates = nil
    ranking = nil
    state = .loading
    render()
    let definition = definition
    let filter = SmartListFilterEngine.sqlExpression(for: definition.filter)
    if definition.sortMethod == .recommendationScore {
      scoring.startObservations()
      observation = Task { [weak self] in
        guard let self else { return }
        do {
          for try await candidates in observatory.embeddedCandidateEpisodes(filter: filter) {
            try Task.checkCancellation()
            self.candidates = candidates
            scoring.refresh()
          }
        } catch {
          fail(error)
        }
      }
    } else {
      observation = Task { [weak self] in
        guard let self else { return }
        do {
          for try await episodes in observatory.listablePodcastEpisodes(
            filter: filter && definition.sortMethod.sqlFilter,
            order: definition.sortMethod.sqlOrdering
          ) {
            try Task.checkCancellation()
            state = .ready(episodes, fallback: false)
            render()
          }
        } catch {
          fail(error)
        }
      }
    }
  }

  private lazy var scoring = RecommendationScoringCoordinator<RankingKey, Ranking>(
    makeSnapshot: { [weak self] in
      guard let self, let candidates else { return nil }
      return RankingKey(
        candidates: candidates,
        revision: recommendationEngine.scoringRevision,
        available: recommendationEngine.hasScoringContext
      )
    },
    score: { [weak self] in
      guard let self, let candidates else { return .cancelled }
      guard recommendationEngine.hasScoringContext else {
        return .cacheable(
          Ranking(
            ids:
              candidates.sorted {
                $0.pubDate == $1.pubDate ? $0.id < $1.id : $0.pubDate > $1.pubDate
              }
              .map(\.id),
            fallback: true
          )
        )
      }
      do {
        let scores = try await recommendationEngine.recommendationScores(for: candidates)
        return .cacheable(
          Ranking(
            ids:
              scores.sorted {
                $0.value == $1.value ? $0.key > $1.key : $0.value > $1.value
              }
              .map(\.key),
            fallback: false
          )
        )
      } catch {
        fail(error)
        return .cancelled
      }
    },
    apply: { [weak self] in self?.hydrate($0) }
  )

  private func hydrate(_ ranking: Ranking) {
    if self.ranking?.ids == ranking.ids, self.ranking?.fallback == ranking.fallback { return }
    self.ranking = ranking
    hydration?.cancel()
    hydration = Task { [weak self] in
      guard let self else { return }
      do {
        for try await episodes in observatory.listablePodcastEpisodes(
          filter: ranking.ids.contains(Episode.Columns.id)
        ) {
          try Task.checkCancellation()
          let byID = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
          state = .ready(ranking.ids.compactMap { byID[$0] }, fallback: ranking.fallback)
          render()
        }
      } catch {
        fail(error)
      }
    }
  }

  private func fail(_ error: any Error) {
    guard !Task.isCancelled else { return }
    Self.log.caughtError("CarPlay Smart List query failed: list=\(definition.id)", error)
    state = .failed
    render()
  }

  func render() {
    list.template.showsSpinnerWhileEmpty = false
    var rows: [CarPlayEpisodeRow] = []
    var leading: [CPListItem] = []
    var header = definition.title
    let title: String
    let subtitle: String
    switch state {
    case .loading:
      list.template.showsSpinnerWhileEmpty = true
      title = "Loading episodes…"
      subtitle = definition.title
    case .failed:
      title = "Couldn't load episodes"
      subtitle = "Try again."
      let retry = CPListItem(text: "Retry", detailText: title)
      retry.handler = { [weak self] _, completion in
        completion()
        self?.start()
      }
      leading = [retry]
    case .ready(let episodes, let fallback):
      rows = episodes.map(CarPlayEpisodeRow.init)
      title = "No matching episodes"
      subtitle = fallback ? "Ranking unavailable. Showing newest first." : definition.title
      if fallback { header += " · Ranking unavailable; newest first" }
    }
    list.update(
      rows.isEmpty ? [] : [.init(title: header, episodes: rows)],
      restricted: restricted,
      leading: leading,
      emptyTitle: title,
      emptySubtitle: subtitle
    )
  }

  func stop() {
    observation?.cancel()
    hydration?.cancel()
    scoring.cancel()
    observation = nil
    hydration = nil
    candidates = nil
    list.stop()
  }
}
