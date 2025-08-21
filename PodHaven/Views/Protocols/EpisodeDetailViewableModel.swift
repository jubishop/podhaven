// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging

@MainActor protocol EpisodeDetailViewableModel {
  var episodeTitle: String { get }
  var episodePubDate: Date { get }
  var episodeDuration: CMTime { get }
  var episodeCachedFilename: String? { get }
  var episodeImage: URL { get }
  var episodeDescription: String? { get }
  var podcastTitle: String { get }

  var maxQueuePosition: Int? { get set }
  var onDeck: Bool { get }
  var atTopOfQueue: Bool { get }
  var atBottomOfQueue: Bool { get }

  func execute() async
  func playNow()
  func addToTopOfQueue()
  func appendToQueue()

  func getPodcastEpisode() -> PodcastEpisode?
  func getOrCreatePodcastEpisode() async throws -> PodcastEpisode
}

extension EpisodeDetailViewableModel {
  var onDeck: Bool {
    guard let podcastEpisode = getPodcastEpisode(),
      let onDeck = Container.shared.playState().onDeck
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

  func playNow() {
    Task {
      let podcastEpisode: PodcastEpisode
      do {
        podcastEpisode = try await getOrCreatePodcastEpisode()
      } catch {
        Log.as(LogSubsystem.EpisodesView.detail).error(error)
        Container.shared.alert()(ErrorKit.message(for: error))
        return
      }

      do {
        try await Container.shared.playManager().load(podcastEpisode)
        await Container.shared.playManager().play()
      } catch {
        Log.as(LogSubsystem.EpisodesView.detail).error(error)
        Container.shared.alert()(ErrorKit.message(for: error))
      }
    }
  }

  func addToTopOfQueue() {
    Task {
      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await Container.shared.queue().unshift(podcastEpisode.episode.id)
      } catch {
        Log.as(LogSubsystem.EpisodesView.detail).error(error)
        Container.shared.alert()(ErrorKit.message(for: error))
      }
    }
  }

  func appendToQueue() {
    Task {
      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await Container.shared.queue().append(podcastEpisode.episode.id)
      } catch {
        Log.as(LogSubsystem.EpisodesView.detail).error(error)
        Container.shared.alert()(ErrorKit.message(for: error))
      }
    }
  }
}
