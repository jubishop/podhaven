// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

@Observable @MainActor final class EpisodeViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.playState) private var playState
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  private var podcastEpisode: PodcastEpisode
  var podcast: Podcast { podcastEpisode.podcast }
  var episode: Episode { podcastEpisode.episode }

  init(podcastEpisode: PodcastEpisode) {
    self.podcastEpisode = podcastEpisode
  }

  func execute() async {
    do {
      for try await podcastEpisode in observatory.podcastEpisode(episode.id) {
        guard let podcastEpisode = podcastEpisode
        else { throw Err("No return from DB for: \(episode.toString)") }
        self.podcastEpisode = podcastEpisode
      }
    } catch {
      alert.andReport(error)
    }
  }

  var onDeck: Bool { 
    guard let onDeck = playState.onDeck else { return false }
    return onDeck == podcastEpisode
  }

  func playNow() {
    Task {
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
  }

  func addToTopOfQueue() {
    Task { try await queue.unshift(episode.id) }
  }

  func appendToQueue() {
    Task { try await queue.append(episode.id) }
  }
}
