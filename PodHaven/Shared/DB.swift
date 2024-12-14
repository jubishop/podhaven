// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import IdentifiedCollections

typealias PodcastArray = IdentifiedArray<URL, Podcast>

@Observable @MainActor final class DB: Sendable {
  static let shared = DB()

  var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)

  private var observing = false

  func observePodcasts() async {
    guard !observing else { return }

    let observer =
      ValueObservation.tracking { db in
        try Podcast.all().fetchIdentifiedArray(db, id: \Podcast.feedURL)
      }
      .removeDuplicates()

    do {
      observing = true
      for try await podcasts in observer.values(in: PodcastRepository.shared.db)
      {
        guard self.podcasts != podcasts else { return }
        self.podcasts = podcasts
      }
    } catch {
      observing = false
      Alert.shared("Error thrown while observing podcast database")
    }
  }
}
