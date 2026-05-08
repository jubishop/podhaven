// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

struct PodcastSeries: Decodable, Equatable, FetchableRecord, Hashable, Identifiable, Stringable {
  var id: Podcast.ID { podcast.id }

  let podcast: Podcast
  let episodes: IdentifiedArrayOf<EpisodeWithTags>
  let tags: IdentifiedArrayOf<Tag>?

  init(
    podcast: Podcast,
    episodes: [Episode] = [],
    tags: IdentifiedArrayOf<Tag>? = nil
  ) {
    self.init(
      podcast: podcast,
      episodes: IdentifiedArrayOf(
        uniqueElements: episodes.map { EpisodeWithTags(episode: $0, tagIDs: nil) }
      ),
      tags: tags
    )
  }

  init(
    podcast: Podcast,
    episodes: IdentifiedArrayOf<Episode>,
    tags: IdentifiedArrayOf<Tag>? = nil
  ) {
    self.init(
      podcast: podcast,
      episodes: IdentifiedArrayOf(
        uniqueElements: episodes.map { EpisodeWithTags(episode: $0, tagIDs: nil) }
      ),
      tags: tags
    )
  }

  init(
    podcast: Podcast,
    episodes: IdentifiedArrayOf<EpisodeWithTags>,
    tags: IdentifiedArrayOf<Tag>? = nil
  ) {
    self.podcast = podcast
    self.episodes = episodes
    self.tags = tags
  }

  // MARK: - Decodable

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    podcast = try container.decode(Podcast.self, forKey: .podcast)
    // Decoder path is only reached via GRDB's `asRequest(of:)`, which doesn't
    // surface the episodeTag join; callers that need tag data fold it in via
    // `withFoldedEpisodeTagIDs(db:)` after decoding.
    episodes = IdentifiedArrayOf(
      uniqueElements: try container.decode([Episode].self, forKey: .episodes)
        .map { EpisodeWithTags(episode: $0, tagIDs: nil) }
    )
    if let decodedTags = try container.decodeIfPresent([Tag].self, forKey: .tags) {
      tags = IdentifiedArrayOf(uniqueElements: decodedTags)
    } else {
      tags = nil
    }
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
    let foldedEpisodes = IdentifiedArrayOf<EpisodeWithTags>(
      uniqueElements: episodes.map {
        EpisodeWithTags(
          episode: $0.episode,
          tagIDs: tagIDsByEpisodeId[$0.id] ?? []
        )
      }
    )
    return PodcastSeries(
      podcast: podcast,
      episodes: foldedEpisodes,
      tags: tags
    )
  }
}
