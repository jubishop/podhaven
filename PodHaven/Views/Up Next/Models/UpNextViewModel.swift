// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor class UpNextViewModel {
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

  func sortByMostRecentFirst() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let sortedEpisodes = podcastEpisodes.sorted { $0.episode.pubDate > $1.episode.pubDate }
        try await queue.updateQueueOrders(sortedEpisodes.map(\.episode.id))
      } catch {
        Self.log.error(error)
      }
    }
  }

  func sortByMostCompleted() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let sortedEpisodes = podcastEpisodes.sorted {
          // Primary sort: most completed first (highest currentTime)
          if $0.episode.currentTime.seconds != $1.episode.currentTime.seconds {
            return $0.episode.currentTime.seconds > $1.episode.currentTime.seconds
          }
          // Secondary sort: most recent publication date first
          return $0.episode.pubDate > $1.episode.pubDate
        }
        try await queue.updateQueueOrders(sortedEpisodes.map(\.episode.id))
      } catch {
        Self.log.error(error)
      }
    }
  }
}
