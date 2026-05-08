// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

struct PodcastSeries: Decodable, Equatable, FetchableRecord, Hashable, Identifiable, Stringable {
  var id: Podcast.ID { podcast.id }

  let podcast: Podcast
  let episodes: IdentifiedArrayOf<Episode>
  let tags: IdentifiedArrayOf<Tag>?
  // Per-episode tag IDs for episodes in this series. Populated by the
  // Observatory observation (which folds in an episodeTag query so the
  // observation region tracks tag changes); `nil` means tag data wasn't
  // loaded with this series, so callers should treat it as "unknown" rather
  // than "no tags". An episode missing from the dictionary has no tags.
  let tagIDsByEpisodeId: [Episode.ID: Set<Tag.ID>]?

  init(
    podcast: Podcast,
    episodes: [Episode] = [],
    tags: IdentifiedArrayOf<Tag>? = nil,
    tagIDsByEpisodeId: [Episode.ID: Set<Tag.ID>]? = nil
  ) {
    self.init(
      podcast: podcast,
      episodes: IdentifiedArrayOf(uniqueElements: episodes),
      tags: tags,
      tagIDsByEpisodeId: tagIDsByEpisodeId
    )
  }

  init(
    podcast: Podcast,
    episodes: IdentifiedArrayOf<Episode>,
    tags: IdentifiedArrayOf<Tag>? = nil,
    tagIDsByEpisodeId: [Episode.ID: Set<Tag.ID>]? = nil
  ) {
    self.podcast = podcast
    self.episodes = episodes
    self.tags = tags
    self.tagIDsByEpisodeId = tagIDsByEpisodeId
  }

  // MARK: - Decodable

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    podcast = try container.decode(Podcast.self, forKey: .podcast)
    episodes = IdentifiedArrayOf(
      uniqueElements: try container.decode([Episode].self, forKey: .episodes)
    )
    if let decodedTags = try container.decodeIfPresent([Tag].self, forKey: .tags) {
      tags = IdentifiedArrayOf(uniqueElements: decodedTags)
    } else {
      tags = nil
    }
    // Decoder path is only reached via GRDB's `asRequest(of:)`, which doesn't
    // surface the episodeTag join. Callers fold the map in via the dedicated
    // initializer after the row decode.
    tagIDsByEpisodeId = nil
  }

  private enum CodingKeys: String, CodingKey {
    case podcast
    case episodes
    case tags
  }

  // MARK: - Stringable

  var toString: String { podcast.toString }
}

extension PodcastSeries {
  // Folds in per-episode tag IDs via a single follow-up query. Used by both
  // `Repo.podcastSeries(...)` readers and `Observatory.podcastSeries(...)`,
  // since GRDB's `asRequest(of: PodcastSeries.self)` decoder path can't pick
  // up the episodeTag join. Calling this inside an `_observe` closure also
  // wires the episodeTag table into the observation's tracked region so tag
  // mutations refire the stream.
  func withFoldedEpisodeTagIDs(db: Database) throws -> PodcastSeries {
    var tagIDsByEpisodeId: [Episode.ID: Set<Tag.ID>] = [:]
    let episodeIDs = episodes.map(\.id)
    if !episodeIDs.isEmpty {
      let pairs = try EpisodeTag
        .filter(episodeIDs.contains(EpisodeTag.Columns.episodeId))
        .fetchAll(db)
      for pair in pairs {
        tagIDsByEpisodeId[pair.episodeId, default: []].insert(pair.tagId)
      }
    }
    return PodcastSeries(
      podcast: podcast,
      episodes: episodes,
      tags: tags,
      tagIDsByEpisodeId: tagIDsByEpisodeId
    )
  }
}
