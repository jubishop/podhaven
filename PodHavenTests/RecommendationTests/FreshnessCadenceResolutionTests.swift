// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

// Covers RecommendationRepo's cadence resolution + per-podcast recompute as seen
// through the engine's rebuild reader (`allScoringContextInputs`), the
// counterpart to the GRDB observation exercised in
// ObservatoryScoringContextInputsTests.
@Suite("of FreshnessCadence resolution tests", .container)
class FreshnessCadenceResolutionTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo

  private let now = Date()

  // MARK: - Helpers

  private func insertPodcast() async throws -> Podcast {
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: []
      )
    )
    .podcast
  }

  // Upserts episodes onto an existing podcast (matched by feedURL) at the given
  // whole-day offsets back from `now`, controlling the median inter-episode gap.
  @discardableResult
  private func addEpisodes(
    to podcast: Podcast,
    atDayOffsets dayOffsets: [Double]
  ) async throws -> [Episode] {
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: podcast.feedURL,
      title: podcast.title,
      image: podcast.image,
      description: podcast.description
    )
    let podcastEpisodes = try await repo.upsertPodcastEpisodes(
      try dayOffsets.map { offset in
        UnsavedPodcastEpisode(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisode: try Create.unsavedEpisode(
            pubDate: now.addingTimeInterval(-offset * 86400)
          )
        )
      }
    )
    return podcastEpisodes.map(\.episode)
  }

  private func resolvedCadence(for podcastID: Podcast.ID) async throws -> FreshnessCadence? {
    try await recommendationRepo.allScoringContextInputs().freshnessCadences[podcastID]
  }

  // MARK: - Tests

  @Test("resolves the inferred cadence from episode spacing")
  func resolvesInferredFromSpacing() async throws {
    let podcast = try await insertPodcast()
    try await addEpisodes(to: podcast, atDayOffsets: [0, 7, 14, 21, 28])
    #expect(try await resolvedCadence(for: podcast.id) == .weekly)
  }

  @Test("manual override wins over the inferred cadence")
  func manualOverrideWins() async throws {
    let podcast = try await insertPodcast()
    // Daily-spaced episodes would otherwise infer to .daily.
    try await addEpisodes(to: podcast, atDayOffsets: [0, 1, 2, 3, 4])
    var settings = PodcastSettings.defaults
    settings.freshnessCadence = .evergreen
    _ = try await repo.updatePodcastSettings(podcast.id, settings)

    #expect(try await resolvedCadence(for: podcast.id) == .evergreen)
  }

  @Test("a podcast with no episodes and no manual override is absent from the map")
  func absentWhenEmpty() async throws {
    let podcast = try await insertPodcast()
    #expect(try await resolvedCadence(for: podcast.id) == nil)
  }

  @Test("the cached inference recomputes when new episodes shift the median")
  func recomputesOnMedianShift() async throws {
    let podcast = try await insertPodcast()
    // Three weekly-spaced episodes well in the past.
    try await addEpisodes(to: podcast, atDayOffsets: [100, 107, 114])
    #expect(try await resolvedCadence(for: podcast.id) == .weekly)

    // A burst of recent daily episodes drags the median gap down to ~1 day.
    try await addEpisodes(to: podcast, atDayOffsets: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
    #expect(try await resolvedCadence(for: podcast.id) == .daily)
  }

  @Test("clearing a manual override falls back to the still-cached inference")
  func clearingManualFallsBackToInferred() async throws {
    let podcast = try await insertPodcast()
    try await addEpisodes(to: podcast, atDayOffsets: [0, 7, 14, 21, 28])

    var settings = PodcastSettings.defaults
    settings.freshnessCadence = .daily
    _ = try await repo.updatePodcastSettings(podcast.id, settings)
    #expect(try await resolvedCadence(for: podcast.id) == .daily)

    settings.freshnessCadence = nil
    _ = try await repo.updatePodcastSettings(podcast.id, settings)
    #expect(try await resolvedCadence(for: podcast.id) == .weekly)
  }

  @Test("deleting a podcast drops it from the resolved map")
  func deletingPodcastDropsCadence() async throws {
    let podcast = try await insertPodcast()
    try await addEpisodes(to: podcast, atDayOffsets: [0, 7, 14, 21, 28])
    #expect(try await resolvedCadence(for: podcast.id) == .weekly)

    _ = try await repo.deletePodcast(podcast.id)
    #expect(try await resolvedCadence(for: podcast.id) == nil)
  }
}
