// Copyright Justin Bishop, 2025

import Foundation

@dynamicMemberLookup
struct DisplayableEpisode: Hashable {
  let episode: any EpisodeDisplayable

  subscript<T>(dynamicMember keyPath: KeyPath<any EpisodeDisplayable, T>) -> T {
    episode[keyPath: keyPath]
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(episode.mediaGUID)
  }

  static func == (lhs: DisplayableEpisode, rhs: DisplayableEpisode) -> Bool {
    lhs.mediaGUID == rhs.mediaGUID
  }
}
