// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("of transcription deletion reconciliation", .container)
struct TranscriptionDeletionTests {
  private let queue = Container.shared.transcriptionQueue()
  private let repo = Container.shared.repo()

  @Test("podcast deletion removes waiting transcriptions and updates positions")
  func podcastDeletionReconcilesWaitingTranscriptions() async throws {
    let doomed = try await makeSeries(episodeCount: 2, title: "Doomed")
    let surviving = try await makeSeries(episodeCount: 2, title: "Surviving")
    let doomedEpisodes = Array(doomed.episodes)
    let survivingEpisodes = Array(surviving.episodes)
    try await queue.enqueue([
      survivingEpisodes[0].id,
      doomedEpisodes[0].id,
      survivingEpisodes[1].id,
      doomedEpisodes[1].id,
    ])

    #expect(try await repo.deletePodcast(doomed.podcast.id))

    #expect(queue.episodeIDs == survivingEpisodes.map(\.id))
    #expect(
      queue.status(for: survivingEpisodes[1].id, hasTranscript: false)
        == .queued(position: 2, total: 2)
    )

    let reversedSurvivors = survivingEpisodes.reversed().map(\.id)
    #expect(try await queue.reorder(reversedSurvivors))
    #expect(try await Container.shared.transcriptionQueueStore().fetchAll() == reversedSurvivors)
  }

  @Test("batch podcast deletion removes mixed waiting work and preserves unaffected order")
  func batchPodcastDeletionReconcilesMixedWaitingWork() async throws {
    let firstDoomed = try await makeSeries(episodeCount: 3, title: "First doomed")
    let secondDoomed = try await makeSeries(episodeCount: 1, title: "Second doomed")
    let surviving = try await makeSeries(episodeCount: 3, title: "Surviving")
    let firstDoomedEpisodes = Array(firstDoomed.episodes)
    let secondDoomedEpisode = try #require(secondDoomed.episodes.first)
    let survivingEpisodes = Array(surviving.episodes)
    try await queue.enqueue([
      firstDoomedEpisodes[0].id,
      survivingEpisodes[0].id,
      secondDoomedEpisode.id,
      survivingEpisodes[1].id,
      firstDoomedEpisodes[1].id,
      survivingEpisodes[2].id,
    ])

    let deletedCount = try await repo.deletePodcast([
      firstDoomed.podcast.id,
      secondDoomed.podcast.id,
    ])

    #expect(deletedCount == 2)
    #expect(queue.episodeIDs == survivingEpisodes.map(\.id))
    #expect(
      try await Container.shared.transcriptionQueueStore().fetchAll()
        == survivingEpisodes.map(\.id)
    )
  }

  @Test("deleting the active episode stops it before deletion and advances surviving work")
  func activeEpisodeDeletionStopsWorkBeforeDeleting() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "done", startSeconds: 0, endSeconds: 60)]
    )
    let firstAnalysisStarted = AsyncSemaphore(value: 0)
    let firstAnalysisRelease = AsyncSemaphore(value: 0)
    let cancellationRelease = AsyncSemaphore(value: 0)
    let secondAnalysisRelease = AsyncSemaphore(value: 0)
    let analyzeCount = ThreadSafe(0)
    let cancellationCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            let invocation = analyzeCount {
              $0 += 1
              return $0
            }
            if invocation == 1 {
              firstAnalysisStarted.signal()
              try await firstAnalysisRelease.waitUnlessCancelled()
            } else if invocation == 2 {
              try await secondAnalysisRelease.waitUnlessCancelled()
            }
            return CMTime(seconds: endTime, preferredTimescale: 600)
          },
          cancelAudio: {
            cancellationCount { $0 += 1 }
            await cancellationRelease.wait()
          }
        )
      }
    }

    let processor = Container.shared.transcriptionProcessor()
    let activeEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Deleted while active",
      cachedFilename: "deleted-while-active.mp3",
      dataSize: 1
    )
    let survivingEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Survives deletion",
      cachedFilename: "survives-deletion.mp3",
      dataSize: 1
    )
    let activePodcastID = try #require(activeEpisode.podcastId)
    try await queue.enqueue([activeEpisode.id, survivingEpisode.id])
    processor.handleScenePhaseChange(to: .active)
    await firstAnalysisStarted.wait()
    try await Wait.until(
      { self.queue.progress[activeEpisode.id] != nil },
      { "Active transcription did not publish progress" }
    )

    let deletionCompleted = ThreadSafe(false)
    let deletionTask = Task {
      defer { deletionCompleted(true) }
      return try await repo.deletePodcast(activePodcastID)
    }
    defer {
      deletionTask.cancel()
      firstAnalysisRelease.signal()
      cancellationRelease.signal()
      secondAnalysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    try await Wait.until(
      { cancellationCount() == 1 || deletionCompleted() },
      { "Podcast deletion neither cancelled active work nor completed" }
    )
    #expect(cancellationCount() == 1)
    #expect(!deletionCompleted())
    #expect(try await repo.episode(activeEpisode.id) != nil)

    cancellationRelease.signal()
    #expect(try await deletionTask.value)
    try await Wait.until(
      { analyzeCount() == 2 },
      { "Surviving transcription did not start after deletion" }
    )

    #expect(try await repo.episode(activeEpisode.id) == nil)
    #expect(queue.episodeIDs == [survivingEpisode.id])
    #expect(!queue.failed.contains(activeEpisode.id))

    secondAnalysisRelease.signal()
    try await Wait.until(
      { self.queue.episodeIDs.isEmpty },
      { "Surviving transcription did not finish: \(self.queue.episodeIDs)" }
    )
    #expect(try await repo.episode(survivingEpisode.id)?.hasTranscript == true)
  }

  @Test("failed podcast deletion restores the queue and preserves cached files")
  func failedPodcastDeletionRestoresQueueAndPreservesCachedFiles() async throws {
    let doomed = try await makeSeries(episodeCount: 2, title: "Retained")
    let surviving = try await makeSeries(episodeCount: 1, title: "Unaffected")
    let doomedEpisodes = Array(doomed.episodes)
    let survivingEpisode = try #require(surviving.episodes.first)
    let cachedFilename = "retained-after-failed-deletion.mp3"
    let cachedData = Data([0x1])
    try #require(
      try await repo.updateCachedFilename(
        doomedEpisodes[0].id,
        cachedFilename: cachedFilename
      )
    )
    let cachedURL = CacheManager.resolveCachedFilepath(for: cachedFilename)
    let fileManager = try #require(Container.shared.fileManager() as? FakeFileManager)
    try await fileManager.writeData(cachedData, to: cachedURL.rawValue)
    let originalOrder = [
      doomedEpisodes[0].id,
      survivingEpisode.id,
      doomedEpisodes[1].id,
    ]
    try await queue.enqueue(originalOrder)
    try await Container.shared.appDB().unsafeTestDB
      .write { db in
        try db.execute(
          sql: """
            CREATE TEMP TRIGGER fail_podcast_delete
            BEFORE DELETE ON podcast
            BEGIN
              SELECT RAISE(ABORT, 'simulated podcast deletion failure');
            END
            """
        )
      }

    await #expect(throws: DatabaseError.self) {
      try await repo.deletePodcast([doomed.podcast.id])
    }

    #expect(queue.episodeIDs == originalOrder)
    #expect(try await Container.shared.transcriptionQueueStore().fetchAll() == originalOrder)
    #expect(try await repo.podcast(doomed.podcast.id) != nil)
    #expect(try await fileManager.readData(from: cachedURL.rawValue) == cachedData)
  }

  private func makeSeries(episodeCount: Int, title: String) async throws -> PodcastSeries {
    let identifier = UUID().uuidString
    return try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: title),
        unsavedEpisodes: try (0..<episodeCount)
          .map { index in
            try Create.unsavedEpisode(
              guid: GUID("\(identifier)-\(index)"),
              title: "\(title) \(index)"
            )
          }
      )
    )
  }
}
