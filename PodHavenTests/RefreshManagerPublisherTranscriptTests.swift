// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
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

  @Test("new publisher transcript imports before automatic on-device queueing")
  func importsNewPublisherTranscriptBeforeAutomaticQueueing() async throws {
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

  @Test("failed timed candidates leave the episode eligible and are not retried each refresh")
  func failedCandidatesDoNotFailOrRefetch() async throws {
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

    try await refreshManager.refreshSeries(podcast: series.podcast)
    try await refreshManager.refreshSeries(podcast: series.podcast)

    let refreshed = try #require(
      try await Container.shared.repo().podcastSeries(series.id)
    )
    let episode = try #require(
      refreshed.episodes.first { $0.guid == GUID("publisher-new") }
    )
    #expect(!episode.hasTranscript)
    #expect(queue.episodeIDs == [episode.id])
    #expect(await transcriptSession.requests.filter { $0 == jsonURL }.count == 1)
    #expect(await transcriptSession.requests.filter { $0 == webVTTURL }.count == 1)
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

  @Test("a new reference imports after an observed empty reference set")
  func importsReferenceAfterKnownEmpty() async throws {
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
    #expect(stored.decodedTranscript?.segments.map(\.text) == ["Observed empty"])
    #expect(stored.publisherTranscriptSource?.url == transcriptURL)
    #expect(await transcriptSession.requests == [transcriptURL])
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
    alwaysTranscribeNewEpisodes: Bool
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
            alwaysTranscribeNewEpisodes: alwaysTranscribeNewEpisodes
          ),
          unsavedEpisodes: feed.toUnsavedEpisodes()
        )
      )
  }
}
