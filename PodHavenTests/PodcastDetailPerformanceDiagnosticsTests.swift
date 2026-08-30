// Copyright Justin Bishop, 2026

import FactoryKit
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("Podcast detail performance diagnostics", .container)
struct PodcastDetailPerformanceDiagnosticsTests {
  @Test("state equality runs off the main actor and records bounded diagnostics")
  @MainActor
  func equalityRunsOffMainActorAndRecordsBoundedDiagnostics() async throws {
    let (podcast, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 40,
      podcastTitle: "Large detail"
    )
    let series = PodcastSeriesDetail(
      podcast: podcast,
      episodes: IdentifiedArrayOf(uniqueElements: episodes.map { ListableEpisode(from: $0) })
    )
    let state = PodcastDetailState.saved(series)
    let diagnostics = Container.shared.podcastDetailPerformanceDiagnostics()

    for _ in 0..<40 {
      #expect(await diagnostics.statesEqual(state, state))
    }

    let context = diagnostics.sentryContext()
    let samples = try #require(context["samples"] as? [[String: Any]])
    #expect(samples.count == 32)
    #expect(samples.last?["phase"] as? String == "stateComparison")
    #expect(samples.last?["mainThread"] as? Bool == false)
    #expect(samples.last?["episodeCount"] as? Int == episodes.count)
  }

  @Test("slow phases emit one thresholded warning")
  func slowPhaseEmitsWarning() {
    let diagnostics = Container.shared.podcastDetailPerformanceDiagnostics()
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()

    LogCapture.withSink { sink in
      diagnostics.measure(.episodeProjection, episodeCount: 500) {
        clock.advance(by: .milliseconds(300))
      }

      let warnings = sink.captured()
        .filter {
          $0.level == .warning && $0.message.contains("phase=episodeProjection")
        }
      #expect(warnings.count == 1)
      #expect(warnings.first?.message.contains("episodeCount=500") == true)
    }
  }
}
