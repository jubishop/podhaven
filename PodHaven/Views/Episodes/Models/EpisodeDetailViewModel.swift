// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging

@Observable @MainActor class EpisodeDetailViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.cacheState) private var cacheState
  @ObservationIgnored @DynamicInjected(\.cacheManager) private var cacheManager
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.playState) private var playState
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.EpisodesView.detail)

  // MARK: - State Management

  let episode: any EpisodeDisplayable
  private var podcastEpisode: PodcastEpisode?
  internal var maxQueuePosition: Int? = nil

  // MARK: - Initialization

  init(episode: any EpisodeDisplayable) {
    self.episode = episode
  }

  func execute() async {
    await withTaskGroup { group in
      // Observe max queue position
      group.addTask { @MainActor @Sendable in
        do {
          for try await maxPosition in self.observatory.maxQueuePosition() {
            try Task.checkCancellation()
            self.maxQueuePosition = maxPosition
          }
        } catch {
          Self.log.error(error)
          guard ErrorKit.isRemarkable(error) else { return }
          self.alert(ErrorKit.coreMessage(for: error))
        }
      }

      // Observe this episode record updates
      group.addTask { @MainActor @Sendable in
        do {
          for try await podcastEpisode in self.observatory.podcastEpisode(self.episode.mediaGUID) {
            try Task.checkCancellation()
            Self.log.debug(
              "Updating observed podcast: \(String(describing: podcastEpisode?.toString))"
            )
            self.podcastEpisode = podcastEpisode
          }
        } catch {
          Self.log.error(error)
          guard ErrorKit.isRemarkable(error) else { return }
          self.alert(ErrorKit.coreMessage(for: error))
        }
      }
    }
  }

  // MARK: - Derived State

  var onDeck: Bool {
    guard let podcastEpisode = podcastEpisode,
      let onDeck = playState.onDeck
    else { return false }
    return onDeck == podcastEpisode
  }

  var atTopOfQueue: Bool {
    guard let podcastEpisode = podcastEpisode else { return false }
    return podcastEpisode.episode.queueOrder == 0
  }

  var atBottomOfQueue: Bool {
    guard let podcastEpisode = podcastEpisode,
      let queueOrder = podcastEpisode.episode.queueOrder
    else { return false }
    return queueOrder == maxQueuePosition
  }

  var isCaching: Bool {
    guard let podcastEpisode = podcastEpisode else { return false }
    return cacheState.isDownloading(podcastEpisode.id)
  }

  // MARK: - Public Methods

  func playNow() {
    Task { [weak self] in
      guard let self else { return }
      let podcastEpisode: PodcastEpisode
      do {
        podcastEpisode = try await getOrCreatePodcastEpisode()
      } catch {
        Self.log.error(error)
        alert(ErrorKit.coreMessage(for: error))
        return
      }

      do {
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        Self.log.error(error)
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func addToTopOfQueue() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await queue.unshift(podcastEpisode.episode.id)
      } catch {
        Self.log.error(error)
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func appendToQueue() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await queue.append(podcastEpisode.episode.id)
      } catch {
        Self.log.error(error)
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func cacheEpisode() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await cacheManager.downloadAndCache(podcastEpisode)
      } catch {
        Self.log.error(error)
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func showPodcast() {
    Task { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      navigation.showPodcast(podcastEpisode.podcast)
    }
  }

  // MARK: - Private Helpers

  private func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = self.podcastEpisode { return podcastEpisode }

    let podcastEpisode = try await DisplayableEpisode.toPodcastEpisode(episode)
    self.podcastEpisode = podcastEpisode
    return podcastEpisode
  }
}
