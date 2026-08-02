// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("of TranscriptionProcessor publisher replacements", .container)
struct TranscriptionProcessorReplacementTests {
  private func insertForcedReplacement(_ episodeID: Episode.ID) async throws {
    try await Container.shared.appDB().unsafeTestDB
      .write { db in
        try db.execute(
          sql: """
            INSERT INTO episodeTranscriptionQueue (episodeId, workMode)
            VALUES (?, 'onDeviceReplacement')
            """,
          arguments: [episodeID]
        )
      }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
  }

  @discardableResult
  private func storePublisherTranscript(
    for episodeID: Episode.ID,
    source: PublisherTranscriptReference,
    text: String = "Publisher words"
  ) async throws -> Transcript {
    let transcript = Transcript(
      segments: [TranscriptSegment(start: 0, end: 1, text: text)],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    #expect(
      try await Container.shared.repo()
        .storeTranscriptIfAbsent(
          episodeID,
          transcript: transcript,
          publisherSource: source
        )
    )
    return transcript
  }

  @Test("queue reorder preserves forced replacement intent")
  func reorderPreservesReplacementIntent() async throws {
    let replacementEpisode = try await Create.podcastEpisode()
    let ordinaryEpisode = try await Create.podcastEpisode()
    try await insertForcedReplacement(replacementEpisode.id)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    try await queue.enqueue(ordinaryEpisode.id)

    #expect(
      try await queue.reorder([ordinaryEpisode.id, replacementEpisode.id])
    )

    let workMode = try await Container.shared.appDB().unsafeTestDB
      .read { db in
        try String.fetchOne(
          db,
          sql: """
            SELECT workMode
            FROM episodeTranscriptionQueue
            WHERE episodeId = ?
            """,
          arguments: [replacementEpisode.id]
        )
      }
    #expect(workMode == "onDeviceReplacement")
  }

  @Test("forced replacement bypasses publisher preflight and transitions the observed source")
  @MainActor func forcedReplacementBypassesPublisherAndTransitionsSource() async throws {
    let replacementText = "Fresh on-device words"
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: replacementText,
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let analysisCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            analysisCount { $0 += 1 }
            return CMTime(seconds: endTime, preferredTimescale: 600)
          }
        )
      }
    }

    let transcriptURL = URL(string: "https://example.com/replacement.vtt")!
    let source = PublisherTranscriptReference(
      url: transcriptURL,
      mimeType: "text/vtt",
      language: "en-US"
    )
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Publisher replacement",
      cachedFilename: "publisher-replacement.mp3",
      dataSize: 1,
      publisherTranscriptReferences: [source]
    )
    let originalTranscript = try await storePublisherTranscript(
      for: episode.id,
      source: source
    )
    let loaded = try #require(try await Container.shared.repo().podcastEpisode(episode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))
    viewModel.appear()
    defer { viewModel.disappear() }

    try await insertForcedReplacement(episode.id)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    #expect(queue.episodeIDs == [episode.id])
    let processor = Container.shared.transcriptionProcessor()
    processor.handleScenePhaseChange(to: .active)
    defer { processor.handleScenePhaseChange(to: .background) }

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "Forced replacement did not drain" }
    )
    try await Wait.until(
      { @MainActor in
        viewModel.decodedTranscript?.segments.map(\.text) == [replacementText]
      },
      { @MainActor in
        "Expected observed on-device replacement, got \(String(describing: viewModel.decodedTranscript))"
      }
    )

    let stored = try #require(try await Container.shared.repo().episode(episode.id))
    #expect(stored.decodedTranscript != originalTranscript)
    #expect(stored.decodedTranscript?.segments.map(\.text) == [replacementText])
    #expect(stored.publisherTranscriptSource == nil)
    #expect(analysisCount() == 1)
    let publisherSession = Container.shared.publisherTranscriptSession() as! FakeDataFetchable
    #expect(await publisherSession.requests.isEmpty)
    #expect(try await Container.shared.repo().transcriptionCheckpoint(episode.id) == nil)
  }

  @Test("failed forced replacement preserves publisher transcript and exposes retry")
  @MainActor func failedReplacementPreservesPublisherTranscript() async throws {
    TranscriptionHelpers.stubSpeechFailure()
    let source = PublisherTranscriptReference(
      url: URL(string: "https://example.com/failing-replacement.vtt")!,
      mimeType: "text/vtt",
      language: "en-US"
    )
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Failing publisher replacement",
      cachedFilename: "failing-publisher-replacement.mp3",
      dataSize: 1,
      publisherTranscriptReferences: [source]
    )
    let originalTranscript = try await storePublisherTranscript(
      for: episode.id,
      source: source
    )
    try await insertForcedReplacement(episode.id)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let processor = Container.shared.transcriptionProcessor()
    processor.handleScenePhaseChange(to: .active)
    defer { processor.handleScenePhaseChange(to: .background) }

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "Failed replacement remained queued" }
    )

    let stored = try #require(try await Container.shared.repo().episode(episode.id))
    #expect(stored.decodedTranscript == originalTranscript)
    #expect(stored.publisherTranscriptSource == source)
    #expect(queue.failed.contains(episode.id))
    let loaded = try #require(try await Container.shared.repo().podcastEpisode(episode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))
    #expect(viewModel.transcriptionStatus == .failed)
  }

  @Test("pausing forced replacement preserves publisher transcript")
  func pausingReplacementPreservesPublisherTranscript() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "Cancelled replacement",
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let analysisStarted = ThreadSafe(false)
    let analysisRelease = AsyncSemaphore(value: 0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            analysisStarted(true)
            try await analysisRelease.waitUnlessCancelled()
            return CMTime(seconds: endTime, preferredTimescale: 600)
          }
        )
      }
    }
    let source = PublisherTranscriptReference(
      url: URL(string: "https://example.com/paused-replacement.vtt")!,
      mimeType: "text/vtt",
      language: "en-US"
    )
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Paused publisher replacement",
      cachedFilename: "paused-publisher-replacement.mp3",
      dataSize: 1
    )
    let originalTranscript = try await storePublisherTranscript(
      for: episode.id,
      source: source
    )
    try await insertForcedReplacement(episode.id)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let processor = Container.shared.transcriptionProcessor()
    processor.handleScenePhaseChange(to: .active)
    defer {
      analysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    try await Wait.until(
      { analysisStarted() },
      { "Forced replacement never began on-device analysis" }
    )
    try await processor.pause(episode.id)
    try await Wait.until(
      {
        queue.episodeIDs.isEmpty
          && queue.interruptions[episode.id] == nil
          && queue.progress[episode.id] == nil
      },
      { "Forced replacement did not finish pausing" }
    )

    let stored = try #require(try await Container.shared.repo().episode(episode.id))
    #expect(stored.decodedTranscript == originalTranscript)
    #expect(stored.publisherTranscriptSource == source)
    #expect(!queue.failed.contains(episode.id))
  }

  @Test("pause during final promotion preserves replacement progress")
  func pauseDuringFinalPromotionPreservesProgress() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "Completed replacement",
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let source = PublisherTranscriptReference(
      url: URL(string: "https://example.com/promotion-pause.vtt")!,
      mimeType: "text/vtt",
      language: "en-US"
    )
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Paused during publisher promotion",
      cachedFilename: "paused-during-publisher-promotion.mp3",
      dataSize: 1
    )
    let originalTranscript = try await storePublisherTranscript(
      for: episode.id,
      source: source
    )
    try await insertForcedReplacement(episode.id)
    let repo = Container.shared.repo()
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.pendingPublisherReplacementSuspend(true)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let processor = Container.shared.transcriptionProcessor()
    processor.handleScenePhaseChange(to: .active)
    defer {
      Task { await fakeRepo.resumeAllPublisherReplacementSuspensions() }
      processor.handleScenePhaseChange(to: .background)
    }

    try await fakeRepo.waitForPublisherReplacementSuspended()
    let checkpoint = try #require(try await repo.transcriptionCheckpoint(episode.id))

    let pauseTask = Task {
      try await processor.pause(episode.id)
    }
    try await Wait.until(
      { queue.status(for: episode.id, hasTranscript: true) == .pausing },
      { "Processor did not claim final promotion for pausing" }
    )
    #expect(queue.status(for: episode.id, hasTranscript: true) == .pausing)
    await fakeRepo.resumeAllPublisherReplacementSuspensions()
    try await pauseTask.value

    try await Wait.until(
      {
        queue.episodeIDs.isEmpty
          && queue.interruptions[episode.id] == nil
          && queue.progress[episode.id] == nil
      },
      { "Replacement did not release promotion after pause took queue ownership" }
    )
    let stored = try #require(try await repo.episode(episode.id))
    #expect(stored.decodedTranscript == originalTranscript)
    #expect(stored.publisherTranscriptSource == source)
    #expect(try await repo.transcriptionCheckpoint(episode.id) == checkpoint)
    #expect(!queue.failed.contains(episode.id))
  }

  @Test("publisher import cleanup preserves a replacement requested during cancellation")
  func publisherImportCleanupPreservesConcurrentReplacement() async throws {
    let replacementText = "On-device replacement wins"
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: replacementText,
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let firstAnalysisStarted = AsyncSemaphore(value: 0)
    let firstAnalysisRelease = AsyncSemaphore(value: 0)
    let cancellationStarted = AsyncSemaphore(value: 0)
    let cancellationRelease = AsyncSemaphore(value: 0)
    let analyzerCreations = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        let invocation = analyzerCreations {
          $0 += 1
          return $0
        }
        return FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            if invocation == 1 {
              firstAnalysisStarted.signal()
              try await firstAnalysisRelease.waitUnlessCancelled()
            }
            return CMTime(seconds: endTime, preferredTimescale: 600)
          },
          cancelAudio: {
            guard invocation == 1 else { return }
            cancellationStarted.signal()
            await cancellationRelease.wait()
          }
        )
      }
    }

    let transcriptURL = URL(string: "https://example.com/concurrent-replacement.vtt")!
    let source = PublisherTranscriptReference(
      url: transcriptURL,
      mimeType: "text/vtt",
      language: "en"
    )
    let fetchCount = ThreadSafe(0)
    let publisherSession = Container.shared.publisherTranscriptSession() as! FakeDataFetchable
    await publisherSession.respond(to: transcriptURL) { url in
      let invocation = fetchCount {
        $0 += 1
        return $0
      }
      let data =
        invocation == 1
        ? Data("not WebVTT".utf8)
        : Data(
          "WEBVTT\n\n00:00:02.000 --> 00:00:04.000\nPublisher words".utf8
        )
      return (data, URL.response(url))
    }

    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Concurrent publisher replacement",
      cachedFilename: "concurrent-publisher-replacement.mp3",
      dataSize: 1,
      publisherTranscriptReferences: [source]
    )
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    try await queue.enqueue(episode.id)
    processor.handleScenePhaseChange(to: .active)
    defer {
      firstAnalysisRelease.signal()
      cancellationRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await firstAnalysisStarted.wait()
    let importTask = Task {
      await processor.importPublisherTranscript(for: episode.id)
    }
    defer { importTask.cancel() }
    await cancellationStarted.wait()

    try await processor.enqueuePublisherReplacement(episode.id)
    #expect(queue.work(for: episode.id)?.mode == .onDeviceReplacement)
    cancellationRelease.signal()
    #expect(await importTask.value)

    try await Wait.until(
      {
        let stored = try await Container.shared.repo().episode(episode.id)
        return queue.episodeIDs.isEmpty
          && stored?.publisherTranscriptSource == nil
      },
      { "Concurrent replacement did not become canonical" }
    )
    let stored = try #require(try await Container.shared.repo().episode(episode.id))
    #expect(stored.decodedTranscript?.segments.map(\.text) == [replacementText])
    #expect(analyzerCreations() == 2)
    #expect(fetchCount() == 2)
  }

  @Test("publisher cleanup leaves an active forced replacement running")
  func publisherCleanupLeavesActiveReplacementRunning() async throws {
    let replacementText = "Active replacement survives cleanup"
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: replacementText,
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let analysisStarted = AsyncSemaphore(value: 0)
    let analysisRelease = AsyncSemaphore(value: 0)
    let cancellationCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            analysisStarted.signal()
            try await analysisRelease.waitUnlessCancelled()
            return CMTime(seconds: endTime, preferredTimescale: 600)
          },
          cancelAudio: {
            cancellationCount { $0 += 1 }
          }
        )
      }
    }

    let transcriptURL = URL(string: "https://example.com/active-replacement.vtt")!
    let source = PublisherTranscriptReference(
      url: transcriptURL,
      mimeType: "text/vtt",
      language: "en"
    )
    let publisherSession = Container.shared.publisherTranscriptSession() as! FakeDataFetchable
    await publisherSession.respond(to: transcriptURL) { url in
      (
        Data(
          "WEBVTT\n\n00:00:02.000 --> 00:00:04.000\nPublisher words".utf8
        ),
        URL.response(url)
      )
    }
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Active replacement during publisher cleanup",
      cachedFilename: "active-replacement-cleanup.mp3",
      dataSize: 1,
      publisherTranscriptReferences: [source]
    )
    let repo = Container.shared.repo()
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.pendingPublisherTranscriptStoreAfterWriteSuspend(true)
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    processor.handleScenePhaseChange(to: .active)
    let importTask = Task {
      await processor.importPublisherTranscript(for: episode.id)
    }
    defer {
      importTask.cancel()
      Task { await fakeRepo.resumeAllPublisherTranscriptStoreAfterWriteSuspensions() }
      analysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    try await fakeRepo.waitForPublisherTranscriptStoreAfterWriteSuspended()
    try await processor.enqueuePublisherReplacement(episode.id)
    await analysisStarted.wait()

    await fakeRepo.resumeAllPublisherTranscriptStoreAfterWriteSuspensions()
    #expect(await importTask.value)
    #expect(cancellationCount() == 0)

    analysisRelease.signal()
    try await Wait.until(
      {
        let stored = try await repo.episode(episode.id)
        return queue.episodeIDs.isEmpty
          && stored?.decodedTranscript?.segments.map(\.text) == [replacementText]
          && stored?.publisherTranscriptSource == nil
      },
      { "Publisher cleanup prevented the active replacement from finishing" }
    )
  }

  @Test("final replacement promotion reconciles an overlapping queue reorder")
  func finalReplacementPromotionReconcilesOverlappingReorder() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "Serialized replacement",
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let source = PublisherTranscriptReference(
      url: URL(string: "https://example.com/serialized-replacement.vtt")!,
      mimeType: "text/vtt",
      language: "en-US"
    )
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Serialized publisher replacement",
      cachedFilename: "serialized-publisher-replacement.mp3",
      dataSize: 1
    )
    try await storePublisherTranscript(for: episode.id, source: source)
    try await insertForcedReplacement(episode.id)

    let reorderStoreEntered = ThreadSafe(false)
    let reorderStoreRelease = AsyncSemaphore(value: 0)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: [episode.id],
      workModes: [episode.id: .onDeviceReplacement],
      beforeReorder: { _ in
        reorderStoreEntered(true)
        await reorderStoreRelease.wait()
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)

    let repo = Container.shared.repo()
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.pendingPublisherReplacementSuspend(true)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let processor = Container.shared.transcriptionProcessor()
    processor.handleScenePhaseChange(to: .active)
    defer {
      Task { await fakeRepo.resumeAllPublisherReplacementSuspensions() }
      reorderStoreRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    try await fakeRepo.waitForPublisherReplacementSuspended()
    let reorderTask = Task(priority: .high) {
      try await processor.reorder([episode.id])
    }
    try await Wait.until(
      { reorderStoreEntered() },
      { "Queue reorder did not overlap final promotion" }
    )

    await fakeRepo.resumeAllPublisherReplacementSuspensions()
    reorderStoreRelease.signal()
    let reordered = try await reorderTask.value

    try await Wait.until(
      {
        queue.episodeIDs.isEmpty && store.removeCalls == [episode.id]
      },
      { "Final promotion did not reconcile the overlapping reorder" }
    )
    #expect(reordered)
  }

  @Test("active reorder cannot cancel committed replacement reconciliation")
  func activeReorderCannotCancelCommittedReplacementReconciliation() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "Completed locally",
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let waitingAnalysisStarted = AsyncSemaphore(value: 0)
    let waitingAnalysisRelease = AsyncSemaphore(value: 0)
    let analyzerCreations = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        let invocation = analyzerCreations {
          $0 += 1
          return $0
        }
        return FakeSpeechAnalyzer { _, endTime in
          if invocation == 2 {
            waitingAnalysisStarted.signal()
            try await waitingAnalysisRelease.waitUnlessCancelled()
          }
          return CMTime(seconds: endTime, preferredTimescale: 600)
        }
      }
    }

    let source = PublisherTranscriptReference(
      url: URL(string: "https://example.com/reordered-after-commit.vtt")!,
      mimeType: "text/vtt",
      language: "en-US"
    )
    let replacementEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Committed replacement moved from head",
      cachedFilename: "committed-replacement-moved.mp3",
      dataSize: 1
    )
    let waitingEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Promoted while replacement commits",
      cachedFilename: "promoted-during-replacement.mp3",
      dataSize: 1
    )
    try await storePublisherTranscript(
      for: replacementEpisode.id,
      source: source
    )
    try await insertForcedReplacement(replacementEpisode.id)
    try await Container.shared.transcriptionQueue().enqueue(waitingEpisode.id)

    let reorderPersisted = AsyncSemaphore(value: 0)
    let reorderReturnRelease = AsyncSemaphore(value: 0)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: [replacementEpisode.id, waitingEpisode.id],
      workModes: [replacementEpisode.id: .onDeviceReplacement],
      afterReorder: { _ in
        reorderPersisted.signal()
        await reorderReturnRelease.wait()
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)

    let repo = Container.shared.repo()
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.pendingPublisherReplacementSuspend(true)
    fakeRepo.pendingPublisherReplacementAfterWriteSuspend(true)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let processor = Container.shared.transcriptionProcessor()
    processor.handleScenePhaseChange(to: .active)
    defer {
      Task {
        await fakeRepo.resumeAllPublisherReplacementSuspensions()
        await fakeRepo.resumeAllPublisherReplacementAfterWriteSuspensions()
      }
      reorderReturnRelease.signal()
      waitingAnalysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    try await fakeRepo.waitForPublisherReplacementSuspended()
    let reorderTask = Task {
      try await processor.reorder([
        waitingEpisode.id,
        replacementEpisode.id,
      ])
    }
    await reorderPersisted.wait()

    await fakeRepo.resumeAllPublisherReplacementSuspensions()
    try await fakeRepo.waitForPublisherReplacementAfterWriteSuspended()
    reorderReturnRelease.signal()
    #expect(try await reorderTask.value)
    await fakeRepo.resumeAllPublisherReplacementAfterWriteSuspensions()
    await waitingAnalysisStarted.wait()

    #expect(queue.episodeIDs == [waitingEpisode.id])
    #expect(
      try await store.fetchAll().map(\.episodeID) == [waitingEpisode.id]
    )
    let stored = try #require(
      try await repo.episode(replacementEpisode.id)
    )
    #expect(stored.publisherTranscriptSource == nil)

    waitingAnalysisRelease.signal()
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "Queue did not finish after replacement reconciliation" }
    )
  }
}
