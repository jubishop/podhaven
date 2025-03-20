// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

extension Container {
  var observer: Factory<Observer> {
    Factory(self) { Observer() }.scope(.singleton)
  }
}

struct Observer {
  func observePodcastEpisode(_ mediaURL: MediaURL) -> AsyncThrowingStream<PodcastEpisode?, Error> {
    let repo = Container.shared.repo()
    let observation =
      ValueObservation
      .tracking(
        Episode
          .filter(Schema.mediaColumn == mediaURL)
          .including(required: Episode.podcast)
          .asRequest(of: PodcastEpisode.self)
          .fetchOne
      )
      .removeDuplicates()

    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await podcastEpisode in observation.values(in: repo.db) {
            continuation.yield(podcastEpisode)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
