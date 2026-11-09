// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of RefreshManager new episode automation tests", .container)
actor RefreshManagerNewEpisodeAutomationTests {
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue
  @DynamicInjected(\.userNotificationCenter) private var userNotificationCenter
  @DynamicInjected(\.userSettings) private var userSettings

  private var session: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }
  private var fakeRepo: FakeRepo { repo as! FakeRepo }
  private var fakeUserNotificationCenter: FakeUserNotificationCenter {
    userNotificationCenter as! FakeUserNotificationCenter
  }

  @Test("refreshSeries skips automation for a podcast unsubscribed after its snapshot")
  func refreshSeriesSkipsAutomationAfterUnsubscribe() async throws {
    await transcriptionQueue.waitUntilLoaded()
    let series = try await NewEpisodeFeed.insertSeries(
      queueAllEpisodes: .onTop,
      cacheAllEpisodes: .save,
      alwaysTranscribeNewEpisodes: true,
      notifyNewEpisodes: true
    )
    try await repo.markUnsubscribed(series.podcast.id)
    fakeUserNotificationCenter.clearAllCalls()
    await session.respond(to: series.podcast.feedURL.rawValue, data: NewEpisodeFeed.data)

    try await refreshManager.refreshSeries(podcast: series.podcast)

    let newEpisode = try await Self.insertedEpisode(in: series)
    #expect(try await PlayHelpers.queuedEpisodeIDs.isEmpty)
    #expect(fakeUserNotificationCenter.addedRequests.isEmpty)
    #expect(!newEpisode.saveInCache)
    #expect(!newEpisode.downloading)
    #expect(transcriptionQueue.episodeIDs.isEmpty)
  }

  @Test("a back-catalog dump queues on top and announces only episodes newer than stored ones")
  func backCatalogDumpAutomatesOnlyNewerEpisodes() async throws {
    userSettings.$maxQueueLength.new(5)
    let other = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: try (0..<3).map { try Create.unsavedEpisode(title: "other \($0)") }
      )
    )
    let otherEpisodeIDs = other.episodes.map(\.id)
    try await queue.append(otherEpisodeIDs)

    let feedURL = FeedURL(URL(string: "https://example.com/back-catalog.rss")!)
    let stored = Item(guid: "stored", daysAgo: 7)
    let storedFeed = try await PodcastFeed.parse(Self.feed([stored]), from: feedURL)
    let basePodcast = try storedFeed.toUnsavedPodcast()
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: basePodcast.feedURL,
          title: basePodcast.title,
          image: basePodcast.image,
          description: basePodcast.description,
          subscriptionDate: Date(),
          queueAllEpisodes: .onTop,
          notifyNewEpisodes: true
        ),
        unsavedEpisodes: storedFeed.toUnsavedEpisodes()
      )
    )
    let fresh = Item(guid: "fresh", daysAgo: 1)
    let backCatalog = (0..<10).map { Item(guid: "back-\($0)", daysAgo: 30 + $0) }
    fakeUserNotificationCenter.clearAllCalls()
    await session.respond(
      to: feedURL.rawValue,
      data: Self.feed([fresh, stored] + backCatalog)
    )

    try await refreshManager.refreshSeries(podcast: series.podcast)

    let refreshed = try #require(try await repo.podcastSeries(series.id))
    #expect(refreshed.episodes.count == 12)
    let freshEpisode = try #require(refreshed.episodes.first { $0.guid == GUID(fresh.guid) })
    #expect(try await PlayHelpers.queuedEpisodeIDs == [freshEpisode.id] + otherEpisodeIDs)
    #expect(fakeUserNotificationCenter.addedRequests.count == 1)
    #expect(fakeUserNotificationCenter.addedRequests.first?.body == freshEpisode.title)
  }

  @Test("refreshSeries saves and caches new episodes when cancelled right after the feed write")
  func refreshSeriesSavesNewEpisodesAfterCancellation() async throws {
    let series = try await NewEpisodeFeed.insertSeries(cacheAllEpisodes: .save)
    await session.respond(to: series.podcast.feedURL.rawValue, data: NewEpisodeFeed.data)
    fakeRepo.pendingSeriesFeedUpdateAfterWriteSuspend(true)

    let refreshManager = refreshManager
    let refreshTask = Task {
      try await refreshManager.refreshSeries(podcast: series.podcast)
    }
    try await fakeRepo.waitForSeriesFeedUpdateAfterWriteSuspended()
    refreshTask.cancel()
    await fakeRepo.resumeAllSeriesFeedUpdateAfterWriteSuspensions()
    try await refreshTask.value

    let newEpisode = try await Self.insertedEpisode(in: series)
    #expect(newEpisode.saveInCache)
    try await CacheHelpers.waitForDownloading(newEpisode.id)
  }

  // MARK: - Helpers

  private struct Item {
    let guid: String
    let daysAgo: Int

    var pubDate: Date {
      Date(timeIntervalSince1970: 1_767_268_800).addingTimeInterval(-daysAgo.days.asTimeInterval)
    }
  }

  private static func insertedEpisode(in series: PodcastSeries) async throws -> Episode {
    let storedEpisodeIDs = Set(series.episodes.map(\.id))
    let refreshed = try #require(
      try await Container.shared.repo().podcastSeries(series.podcast.id)
    )
    let inserted = refreshed.episodes.filter { !storedEpisodeIDs.contains($0.id) }
    #expect(inserted.count == 1)
    return try #require(inserted.first)
  }

  private static func feed(_ items: [Item]) -> Data {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
    let itemXML = items.map { item in
      """
      <item>
        <title>Episode \(item.guid)</title>
        <guid>\(item.guid)</guid>
        <pubDate>\(formatter.string(from: item.pubDate))</pubDate>
        <enclosure url="https://example.com/\(item.guid).mp3" type="audio/mpeg" />
      </item>
      """
    }
    return Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>Back Catalog</title>
          <description>Back catalog test feed</description>
          <itunes:image href="https://example.com/back-catalog.jpg" />
          \(itemXML.joined(separator: "\n"))
        </channel>
      </rss>
      """
      .utf8
    )
  }
}
