// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("of RefreshManager publisher transcript tests", .container)
struct RefreshManagerPublisherTranscriptTests {
  private var feedSession: FakeDataFetchable {
    Container.shared.podcastFeedSession() as! FakeDataFetchable
  }

  private var transcriptSession: FakeDataFetchable {
    Container.shared.publisherTranscriptSession() as! FakeDataFetchable
  }

  private var notificationCenter: FakeUserNotificationCenter {
    Container.shared.userNotificationCenter() as! FakeUserNotificationCenter
  }

  @Test("new publisher transcript removes automatic on-device queue entry")
  func newPublisherTranscriptRemovesAutomaticQueueEntry() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/publisher-feed.rss")!)
    let transcriptURL = URL(string: "https://example.com/new-episode.vtt")!
    let initialFeed = try await PodcastFeed.parse(
      Self.feedData(feedURL: feedURL, transcriptURL: nil),
      from: feedURL
    )
    let initialPodcast = try initialFeed.toUnsavedPodcast()
    let repo = Container.shared.repo()
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try UnsavedPodcast(
          feedURL: initialPodcast.feedURL,
          title: initialPodcast.title,
          image: initialPodcast.image,
          description: initialPodcast.description,
          link: initialPodcast.link,
          alwaysTranscribeNewEpisodes: true
        ),
        unsavedEpisodes: initialFeed.toUnsavedEpisodes()
      )
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(feedURL: feedURL, transcriptURL: transcriptURL)
    )
    await transcriptSession.respond(
      to: transcriptURL,
      data: Data(
        """
        WEBVTT

        00:00:01.500 --> 00:00:03.250
        <v Publisher>Publisher supplied words
        """
        .utf8
      )
    )
    let transcriptionQueue = Container.shared.transcriptionQueue()
    await transcriptionQueue.waitUntilLoaded()

    try await Container.shared.refreshManager().refreshSeries(podcast: series.podcast)

    let refreshed = try #require(try await repo.podcastSeries(series.id))
    let importedEpisode = try #require(
      refreshed.episodes.first { $0.guid == GUID("publisher-new") }
    )
    let transcript = try #require(importedEpisode.decodedTranscript)
    #expect(
      transcript.segments == [
        TranscriptSegment(
          start: 1.5,
          end: 3.25,
          text: "Publisher supplied words"
        )
      ]
    )
    #expect(importedEpisode.publisherTranscriptSource?.url == transcriptURL)
    let matchingEpisodeIDs = try await repo.db.read { db in
      try Int64.fetchAll(
        db,
        sql: """
          SELECT rowid
          FROM episode_transcript_fts
          WHERE episode_transcript_fts MATCH ?
          """,
        arguments: [#""Publisher supplied""#]
      )
    }
    #expect(matchingEpisodeIDs == [importedEpisode.id.rawValue])
    #expect(transcriptionQueue.episodeIDs.isEmpty)
  }

  @Test("automatic transcription queues before publisher retrieval completes")
  func queuesAutomaticTranscriptionBeforePublisherRetrievalCompletes() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/queued-before-fetch.rss")!)
    let transcriptURL = URL(string: "https://example.com/queued-before-fetch.vtt")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: true
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(feedURL: feedURL, transcriptURL: transcriptURL)
    )
    let fetch = await transcriptSession.releaseWaitRespond(
      to: transcriptURL,
      data: Data(
        "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nQueued before retrieval".utf8
      )
    )
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let repo = Container.shared.repo()

    let refreshTask = Task {
      try await Container.shared.refreshManager().refreshSeries(podcast: series.podcast)
    }
    defer {
      refreshTask.cancel()
      fetch.finish.signal()
    }
    await fetch.started.wait()

    let refreshed = try #require(try await repo.podcastSeries(series.id))
    let newEpisode = try #require(
      refreshed.episodes.first { $0.guid == GUID("publisher-new") }
    )
    #expect(queue.episodeIDs == [newEpisode.id])

    fetch.finish.signal()
    try await refreshTask.value
    #expect(queue.episodeIDs.isEmpty)
  }

  @Test("new-episode notification is scheduled before publisher retrieval completes")
  func schedulesNotificationBeforePublisherRetrievalCompletes() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/notify-before-fetch.rss")!)
    let transcriptURL = URL(string: "https://example.com/notify-before-fetch.vtt")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: false,
      notifyNewEpisodes: true
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(feedURL: feedURL, transcriptURL: transcriptURL)
    )
    let fetch = await transcriptSession.releaseWaitRespond(
      to: transcriptURL,
      data: Data(
        "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nNotify before retrieval".utf8
      )
    )
    notificationCenter.clearAllCalls()

    let refreshTask = Task {
      try await Container.shared.refreshManager().refreshSeries(podcast: series.podcast)
    }
    defer {
      refreshTask.cancel()
      fetch.finish.signal()
    }
    await fetch.started.wait()

    #expect(notificationCenter.addedRequests.count == 1)

    fetch.finish.signal()
    try await refreshTask.value
  }

  @Test("expired background refresh leaves demand for a network publisher task")
  func expiredBackgroundRefreshLeavesDemandForPublisherTask() async throws {
    Container.shared.speechModelManager.register {
      FakeSpeechModelManager(supportedIdentifiers: [])
    }
    let availability = Container.shared.transcriptionAvailability()
    await availability.prepare()
    #expect(availability.state == .unavailable)

    let feedURL = FeedURL(URL(string: "https://example.com/cancelled-publisher-feed.rss")!)
    let transcriptURL = URL(string: "https://example.com/cancelled-publisher.vtt")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: false,
      subscriptionDate: Date(timeIntervalSince1970: 1)
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(feedURL: feedURL, transcriptURL: transcriptURL)
    )
    let fetch = await transcriptSession.releaseWaitRespond(
      to: transcriptURL,
      data: Data(
        "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nRecovered publisher words".utf8
      )
    )
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let scheduler = try #require(
      Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler
    )
    let publisherProcessor = Container.shared.publisherTranscriptProcessor()
    let publisherIdentifier = "\(AppInfo.bundleIdentifier).publisherTranscripts"
    await queue.waitUntilLoaded()
    publisherProcessor.register()
    try await Wait.until(
      {
        scheduler.cancelledIdentifiers.contains(publisherIdentifier)
          && !scheduler.pendingIdentifiers.contains(publisherIdentifier)
      },
      { "Initial publisher-demand reconciliation did not finish" }
    )

    let refreshScheduler = Container.shared.refreshScheduler()
    refreshScheduler.register()
    let feedIdentifier = "\(AppInfo.bundleIdentifier).feedRefresh"
    let feedTask = try #require(
      scheduler.launchTask(withIdentifier: feedIdentifier)
    )
    defer {
      feedTask.expire()
      fetch.finish.signal()
    }
    await fetch.started.wait()

    let committedSeries = try #require(try await repo.podcastSeries(series.id))
    let committedEpisode = try #require(
      committedSeries.episodes.first { $0.guid == GUID("publisher-new") }
    )
    #expect(!committedEpisode.hasTranscript)
    #expect(queue.episodeIDs.isEmpty)
    let committedJobCount = try await repo.db.read { db in
      try PublisherTranscriptImportJob
        .filter(PublisherTranscriptImportJob.Columns.episodeId == committedEpisode.id)
        .fetchCount(db)
    }
    #expect(committedJobCount == 1)

    feedTask.expire()
    try await Wait.until(
      { feedTask.completionResults == [false] },
      { "Expired feed background task did not complete unsuccessfully" }
    )

    await transcriptSession.respond(
      to: transcriptURL,
      data: Data(
        "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nRecovered publisher words".utf8
      )
    )
    fetch.finish.signal()

    try await Wait.until(
      { scheduler.pendingIdentifiers.contains(publisherIdentifier) },
      { "Durable publisher demand did not schedule background work" }
    )
    let publisherRequest = try #require(
      scheduler.submissions.last { $0.identifier == publisherIdentifier }
    )
    #expect(publisherRequest.isProcessing)
    #expect(publisherRequest.requiresNetworkConnectivity)
    let publisherTask = try #require(
      scheduler.launchTask(withIdentifier: publisherIdentifier)
    )
    try await Wait.until(
      { publisherTask.completionResults == [true] },
      { "Publisher transcript background task did not complete successfully" }
    )

    let recovered = try #require(try await repo.episode(committedEpisode.id))
    #expect(recovered.decodedTranscript?.segments.map(\.text) == ["Recovered publisher words"])
    #expect(recovered.publisherTranscriptSource?.url == transcriptURL)
    #expect(queue.episodeIDs.isEmpty)
    #expect(await transcriptSession.requests.filter { $0 == transcriptURL }.count == 2)
    let recoveredJobCount = try await repo.db.read { db in
      try PublisherTranscriptImportJob
        .filter(PublisherTranscriptImportJob.Columns.episodeId == committedEpisode.id)
        .fetchCount(db)
    }
    #expect(recoveredJobCount == 0)
  }

  @Test("retryable publisher failure succeeds on a later durable attempt")
  func retryablePublisherFailureSucceedsLater() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/failing-publisher-feed.rss")!)
    let jsonURL = URL(string: "https://example.com/malformed.json")!
    let webVTTURL = URL(string: "https://example.com/unavailable.vtt")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: true
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(
        feedURL: feedURL,
        newEpisodeTranscripts: """
          <podcast:transcript url="\(jsonURL.absoluteString)" type="application/json" language="en" />
          <podcast:transcript url="\(webVTTURL.absoluteString)" type="text/vtt" language="en" />
          """
      )
    )
    await transcriptSession.respond(
      to: jsonURL,
      data: Data(#"{"segments":[{"body":"missing timecodes"}]}"#.utf8)
    )
    await transcriptSession.respond(to: webVTTURL, error: URLError(.cannotConnectToHost))
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let refreshManager = Container.shared.refreshManager()
    Container.shared.fakeDate().freeze(at: Date(timeIntervalSince1970: 1_000))

    try await refreshManager.refreshSeries(podcast: series.podcast)

    await transcriptSession.respond(
      to: webVTTURL,
      data: Data(
        "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nPublisher retry succeeded".utf8
      )
    )
    Container.shared.fakeDate().freeze(at: Date(timeIntervalSince1970: 2_000))
    try await refreshManager.refreshSeries(podcast: series.podcast)

    let refreshed = try #require(
      try await Container.shared.repo().podcastSeries(series.id)
    )
    let episode = try #require(
      refreshed.episodes.first { $0.guid == GUID("publisher-new") }
    )
    #expect(episode.decodedTranscript?.segments.map(\.text) == ["Publisher retry succeeded"])
    #expect(queue.episodeIDs.isEmpty)
    #expect(await transcriptSession.requests.filter { $0 == jsonURL }.count == 2)
    #expect(await transcriptSession.requests.filter { $0 == webVTTURL }.count == 2)
    let jobCount = try await Container.shared.repo().db
      .read { db in
        try PublisherTranscriptImportJob.fetchCount(db)
      }
    #expect(jobCount == 0)
  }

  @Test("permanently unusable publisher candidates are not retried")
  func permanentlyUnusableCandidatesAreNotRetried() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/terminal-publisher-feed.rss")!)
    let transcriptURL = URL(string: "https://example.com/terminal.json")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: false
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(feedURL: feedURL, transcriptURL: transcriptURL)
    )
    await transcriptSession.respond(
      to: transcriptURL,
      data: Data(#"{"segments":[{"body":"missing timecodes"}]}"#.utf8)
    )
    let refreshManager = Container.shared.refreshManager()
    Container.shared.fakeDate().freeze(at: Date(timeIntervalSince1970: 1_000))

    try await refreshManager.refreshSeries(podcast: series.podcast)
    Container.shared.fakeDate().freeze(at: Date(timeIntervalSince1970: 2_000))
    try await refreshManager.refreshSeries(podcast: series.podcast)

    let refreshed = try #require(
      try await Container.shared.repo().podcastSeries(series.id)
    )
    let episode = try #require(
      refreshed.episodes.first { $0.guid == GUID("publisher-new") }
    )
    #expect(!episode.hasTranscript)
    #expect(await transcriptSession.requests.filter { $0 == transcriptURL }.count == 1)
    let jobCount = try await Container.shared.repo().db
      .read { db in
        try PublisherTranscriptImportJob.fetchCount(db)
      }
    #expect(jobCount == 0)
  }

  @Test("retryable publisher failures stop after the bounded attempt limit")
  func retryableFailuresStopAfterAttemptLimit() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/bounded-publisher-feed.rss")!)
    let transcriptURL = URL(string: "https://example.com/bounded.vtt")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: false
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(feedURL: feedURL, transcriptURL: transcriptURL)
    )
    await transcriptSession.respond(
      to: transcriptURL,
      error: URLError(.notConnectedToInternet)
    )
    let refreshManager = Container.shared.refreshManager()

    let maximumAttemptCount = PublisherTranscriptImportStore.maximumAttemptCount
    for attempt in 1...(maximumAttemptCount + 1) {
      Container.shared.fakeDate()
        .freeze(
          at: Date(timeIntervalSince1970: Double(attempt) * 1_000)
        )
      try await refreshManager.refreshSeries(podcast: series.podcast)
    }

    #expect(
      await transcriptSession.requests.filter { $0 == transcriptURL }.count
        == maximumAttemptCount
    )
    let jobCount = try await Container.shared.repo().db
      .read { db in
        try PublisherTranscriptImportJob.fetchCount(db)
      }
    #expect(jobCount == 0)
  }

  @Test("removing the last supported reference clears deferred publisher demand")
  func removedReferencesClearDeferredDemand() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/obsolete-publisher-feed.rss")!)
    let transcriptURL = URL(string: "https://example.com/obsolete.vtt")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: false
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(feedURL: feedURL, transcriptURL: transcriptURL)
    )
    await transcriptSession.respond(
      to: transcriptURL,
      error: URLError(.notConnectedToInternet)
    )
    let refreshManager = Container.shared.refreshManager()
    let repo = Container.shared.repo()
    Container.shared.fakeDate().freeze(at: Date(timeIntervalSince1970: 1_000))

    try await refreshManager.refreshSeries(podcast: series.podcast)

    let refreshed = try #require(try await repo.podcastSeries(series.id))
    let episode = try #require(
      refreshed.episodes.first { $0.guid == GUID("publisher-new") }
    )
    let deferredJobCount = try await repo.db.read { db in
      try PublisherTranscriptImportJob
        .filter(PublisherTranscriptImportJob.Columns.episodeId == episode.id)
        .fetchCount(db)
    }
    #expect(deferredJobCount == 1)

    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(feedURL: feedURL, newEpisodeTranscripts: "")
    )
    Container.shared.fakeDate().freeze(at: Date(timeIntervalSince1970: 1_010))
    try await refreshManager.refreshSeries(podcast: series.podcast)

    let updated = try #require(try await repo.episode(episode.id))
    #expect(updated.publisherTranscriptReferences.isEmpty)
    #expect(await transcriptSession.requests.filter { $0 == transcriptURL }.count == 1)
    let remainingJobCount = try await repo.db.read { db in
      try PublisherTranscriptImportJob
        .filter(PublisherTranscriptImportJob.Columns.episodeId == episode.id)
        .fetchCount(db)
    }
    #expect(remainingJobCount == 0)
  }

  @Test("untimed resources are ignored and leave automatic transcription eligible")
  func untimedResourcesRemainEligible() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/untimed-publisher-feed.rss")!)
    let plainURL = URL(string: "https://example.com/transcript.txt")!
    let htmlURL = URL(string: "https://example.com/transcript.html")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: true
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(
        feedURL: feedURL,
        newEpisodeTranscripts: """
          <podcast:transcript url="\(plainURL.absoluteString)" type="text/plain" language="en" />
          <podcast:transcript url="\(htmlURL.absoluteString)" type="text/html" language="en" />
          """
      )
    )
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()

    try await Container.shared.refreshManager().refreshSeries(podcast: series.podcast)

    let refreshed = try #require(
      try await Container.shared.repo().podcastSeries(series.id)
    )
    let episode = try #require(
      refreshed.episodes.first { $0.guid == GUID("publisher-new") }
    )
    #expect(!episode.hasTranscript)
    #expect(queue.episodeIDs == [episode.id])
    let requests = await transcriptSession.requests
    #expect(!requests.contains(plainURL))
    #expect(!requests.contains(htmlURL))
  }

  @Test("publisher resources never replace an existing usable transcript")
  func existingTranscriptIsNotReplaced() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/no-replacement-feed.rss")!)
    let publisherURL = URL(string: "https://example.com/replacement.vtt")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: false
    )
    let existingEpisode = try #require(series.episodes.first)
    let existingTranscript = Transcript(
      segments: [TranscriptSegment(start: 0, end: 2, text: "Keep existing")],
      locale: "en",
      createdAt: Date(timeIntervalSince1970: 1)
    )
    let repo = Container.shared.repo()
    try await repo.updateTranscript(
      existingEpisode.id,
      transcript: existingTranscript.jsonString()
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(
        feedURL: feedURL,
        existingEpisodeTranscripts: """
          <podcast:transcript url="\(publisherURL.absoluteString)" type="text/vtt" language="en" />
          """
      )
    )
    await transcriptSession.respond(
      to: publisherURL,
      data: Data("WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nReplace me".utf8)
    )

    try await Container.shared.refreshManager().refreshSeries(podcast: series.podcast)

    let stored = try #require(try await repo.episode(existingEpisode.id))
    #expect(stored.decodedTranscript == existingTranscript)
    #expect(stored.publisherTranscriptSource == nil)
    let requests = await transcriptSession.requests
    #expect(!requests.contains(publisherURL))
  }

  @Test("a competing transcript writer clears publisher demand without replacement")
  func competingTranscriptWriterClearsDemand() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/competing-writer-feed.rss")!)
    let publisherURL = URL(string: "https://example.com/competing-writer.vtt")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: false
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(feedURL: feedURL, transcriptURL: publisherURL)
    )
    let fetch = await transcriptSession.releaseWaitRespond(
      to: publisherURL,
      data: Data("WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nPublisher loses".utf8)
    )
    let repo = Container.shared.repo()
    let refreshTask = Task {
      try await Container.shared.refreshManager().refreshSeries(podcast: series.podcast)
    }
    defer {
      refreshTask.cancel()
      fetch.finish.signal()
    }

    await fetch.started.wait()
    let committedSeries = try #require(try await repo.podcastSeries(series.id))
    let episode = try #require(
      committedSeries.episodes.first { $0.guid == GUID("publisher-new") }
    )
    let competingTranscript = Transcript(
      segments: [TranscriptSegment(start: 0, end: 1, text: "Competing writer wins")],
      locale: "en",
      createdAt: Date(timeIntervalSince1970: 1)
    )
    try await repo.updateTranscript(
      episode.id,
      transcript: competingTranscript.jsonString()
    )

    fetch.finish.signal()
    try await refreshTask.value

    let stored = try #require(try await repo.episode(episode.id))
    #expect(stored.decodedTranscript == competingTranscript)
    #expect(stored.publisherTranscriptSource == nil)
    let jobCount = try await repo.db.read { db in
      try PublisherTranscriptImportJob.fetchCount(db)
    }
    #expect(jobCount == 0)
  }

  @Test("a new reference on an observed episode is persisted for deferred retrieval")
  func persistsReferenceAfterKnownEmpty() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/observed-empty-feed.rss")!)
    let transcriptURL = URL(string: "https://example.com/observed-empty.vtt")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: false
    )
    let existingEpisode = try #require(series.episodes.first)
    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(
        feedURL: feedURL,
        existingEpisodeTranscripts: """
          <podcast:transcript url="\(transcriptURL.absoluteString)" type="text/vtt" language="en" />
          """
      )
    )
    await transcriptSession.respond(
      to: transcriptURL,
      data: Data("WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nObserved empty".utf8)
    )

    try await Container.shared.refreshManager().refreshSeries(podcast: series.podcast)

    let stored = try #require(
      try await Container.shared.repo().episode(existingEpisode.id)
    )
    #expect(!stored.hasTranscript)
    #expect(stored.publisherTranscriptReferences.map(\.url) == [transcriptURL])
    #expect(stored.publisherTranscriptSource == nil)
    #expect(await transcriptSession.requests.isEmpty)
  }

  @Test("first post-migration refresh records legacy references without importing the backlog")
  func legacyReferenceBackfillDoesNotImportBacklog() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/legacy-reference-feed.rss")!)
    let legacyTranscriptURL = URL(string: "https://example.com/legacy.vtt")!
    let newTranscriptURL = URL(string: "https://example.com/new.vtt")!
    let series = try await Self.insertInitialSeries(
      feedURL: feedURL,
      alwaysTranscribeNewEpisodes: false
    )
    let legacyEpisode = try #require(series.episodes.first)
    try await Container.shared.appDB().writer
      .write { db in
        try db.execute(
          sql: """
            UPDATE episode
            SET publisherTranscriptReferencesJSON = NULL
            WHERE id = ?
            """,
          arguments: [legacyEpisode.id]
        )
      }

    await feedSession.respond(
      to: feedURL.rawValue,
      data: Self.feedData(
        feedURL: feedURL,
        newEpisodeTranscripts: """
          <podcast:transcript url="\(newTranscriptURL.absoluteString)" type="text/vtt" language="en" />
          """,
        existingEpisodeTranscripts: """
          <podcast:transcript url="\(legacyTranscriptURL.absoluteString)" type="text/vtt" language="en" />
          """
      )
    )
    await transcriptSession.respond(
      to: legacyTranscriptURL,
      data: Data("WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nLegacy".utf8)
    )
    await transcriptSession.respond(
      to: newTranscriptURL,
      data: Data("WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nNew".utf8)
    )

    try await Container.shared.refreshManager().refreshSeries(podcast: series.podcast)

    let refreshed = try #require(
      try await Container.shared.repo().podcastSeries(series.id)
    )
    let storedLegacyEpisode = try #require(
      refreshed.episodes.first { $0.id == legacyEpisode.id }
    )
    let storedNewEpisode = try #require(
      refreshed.episodes.first { $0.guid == GUID("publisher-new") }
    )
    #expect(!storedLegacyEpisode.hasTranscript)
    #expect(storedLegacyEpisode.publisherTranscriptReferences.map(\.url) == [legacyTranscriptURL])
    #expect(storedNewEpisode.decodedTranscript?.segments.map(\.text) == ["New"])
    let requests = await transcriptSession.requests
    #expect(!requests.contains(legacyTranscriptURL))
    #expect(requests.filter { $0 == newTranscriptURL }.count == 1)
  }

  private static func feedData(feedURL: FeedURL, transcriptURL: URL?) -> Data {
    let transcripts: String?
    if let transcriptURL {
      transcripts =
        """
        <podcast:transcript url="\(transcriptURL.absoluteString)" type="text/vtt" language="en" />
        """
    } else {
      transcripts = nil
    }
    return feedData(feedURL: feedURL, newEpisodeTranscripts: transcripts)
  }

  private static func feedData(
    feedURL: FeedURL,
    newEpisodeTranscripts: String? = nil,
    existingEpisodeTranscripts: String = ""
  ) -> Data {
    let newEpisode: String
    if let newEpisodeTranscripts {
      newEpisode =
        """
          <item>
            <title>Publisher New</title>
            <guid>publisher-new</guid>
            <pubDate>Thu, 30 Jul 2026 12:00:00 +0000</pubDate>
            <enclosure url="https://example.com/publisher-new.mp3" type="audio/mpeg" />
            \(newEpisodeTranscripts)
          </item>
        """
    } else {
      newEpisode = ""
    }

    return Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss xmlns:atom="http://www.w3.org/2005/Atom"
           xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
           xmlns:podcast="https://podcastindex.org/namespace/1.0"
           version="2.0">
        <channel>
          <title>Publisher Feed</title>
          <description>Publisher transcript test feed</description>
          <link>https://example.com/publisher</link>
          <atom:link href="\(feedURL.absoluteString)" rel="self" type="application/rss+xml" />
          <itunes:image href="https://example.com/publisher.jpg" />
          \(newEpisode)
          <item>
            <title>Existing</title>
            <guid>publisher-existing</guid>
            <pubDate>Wed, 29 Jul 2026 12:00:00 +0000</pubDate>
            <enclosure url="https://example.com/publisher-existing.mp3" type="audio/mpeg" />
            \(existingEpisodeTranscripts)
          </item>
        </channel>
      </rss>
      """
      .utf8
    )
  }

  private static func insertInitialSeries(
    feedURL: FeedURL,
    alwaysTranscribeNewEpisodes: Bool,
    notifyNewEpisodes: Bool = false,
    subscriptionDate: Date? = nil
  ) async throws -> PodcastSeries {
    let feed = try await PodcastFeed.parse(
      feedData(feedURL: feedURL, transcriptURL: nil),
      from: feedURL
    )
    let podcast = try feed.toUnsavedPodcast()
    return try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try UnsavedPodcast(
            feedURL: podcast.feedURL,
            title: podcast.title,
            image: podcast.image,
            description: podcast.description,
            link: podcast.link,
            subscriptionDate: subscriptionDate,
            alwaysTranscribeNewEpisodes: alwaysTranscribeNewEpisodes,
            notifyNewEpisodes: notifyNewEpisodes
          ),
          unsavedEpisodes: feed.toUnsavedEpisodes()
        )
      )
  }
}
