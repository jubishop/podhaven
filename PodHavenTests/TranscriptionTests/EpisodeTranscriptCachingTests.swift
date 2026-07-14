// Copyright Justin Bishop, 2026

import FactoryKit
import Testing

@testable import PodHaven

@Suite("of episode transcript caching", .container)
struct EpisodeTranscriptCachingTests {
  @Test("a malformed stored transcript is decoded and logged only once")
  func malformedTranscriptDecodesOnce() async throws {
    let repo = Container.shared.repo()
    let podcastEpisode = try await Create.podcastEpisode()
    try await repo.updateTranscript(podcastEpisode.id, transcript: "not-json")
    let episode = try #require(try await repo.episode(podcastEpisode.id))

    LogCapture.withSink { sink in
      #expect(episode.decodedTranscript == nil)
      #expect(episode.decodedTranscript == nil)

      let decodeErrors = sink.captured()
        .filter {
          $0.message.contains("Failed to decode transcript")
        }
      #expect(decodeErrors.count == 1)
    }
  }
}
