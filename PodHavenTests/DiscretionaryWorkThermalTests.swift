// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI
import Testing

@testable import PodHaven

@Suite("Discretionary work thermal backpressure", .container)
struct DiscretionaryWorkThermalTests {
  @Test("thermal monitoring applies startup, registration-window, and later changes")
  func thermalMonitoringStartsBeforeForegroundPreparation() {
    let readings = ThreadSafe([ThermalPressure.nominal, .critical])
    Container.shared.currentThermalPressure.context(.test) {
      {
        readings { values in
          guard values.count > 1 else { return values[0] }
          return values.removeFirst()
        }
      }
    }

    Container.shared.thermalPressureMonitor().start()
    #expect(Container.shared.sharedState().thermalPressure == .critical)

    readings([.fair])
    Container.shared.notifier().post(ProcessInfo.thermalStateDidChangeNotification)
    #expect(Container.shared.sharedState().thermalPressure == .fair)
  }

  @Test("embedding work waits through critical pressure and resumes after recovery")
  func embeddingWaitsAndResumes() async throws {
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Thermal embeddings"
    )
    let processor = Container.shared.embeddingProcessor()
    processor.handleThermalPressureChange(to: .critical)
    processor.handleScenePhaseChange(to: .active)

    let repo = Container.shared.recommendationRepo()
    let revision = Container.shared.contextualEmbedding().revision
    for _ in 0..<20 {
      await (Container.shared.sleeper() as! FakeSleeper).advanceTime(by: .seconds(10))
      await Task.yield()
    }
    let pending = try await repo.episodesNeedingEmbeddings(revision: revision)
    #expect(Set(pending).isSuperset(of: episodes.map(\.id)))

    processor.handleThermalPressureChange(to: .nominal)
    try await RecommendationHelpers.untilAdvancing({
      let remaining = try await repo.episodesNeedingEmbeddings(revision: revision)
      return Set(remaining).isDisjoint(with: episodes.map(\.id))
    }) {
      "Embedding work did not resume after thermal recovery"
    }
    processor.handleScenePhaseChange(to: .background)
  }

  @Test("recommendation rescans coalesce while critical and resume after recovery")
  func recommendationRescansWaitAndResume() async throws {
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Thermal signals",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)
    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Thermal candidates"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    let engine = Container.shared.recommendationEngine()
    engine.handleThermalPressureChange(to: .critical)
    engine.start()
    for _ in 0..<20 {
      await (Container.shared.sleeper() as! FakeSleeper).advanceTime(by: .seconds(10))
      await Task.yield()
    }
    #expect(engine.scoringRevision == 0)

    engine.handleThermalPressureChange(to: .nominal)
    let recommendations = try await RecommendationHelpers.waitAdvancing {
      let result = try await engine.topRecommendations(limit: 10)
      return result.isEmpty ? nil : result
    }
    #expect(!recommendations.isEmpty)
  }

  @Test("on-device transcription waits through critical pressure and resumes")
  func transcriptionWaitsAndResumes() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hello", startSeconds: 0, endSeconds: 60)]
    )
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Thermal transcription",
      cachedFilename: "thermal.mp3",
      dataSize: 1
    )
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    try await queue.enqueue(episode.id)
    processor.handleThermalPressureChange(to: .critical)
    processor.handleScenePhaseChange(to: .active)

    for _ in 0..<20 { await Task.yield() }
    #expect(queue.episodeIDs == [episode.id])
    #expect(try await Container.shared.repo().episode(episode.id)?.hasTranscript == false)

    processor.handleThermalPressureChange(to: .nominal)
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "Transcription did not resume after thermal recovery" }
    )
    #expect(try await Container.shared.repo().episode(episode.id)?.hasTranscript == true)
    processor.handleScenePhaseChange(to: .background)
  }

  @Test("thermal pressure maps system states to work policy")
  func thermalPressurePolicy() {
    #expect(ThermalPressure(.nominal).permitsDiscretionaryWork)
    #expect(ThermalPressure(.fair).permitsDiscretionaryWork)
    #expect(!ThermalPressure(.serious).permitsDiscretionaryWork)
    #expect(!ThermalPressure(.critical).permitsDiscretionaryWork)
  }
}
