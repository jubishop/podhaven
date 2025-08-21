// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor class UpNextViewModel: Sortable {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.cacheManager) private var cacheManager
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.UpNextView.main)

  // MARK: - State Management

  var editMode: EditMode = .inactive
  var isEditing: Bool { editMode == .active }

  var episodeList = SelectableListUseCase<PodcastEpisode, Episode.ID>(idKeyPath: \.id)
  var podcastEpisodes: IdentifiedArray<Episode.ID, PodcastEpisode> { episodeList.allEntries }

  enum SortMethod: String, CaseIterable {
    case oldestFirst = "Oldest First"
    case mostRecentFirst = "Most Recent First"
    case mostCompleted = "Most Completed"
  }

  private static func sortMethod(for sortMethod: SortMethod) -> (
    PodcastEpisode, PodcastEpisode
  ) -> Bool {
    switch sortMethod {
    case .oldestFirst:
      return { lhs, rhs in lhs.episode.pubDate < rhs.episode.pubDate }
    case .mostRecentFirst:
      return { lhs, rhs in lhs.episode.pubDate > rhs.episode.pubDate }
    case .mostCompleted:
      return { lhs, rhs in
        // Primary sort: most completed first (highest currentTime)
        if lhs.episode.currentTime.seconds != rhs.episode.currentTime.seconds {
          return lhs.episode.currentTime.seconds > rhs.episode.currentTime.seconds
        }
        // Secondary sort: oldest publication date first
        return lhs.episode.pubDate < rhs.episode.pubDate
      }
    }
  }
  
  // MARK: - Sortable Protocol
  
  var currentSortMethod: SortMethod? = nil

  // MARK: - Initialization

  func execute() async {
    do {
      for try await podcastEpisodes in observatory.queuedPodcastEpisodes() {
        self.episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
      }
    } catch {
      alert("Couldn't execute UpNextViewModel")
    }
  }

  // MARK: - Derived State

  var totalQueueDuration: CMTime {
    podcastEpisodes.reduce(CMTime.zero) { total, podcastEpisode in
      total + podcastEpisode.episode.duration
    }
  }

  // MARK: - Public Functions

  func moveItem(from: IndexSet, to: Int) {
    guard from.count == 1, let from = from.first
    else { Assert.fatal("Somehow dragged none or several?") }

    Task { [weak self] in
      guard let self else { return }
      do {
        try await queue.insert(podcastEpisodes[from].episode.id, at: to)
      } catch {
        Self.log.error(error)
      }
    }
  }

  func deleteSelected() {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await queue.dequeue(episodeList.selectedEntryIDs)
      } catch {
        Self.log.error(error)
      }
    }
  }

  func playItem(_ podcastEpisode: PodcastEpisode) {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        Self.log.error(error)
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func deleteItem(_ podcastEpisode: PodcastEpisode) {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await queue.dequeue(podcastEpisode.episode.id)
      } catch {
        Self.log.error(error)
      }
    }
  }

  func cacheItem(_ podcastEpisode: PodcastEpisode) {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await cacheManager.downloadAndCache(podcastEpisode)
      } catch {
        Self.log.error(error)
      }
    }
  }

  func sort(by method: SortMethod) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let sortedEpisodes = podcastEpisodes.sorted(by: Self.sortMethod(for: method))
        try await queue.updateQueueOrders(sortedEpisodes.map(\.episode.id))
      } catch {
        Self.log.error(error)
      }
    }
  }

  func refreshQueue() {
    Self.log.debug("refreshQueue: downloading and caching uncached episodes")

    let uncachedEpisodes = podcastEpisodes.filter { podcastEpisode in
      podcastEpisode.episode.cachedFilename == nil
    }

    guard !uncachedEpisodes.isEmpty else { return }

    Self.log.debug(
      """
      Uncached episodes:
        \(uncachedEpisodes.map(\.toString).joined(separator: "\n  "))
      """
    )

    for podcastEpisode in uncachedEpisodes.reversed() {
      Task { [weak self] in
        guard let self else { return }
        do {
          try await cacheManager.downloadAndCache(podcastEpisode)
        } catch {
          Self.log.error(error)
        }
      }
    }
  }
}
