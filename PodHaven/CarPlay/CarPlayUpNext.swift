// Copyright Justin Bishop, 2026

import FactoryKit
import GRDB
import Logging

extension Container {
  @MainActor var carPlayUpNext: Factory<CarPlayUpNext> {
    Factory(self) { CarPlayUpNext() }
  }
}

@MainActor
final class CarPlayUpNext {
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.userSettings) private var userSettings
  @DynamicInjected(\.observatory) private var observatory
  private static let log = Log.as("CarPlayUpNext")
  private var observation: Task<Void, Never>?
  private var currentObservation: Task<Void, Never>?
  private var recommendationsObservation: Task<Void, Never>?
  private var current: CarPlayEpisodeRow?
  private var recommendations: [Episode.ID: CarPlayEpisodeRow] = [:]
  private var list: CarPlayEpisodeList?
  var restricted = false { didSet { render() } }

  fileprivate init() {}

  func start(_ list: CarPlayEpisodeList) {
    self.list = list
    observation = Task { [weak self] in
      guard let self else { return }
      await withDiscardingTaskGroup { group in
        group.addTask { await self.observeQueue() }
        group.addTask { await self.observeOnDeck() }
        group.addTask { await self.observePlayback() }
        group.addTask { await self.observeCurrentID() }
        group.addTask { await self.observePool() }
        group.addTask { await self.observeLimit() }
        group.addTask { await self.observeTimeFormat() }
      }
    }
  }

  private func observeQueue() async {
    for await _ in sharedState.$queuedPodcastEpisodes.stream() {
      guard !Task.isCancelled else { return }
      render()
    }
  }

  private func observeOnDeck() async {
    for await _ in sharedState.$onDeck.stream() {
      guard !Task.isCancelled else { return }
      render()
    }
  }

  private func observePlayback() async {
    for await _ in sharedState.$playbackStatus.stream() {
      guard !Task.isCancelled else { return }
      render()
    }
  }

  private func observeCurrentID() async {
    for await id in sharedState.$currentEpisodeID.stream() {
      guard !Task.isCancelled else { return }
      observeCurrent(id)
    }
  }

  private func observePool() async {
    for await ranking in sharedState.$recommendedEpisodePool.stream() {
      guard !Task.isCancelled else { return }
      observeRecommendations(ranking)
    }
  }

  private func observeLimit() async {
    for await _ in userSettings.$maxRecommendedEpisodesInUpNext.stream() {
      guard !Task.isCancelled else { return }
      render()
    }
  }

  private func observeTimeFormat() async {
    for await _ in userSettings.$showTimeRemainingInEpisodeLists.stream() {
      guard !Task.isCancelled else { return }
      render()
    }
  }

  private func observeCurrent(_ id: Episode.ID?) {
    currentObservation?.cancel()
    current = nil
    render()
    guard let id else { return }
    currentObservation = Task { [weak self] in
      guard let self else { return }
      do {
        for try await episodes in observatory.listablePodcastEpisodes(
          filter: Episode.Columns.id == id
        ) {
          guard !Task.isCancelled, sharedState.currentEpisodeID == id else { return }
          if let first = episodes.first {
            current = CarPlayEpisodeRow(first)
          } else {
            current = nil
          }
          render()
        }
      } catch {
        Self.log.caughtError("CarPlay current episode observation failed: episode=\(id)", error)
      }
    }
  }

  private func observeRecommendations(_ ranking: [Episode.ID]) {
    recommendationsObservation?.cancel()
    recommendations = [:]
    render()
    guard !ranking.isEmpty else { return }
    recommendationsObservation = Task { [weak self] in
      guard let self else { return }
      do {
        for try await episodes in observatory.listablePodcastEpisodes(
          filter: Set(ranking).contains(Episode.Columns.id) && Episode.candidate
        ) {
          guard !Task.isCancelled, sharedState.recommendedEpisodePool == ranking else { return }
          recommendations = Dictionary(
            uniqueKeysWithValues: episodes.map { ($0.id, CarPlayEpisodeRow($0)) }
          )
          render()
        }
      } catch {
        Self.log.caughtError(
          "CarPlay recommendation observation failed: count=\(ranking.count)",
          error
        )
      }
    }
  }

  private func render() {
    guard let list else { return }
    var sections: [CarPlayEpisodeList.Section] = []
    let currentID = sharedState.currentEpisodeID
    if let onDeck = sharedState.onDeck, onDeck.id == currentID {
      sections.append(.init(title: "Current episode", episodes: [CarPlayEpisodeRow(onDeck)]))
    } else if let current, current.id == currentID {
      sections.append(.init(title: "Current episode", episodes: [current]))
    }
    let queue = sharedState.queuedPodcastEpisodes.filter { $0.id != currentID }
      .map(CarPlayEpisodeRow.init)
    if !queue.isEmpty { sections.append(.init(title: "Up Next", episodes: queue)) }
    let recommended = sharedState.recommendedEpisodePool
      .filter { $0 != currentID && !sharedState.queuedEpisodeIDs.contains($0) }
      .compactMap { recommendations[$0] }
      .prefix(max(0, userSettings.maxRecommendedEpisodesInUpNext))
    if !recommended.isEmpty {
      sections.append(.init(title: "Recommended", episodes: Array(recommended)))
    }
    list.update(sections, restricted: restricted)
  }

  func stop() {
    observation?.cancel()
    currentObservation?.cancel()
    recommendationsObservation?.cancel()
    observation = nil
    currentObservation = nil
    recommendationsObservation = nil
    list?.stop()
    list = nil
  }
}
