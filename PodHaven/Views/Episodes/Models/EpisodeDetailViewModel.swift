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

  // MARK: - Data

  var episode: any EpisodeDisplayable
  private var maxQueuePosition: Int? = nil
  private var podcastEpisode: PodcastEpisode? {
    didSet {
      guard let podcastEpisode = podcastEpisode
      else { Assert.fatal("Setting podcastEpisode to nil is not allowed") }

      Self.log.debug("podcastEpisode: \(podcastEpisode.toString)")

      self.episode = podcastEpisode
    }
  }

  // MARK: - Initialization

  init(episode: any EpisodeDisplayable) {
    self.episode = episode
  }

  func execute() async {
    do {
      try await performExecute()
    } catch {
      Self.log.error(error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.coreMessage(for: error))
    }
  }

  func performExecute() async throws {
    let podcastEpisode = try await repo.podcastEpisode(episode.mediaGUID)

    if let podcastEpisode {
      Self.log.debug("Podcast episode: \(podcastEpisode.toString) exists in db")

      self.podcastEpisode = podcastEpisode
      startObservation()
    } else {
      Self.log.debug("Podcast episode: \(episode.toString) does not exist in db")
    }

    do {
      for try await maxPosition in self.observatory.maxQueuePosition() {
        try Task.checkCancellation()
        Self.log.debug("Updating observed max queue position: \(String(describing: maxPosition))")
        self.maxQueuePosition = maxPosition
      }
    } catch {
      Self.log.error(error)
      guard ErrorKit.isRemarkable(error) else { return }
      self.alert(ErrorKit.coreMessage(for: error))
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

  // MARK: - Public Methods

  func playNow() {
    Task { [weak self] in
      guard let self else { return }
      let podcastEpisode: PodcastEpisode
      do {
        podcastEpisode = try await getOrCreatePodcastEpisode()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
        return
      }

      do {
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
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
        guard ErrorKit.isRemarkable(error) else { return }
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
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func cacheEpisode() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await cacheManager.downloadToCache(for: podcastEpisode.id)
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
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

  // MARK: - Observation Management

  @ObservationIgnored private var observationTask: Task<Void, Never>?

  private func startObservation() {
    Assert.precondition(
      observationTask == nil,
      "Already observing"
    )

    observationTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await observePodcastEpisode()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  private func observePodcastEpisode() async throws {
    guard let podcastEpisode = self.podcastEpisode
    else { Assert.fatal("Observing a non-saved podcastEpisode") }

    Self.log.debug("Starting observation for episode: \(podcastEpisode.toString)")

    do {
      for try await updatedEpisode in self.observatory.podcastEpisode(podcastEpisode.id) {
        try Task.checkCancellation()
        Self.log.debug("Updating observed episode: \(String(describing: updatedEpisode?.toString))")
        guard let updatedEpisode, updatedEpisode != self.podcastEpisode else { continue }
        self.podcastEpisode = updatedEpisode
      }
    } catch {
      Self.log.error(error)
      guard ErrorKit.isRemarkable(error) else { return }
      self.alert(ErrorKit.coreMessage(for: error))
    }
  }

  func disappear() {
    Self.log.debug("disappear: executing")
    observationTask?.cancel()
  }

  // MARK: - Private Helpers

  private func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = self.podcastEpisode { return podcastEpisode }

    let podcastEpisode = try await DisplayableEpisode.getOrCreatePodcastEpisode(episode)
    self.podcastEpisode = podcastEpisode
    startObservation()
    return podcastEpisode
  }
}
