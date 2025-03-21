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
  // MARK: - Observers

  func observePodcastEpisode(_ mediaURL: MediaURL) -> AsyncThrowingStream<PodcastEpisode?, Error> {
    _streamFromObservation(
      ValueObservation
        .tracking(
          Episode
            .filter(Schema.mediaColumn == mediaURL)
            .including(required: Episode.podcast)
            .asRequest(of: PodcastEpisode.self)
            .fetchOne
        )
        .removeDuplicates()
    )
  }

  func observePodcastSeries(_ feedURL: FeedURL) -> AsyncThrowingStream<PodcastSeries?, Error> {
    _streamFromObservation(
      ValueObservation
        .tracking(
          Podcast
            .filter(Schema.feedURLColumn == feedURL)
            .including(all: Podcast.episodes)
            .asRequest(of: PodcastSeries.self)
            .fetchOne
        )
        .removeDuplicates()
    )
  }

  // MARK: - Private Helpers

  private func _streamFromObservation<T>(_ observation: ValueObservation<T>)
    -> AsyncThrowingStream<T.Value, Error>
  {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await value in observation.values(in: Container.shared.repo().db) {
            continuation.yield(value)
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
