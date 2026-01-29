// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging
import Nuke
import SwiftUI
import Tagged
import UIKit

@Observable @MainActor class EpisodeDetailViewModel: Shareable {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.cacheManager) private var cacheManager
  @ObservationIgnored @DynamicInjected(\.imagePipeline) private var imagePipeline
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState

  private static let log = Log.as(LogSubsystem.EpisodesView.detail)

  // MARK: - Data

  var episode: DisplayedEpisode
  private var _podcastEpisode: PodcastEpisode?
  private var podcastEpisode: PodcastEpisode? {
    get { _podcastEpisode }
    set {
      guard let newValue
      else { Assert.fatal("Setting podcastEpisode to nil is not allowed") }

      Self.log.debug("Setting podcastEpisode to: \(newValue.toString)")

      _podcastEpisode = newValue
      episode = DisplayedEpisode(newValue)
    }
  }

  // MARK: - Derived State

  var onDeck: Bool {
    guard let podcastEpisode = podcastEpisode else { return false }
    return sharedState.onDeck?.id == podcastEpisode.id
  }

  var atTopOfQueue: Bool {
    episode.queueOrder == 0
  }

  var atBottomOfQueue: Bool {
    guard let queueOrder = episode.queueOrder else { return false }
    return queueOrder == sharedState.maxQueuePosition
  }

  var isPlaying: Bool {
    guard let podcastEpisode = podcastEpisode else { return false }
    return sharedState.isEpisodePlaying(podcastEpisode)
  }

  var canClearCache: Bool {
    episode.cacheStatus != .uncached && CacheManager.canClearCache(episode)
  }

  // MARK: - Shareable

  var shareTitle: String { episode.title }
  var shareArtwork: UIImage?
  var shareFallbackIcon: AppIcon { .showEpisode }
  var shareURL: URL? { ShareURL.episode(feedURL: episode.feedURL, guid: episode.mediaGUID.guid) }

  // MARK: - Initialization

  init(episode: DisplayedEpisode) {
    self.episode = episode

    Task { [weak self] in
      guard let self else { return }
      shareArtwork = try await imagePipeline.image(for: episode.image)
    }
  }

  func appear() {
    Task { [weak self] in
      guard let self else { return }

      do {
        try await performAppear()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func performAppear() async throws {
    let podcastEpisode = try await repo.podcastEpisode(episode.mediaGUID)

    if let podcastEpisode {
      Self.log.debug("Podcast episode: \(podcastEpisode.toString) exists in db")

      self.podcastEpisode = podcastEpisode
      startObservation()
    } else {
      Self.log.debug("Podcast episode: \(episode.toString) does not exist in db")

      _podcastEpisode = nil
      episode = DisplayedEpisode(try episode.toOriginalUnsavedPodcastEpisode())
    }
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

  func pause() {
    guard isPlaying else { return }

    Task { [weak self] in
      guard let self else { return }
      await playManager.pause()
    }
  }

  func addToTopOfQueue() {
    guard !atTopOfQueue else { return }

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
    guard !atBottomOfQueue else { return }

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

  func removeFromQueue() {
    guard episode.queued else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await queue.dequeue(podcastEpisode.episode.id)
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

  func uncacheEpisode() {
    guard canClearCache else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await repo.updateSaveInCache(podcastEpisode.id, saveInCache: false)
        try await cacheManager.clearCache(for: podcastEpisode.id)
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func saveEpisodeInCache() {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await repo.updateSaveInCache(podcastEpisode.id, saveInCache: true)
        try await cacheManager.downloadToCache(for: podcastEpisode.id)
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func markFinished() {
    guard !episode.finished else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await repo.markFinished(podcastEpisode.id)
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
    if let observationTask, !observationTask.isCancelled {
      Self.log.debug("Observation already active; not starting observation")
      return
    }

    observationTask = Task { [weak self] in
      guard let self else { return }

      do {
        try await observePodcastEpisode()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
      clearObservationTask()
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

        guard let updatedEpisode
        else {
          Self.log.debug("Episode was deleted")
          _podcastEpisode = nil
          episode = DisplayedEpisode(try podcastEpisode.toOriginalUnsavedPodcastEpisode())
          return
        }

        guard updatedEpisode != self.podcastEpisode
        else {
          Self.log.debug("New episode is the same as the current one, skipping update")
          continue
        }

        self.podcastEpisode = updatedEpisode
      }
    } catch {
      Self.log.error(error)
      guard ErrorKit.isRemarkable(error) else { return }
      self.alert(ErrorKit.coreMessage(for: error))
    }
  }

  // MARK: - Disappear

  func disappear() {
    Self.log.debug("disappear: executing")
    clearObservationTask()
  }

  private func clearObservationTask() {
    observationTask?.cancel()
    observationTask = nil
  }

  // MARK: - Private Helpers

  private func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = self.podcastEpisode { return podcastEpisode }

    let podcastEpisode = try await DisplayedEpisode.getOrCreatePodcastEpisode(episode)
    self.podcastEpisode = podcastEpisode
    startObservation()
    return podcastEpisode
  }
}
