// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging

@MainActor protocol EpisodeDetailViewableModel: AnyObject {
  var episodeTitle: String { get }
  var episodePubDate: Date { get }
  var episodeDuration: CMTime { get }
  var episodeCached: Bool { get }
  var episodeImage: URL { get }
  var episodeDescription: String? { get }
  var podcastTitle: String { get }

  var maxQueuePosition: Int? { get set }
  var onDeck: Bool { get }
  var atTopOfQueue: Bool { get }
  var atBottomOfQueue: Bool { get }
  var isCaching: Bool { get }

  func execute() async
  func playNow()
  func addToTopOfQueue()
  func appendToQueue()
  func cacheEpisode()
  func showPodcast()

  func getPodcastEpisode() -> PodcastEpisode?
  func getOrCreatePodcastEpisode() async throws -> PodcastEpisode
}

extension EpisodeDetailViewableModel {
  private var alert: Alert { Container.shared.alert() }
  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var cacheState: CacheState { Container.shared.cacheState() }
  private var navigation: Navigation { Container.shared.navigation() }
  private var playManager: PlayManager { Container.shared.playManager() }
  private var playState: PlayState { Container.shared.playState() }
  private var queue: any Queueing { Container.shared.queue() }
  
  private var log: Logger { Log.as(LogSubsystem.EpisodesView.detail) }
  
  var onDeck: Bool {
    guard let podcastEpisode = getPodcastEpisode(),
      let onDeck = playState.onDeck
    else { return false }
    return onDeck == podcastEpisode
  }

  var atTopOfQueue: Bool {
    guard let podcastEpisode = getPodcastEpisode() else { return false }
    return podcastEpisode.episode.queueOrder == 0
  }

  var atBottomOfQueue: Bool {
    guard let podcastEpisode = getPodcastEpisode(),
      let queueOrder = podcastEpisode.episode.queueOrder
    else { return false }
    return queueOrder == maxQueuePosition
  }
  
  var isCaching: Bool {
    guard let podcastEpisode = getPodcastEpisode() else { return false }
    return cacheState.isDownloading(podcastEpisode.id)
  }

  func playNow() {
    Task { [weak self] in
      guard let self else { return }
      let podcastEpisode: PodcastEpisode
      do {
        podcastEpisode = try await getOrCreatePodcastEpisode()
      } catch {
        log.error(error)
        alert(ErrorKit.message(for: error))
        return
      }

      do {
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        log.error(error)
        alert(ErrorKit.message(for: error))
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
        log.error(error)
        alert(ErrorKit.message(for: error))
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
        log.error(error)
        alert(ErrorKit.message(for: error))
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
        log.error(error)
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
}
