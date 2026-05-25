// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

enum SearchRecommendationCollectorTestHelpers {
  static var session: FakeDataFetchable {
    Container.shared.podcastFeedSession() as! FakeDataFetchable
  }
  static var fakeSleeper: FakeSleeper {
    Container.shared.sleeper() as! FakeSleeper
  }

  static func makeUnsavedRow(
    feedURL: FeedURL,
    iTunesID: ITunesPodcastID
  ) -> PodcastWithEpisodeMetadata<ListedPodcast> {
    let unsaved = try! Create.unsavedPodcast(
      feedURL: feedURL,
      iTunesID: iTunesID,
      title: "Discovery Source",
      description: "Discovery Source"
    )
    return PodcastWithEpisodeMetadata(
      podcast: ListedPodcast(unsavedSearchResult: unsaved),
      episodeCount: 1,
      mostRecentEpisodeDate: Date()
    )
  }

  // Signal episodes get three orthogonal vectors so the whitening transform
  // produces a non-degenerate centroid pointing in a measurable direction.
  // Discovery / candidate text defaults to the Signal-0 direction so its
  // similarity lands comfortably above the 0.5 floor; "Below Floor" text is
  // explicitly anti-aligned.
  static func makeScriptedEmbeddable() -> ScriptedEmbeddable {
    ScriptedEmbeddable { text in
      if text.contains("Below Floor") { return [-1, 0, 0] }
      if text.contains("of Signal") {
        if text.contains("Episode 0") { return [1, 0, 0] }
        if text.contains("Episode 1") { return [0, 1, 0] }
        return [0, 0, 1]
      }
      return [1, 0, 0]
    }
  }

  static func primeEngine(embeddable: ScriptedEmbeddable) async throws {
    // Reset + register: the default test container already cached a
    // ContextualEmbedding around FakeEmbeddable, so we have to replace the
    // resolved instance, not just the underlying nlContextualEmbedding.
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: embeddable) }
      .scope(.cached)

    // Whitening on tiny corpora (3 signal episodes, dim-3 vectors) produces
    // nan principal components and breaks similarity scoring. The Focused
    // mode skips the PCA strip entirely.
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    let localEngine = Container.shared.recommendationEngine()
    localEngine.start()
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in localEngine.hasScoringContext },
      { @Sendable in "Expected scoring context to land" }
    )
  }

  static func respondWithFeed(at feedURL: FeedURL, title: String, episodes: Int) async {
    let eps = (0..<episodes)
      .map { i in
        (
          "ep-\(i)-\(feedURL.absoluteString.hashValue)",
          // Use "Pick" so candidate titles don't collide with the scripted
          // embeddable's per-signal-episode rules.
          "\(title) Pick \(i)",
          Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(i * 86_400))
        )
      }
    await session.respond(
      to: feedURL.rawValue,
      data: rssXML(title: title, feedURL: feedURL, episodes: eps)
    )
  }

  static func advanceStableSourceDebounce() async throws {
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: SearchRecommendationCollector.stableSourceDebounce)
  }

  static func rssXML(
    title: String,
    feedURL: FeedURL,
    episodes: [(guid: String, title: String, pubDate: Date)]
  ) -> Data {
    let pubDateFormatter = DateFormatter()
    pubDateFormatter.locale = Locale(identifier: "en_US_POSIX")
    pubDateFormatter.timeZone = TimeZone(identifier: "GMT")
    pubDateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

    let items =
      episodes.map { entry -> String in
        """
        <item>
          <guid isPermaLink="false">\(entry.guid)</guid>
          <title>\(entry.title)</title>
          <pubDate>\(pubDateFormatter.string(from: entry.pubDate))</pubDate>
          <enclosure url="https://example.com/audio/\(entry.guid).mp3" type="audio/mpeg" length="0" />
          <description>\(entry.title) description</description>
        </item>
        """
      }
      .joined(separator: "\n")

    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
        <channel>
          <title>\(title)</title>
          <link>\(feedURL.absoluteString)</link>
          <description>\(title) description</description>
          <itunes:image href="https://example.com/image.png" />
          \(items)
        </channel>
      </rss>
      """
    return Data(xml.utf8)
  }
}
