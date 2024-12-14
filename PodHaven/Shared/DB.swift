// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import IdentifiedCollections
import Semaphore

typealias PodcastArray = IdentifiedArray<URL, Podcast>

@Observable @MainActor final class DB: Sendable {
  #if DEBUG
    static func empty() -> DB { DB(.empty()) }
  #endif

  static let shared = DB(.shared)

  var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)

  private let semaphore = AsyncSemaphore(value: 1)
  private let appDB: AppDB

  init(_ appDB: AppDB) {
    self.appDB = appDB
  }

  func observePodcasts() async {
    await semaphore.wait()
    defer { semaphore.signal() }

    let observer =
      ValueObservation.tracking { db in
        try Podcast.all().fetchIdentifiedArray(db, id: \Podcast.feedURL)
      }
      .removeDuplicates()

    do {
      for try await podcasts in observer.values(in: appDB.db) {
        self.podcasts = podcasts
      }
    } catch {
      Alert.shared("Error thrown while observing podcast database")
    }
  }
}
