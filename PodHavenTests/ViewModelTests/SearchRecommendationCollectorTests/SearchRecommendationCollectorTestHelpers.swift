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

  // Three orthogonal signal vectors give the centroid a measurable
  // direction. Candidate text defaults to Signal-0 (above the 0.5 floor);
  // "Below Floor" text is explicitly anti-aligned.
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
    // Default test container already cached a ContextualEmbedding around
    // FakeEmbeddable, so replace the resolved instance not just the
    // underlying nlContextualEmbedding.
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: embeddable) }
      .scope(.cached)

    // Whitening on 3 signal episodes / dim-3 vectors produces NaN principal
    // components; Focused mode skips PCA entirely.
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
    // "Pick" so candidate titles don't collide with the scripted
    // embeddable's per-signal-episode rules.
    let eps = (0..<episodes)
      .map { i in
        (
          "ep-\(i)-\(feedURL.absoluteString.hashValue)",
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

// Test convenience mirroring the active-source picks. Production reads
// `picks(for:)` and `bannerState` directly, so this lives in the test target.
extension SearchRecommendationCollector {
  var visiblePicks: [ScoredEpisode] {
    guard let activeSource else { return [] }
    return picks(for: activeSource)
  }
}
