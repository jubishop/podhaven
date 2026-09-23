// Copyright Justin Bishop, 2026

import Intents

@testable import PodHaven

enum SiriTestIntent {
  static func named(
    _ name: String?,
    type: INMediaItemType = .unknown,
    shuffled: Bool? = nil,
    album: String? = nil
  )
    -> INPlayMediaIntent
  {
    INPlayMediaIntent(
      mediaItems: nil,
      mediaContainer: nil,
      playShuffled: shuffled,
      playbackRepeatMode: .unknown,
      resumePlayback: nil,
      playbackQueueLocation: .unknown,
      playbackSpeed: nil,
      mediaSearch: INMediaSearch(
        mediaType: type,
        sortOrder: .unknown,
        mediaName: name,
        artistName: nil,
        albumName: album,
        genreNames: nil,
        moodNames: nil,
        releaseDate: nil,
        reference: .unknown,
        mediaIdentifier: nil
      )
    )
  }

  static func resolved(_ entry: SiriCatalog.Entry) throws -> INPlayMediaIntent {
    INPlayMediaIntent(
      mediaItems: [try entry.mediaItem()],
      mediaContainer: nil,
      playShuffled: nil,
      playbackRepeatMode: .unknown,
      resumePlayback: nil,
      playbackQueueLocation: .unknown,
      playbackSpeed: nil,
      mediaSearch: nil
    )
  }
}
