#if DEBUG
// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

// Seeds the RecommendationEngine for previews that need a live scoring context
// (e.g. the search discovery banner). Registers a scripted embeddable, inserts
// a few rated + embedded "signal" episodes, and starts the engine so it builds
// a non-nil context. Discovery candidates default to the loved-signal
// direction, so their scores land above the floor and surface as picks.
enum PreviewRecommendations {
  static func seedScoringContext() async throws {
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: signalEmbeddable) }
      .scope(.cached)

    // Focused mode skips PCA whitening, which NaNs on the dim-3 signal vectors.
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let signals = try await insertSignalEpisodes()
    let embedding = Container.shared.contextualEmbedding()
    await embedding.requestAndLoadAssetsIfNeeded()
    try await EmbeddingService.upsertEpisodeEmbeddings(for: signals, embedding: embedding)

    Container.shared.recommendationEngine().start()
  }

  // Three orthogonal signal vectors give the centroid a measurable direction;
  // candidate text defaults to the loved-signal direction (above the floor).
  private static var signalEmbeddable: PreviewEmbeddable {
    PreviewEmbeddable { text in
      if text.contains("Episode 0 of Signal") { return [1, 0, 0] }
      if text.contains("Episode 1 of Signal") { return [0, 1, 0] }
      if text.contains("of Signal") { return [0, 0, 1] }
      return [1, 0, 0]
    }
  }

  private static func insertSignalEpisodes() async throws -> [Episode] {
    let ratings: [EpisodeRating] = [.loved, .liked, .liked]
    let unsavedPodcast = try Create.unsavedPodcast(title: "Signal", description: "Signal")
    let entries = try ratings.enumerated()
      .map { index, rating in
        UnsavedPodcastEpisode(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisode: try Create.unsavedEpisode(
            title: "Episode \(index) of Signal",
            pubDate: Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 86_400),
            description: "Episode \(index) description",
            rating: rating,
            ratingDate: Date(timeIntervalSince1970: 1_700_000_000)
          )
        )
      }
    let podcastEpisodes = try await Container.shared.repo().upsertPodcastEpisodes(entries)
    return podcastEpisodes.map(\.episode)
  }
}
#endif
