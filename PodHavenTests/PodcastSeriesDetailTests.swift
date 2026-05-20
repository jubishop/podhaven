// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

// `Observatory.podcastSeriesDetail` is a `ValueObservation` with
// `.removeDuplicates()`, which relies entirely on `PodcastSeriesDetail`'s
// `Equatable` to drop redundant emissions. If a fetched detail does not
// compare equal to a second fetch of the same unchanged data, then
// `.removeDuplicates()` is defeated: every write to the observed region
// becomes a spurious emission, which is the PodcastDetail observation storm.
@Suite("of PodcastSeriesDetail equality stability", .container)
class PodcastSeriesDetailTests {
  @DynamicInjected(\.repo) private var repo

  @Test("two fetches of unchanged data compare equal")
  func repeatedFetchIsEqual() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(pubDate: Date(timeIntervalSince1970: 3_000)),
          try Create.unsavedEpisode(pubDate: Date(timeIntervalSince1970: 2_000)),
          try Create.unsavedEpisode(pubDate: Date(timeIntervalSince1970: 1_000)),
        ]
      )
    )

    let first = try #require(try await repo.podcastSeriesDetail(series.id))
    let second = try #require(try await repo.podcastSeriesDetail(series.id))

    #expect(first == second)
  }

  @Test("a fetched detail stays equal across an unrelated write")
  func fetchIsStableAcrossUnrelatedWrite() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(pubDate: Date(timeIntervalSince1970: 3_000)),
          try Create.unsavedEpisode(pubDate: Date(timeIntervalSince1970: 2_000)),
        ]
      )
    )

    let before = try #require(try await repo.podcastSeriesDetail(series.id))

    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )

    let after = try #require(try await repo.podcastSeriesDetail(series.id))

    #expect(before == after)
  }
}
