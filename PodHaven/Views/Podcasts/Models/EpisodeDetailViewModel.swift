// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB

@Observable @MainActor final class EpisodeDetailViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playState) private var playState
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  private var playManager: PlayManager { get async { await Container.shared.playManager() } }

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
        else {
          throw ObservatoryError.recordNotFound(type: PodcastEpisode.self, id: episode.id.rawValue)
        }

        if self.podcastEpisode == podcastEpisode { continue }
        self.podcastEpisode = podcastEpisode
      }
    } catch {
      alert("Couldn't execute EpisodeDetailViewModel")
    }
  }

  var onDeck: Bool {
    guard let onDeck = playState.onDeck else { return false }
    return onDeck == podcastEpisode
  }

  func playNow() {
    Task { [weak self] in
      guard let self else { return }
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
  }

  func addToTopOfQueue() {
    Task { [weak self] in
      guard let self else { return }
      try await queue.unshift(episode.id)
    }
  }

  func appendToQueue() {
    Task { [weak self] in
      guard let self else { return }
      try await queue.append(episode.id)
    }
  }
}
