// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of PodcastFeed tests")
struct PodcastFeedTests {
  @Test("parsing the Pod Save America feed")
  func parsePodSaveAmericaFeed() async throws {
    let url = Bundle.main.url(forResource: "pod_save_america", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(unsavedPodcast.title == "Pod Save America")
    #expect(unsavedPodcast.link == URL(string: "https://crooked.com"))
    #expect(unsavedPodcast.image.absoluteString.contains("simplecastcdn"))
    let unsavedEpisode = try feed.episodes.first!.toUnsavedEpisode()
    #expect(unsavedEpisode.duration == CMTime.inSeconds(2643))
  }

  @Test("parsing the Marketplace feed with an invalid MediaURL")
  func parseMarketplaceFeedWithInvalidMediaURL() async throws {
    let url = Bundle.main.url(forResource: "marketplace", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(URL.valid()))
    let unsavedPodcast = try feed.toUnsavedPodcast()
    let unsavedEpisodes = try feed.episodes.map { try $0.toUnsavedEpisode() }
    #expect(unsavedPodcast.title == "Marketplace")
    #expect(unsavedPodcast.subscribed == false)

    // title: "What will a GOP-ruled Congress do with Trump" is removed for invalid MediaURL
    #expect(unsavedEpisodes.count == 49)
    #expect(unsavedEpisodes.first!.title == "Happy New Year! The cold weather could cost you.")
    #expect(unsavedEpisodes.last!.title == "What’s better, a pension or a 401(k)?")
  }

  @Test("parsing the Land of the Giants")
  func parseLandOfTheGiantsFeed() async throws {
    let url = Bundle.main.url(forResource: "land_of_the_giants", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
    let unsavedPodcast = try feed.toUnsavedPodcast(subscribed: true)
    let unsavedEpisodes = try feed.episodes.map { try $0.toUnsavedEpisode() }
    #expect(unsavedPodcast.title == "Land of the Giants")
    #expect(unsavedPodcast.subscribed == true)
    #expect(unsavedEpisodes.count == 71)
    #expect(unsavedEpisodes.first!.title == "Disney is a Tech Company?")
    #expect(unsavedEpisodes.last!.title == "The Rise of Amazon")
  }

  @Test("parsing the invalid Game Informer feed")
  func parseInvalidGameInformerFeed() async throws {
    let url = Bundle.main.url(forResource: "game_informer_invalid", withExtension: "rss")!
    await #expect {
      try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
    } throws: { error in
      guard let error = error as? FeedError
      else { return false }

      if case .parseFailure(let thrownURL, _) = error {
        return thrownURL.rawValue == url
      }

      return false
    }
  }

  // This is invalid behavior by a feed but sadly dumb dumbs still do it.
  @Test("parsing the seattle official feed with duplicate guids")
  func parseSeattleOfficialFeedWithDuplicateGuids() async throws {
    let url = Bundle.main.url(forResource: "seattle_official", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
    let episodes = feed.toEpisodeArray()
    let duplicatedEpisode = episodes[id: "178f32e0-7246-11ec-b14e-19521896ea35"]!
    #expect(Calendar.current.component(.year, from: duplicatedEpisode.pubDate) == 2024)
  }

  @Test("parsing the morningbrew feed with duplicate mediaURLs")
  func parseMorningBrewFeedWithDuplicateMediaURLs() async throws {
    let url = Bundle.main.url(forResource: "morningbrew", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))

    let episodes = feed.toEpisodeArray()
    let mediaURLs: [MediaURL: Int] = episodes.reduce(into: [:]) { counts, episode in
      counts[episode.media, default: 0] += 1
    }
    for (mediaURL, count) in mediaURLs where count > 1 {
      Issue.record("Duplicate media url found: \(mediaURL) with count: \(count)")
    }

    let episodesByMediaURL = IdentifiedArray(uniqueElements: episodes, id: \.media)
    let duplicatedEpisode = episodesByMediaURL[
      id: MediaURL(
        URL(
          string:
            "https://www.podtrac.com/pts/redirect.mp3/pdst.fm/e/tracking.swap.fm/track/bHsDpvy53mYwJpnc1UL5/traffic.megaphone.fm/MOBI2606610581.mp3?updated=1750937895"
        )!
      )
    ]!
    #expect(Calendar.current.component(.year, from: duplicatedEpisode.pubDate) == 2026)
  }

  @Test("parsing the seattlenow feed with a <p> tagged description")
  func parseSeattleNowFeedWithPTagInDescription() async throws {
    let url = Bundle.main.url(forResource: "seattlenow", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(
      unsavedPodcast.description
        == "<p>A daily news podcast for a curious city. Seattle Now brings you quick, informal, and hyper-local news updates every weekday.</p>"
    )
  }

  @Test("parsing the makingsense feed with items missing media urls")
  func parseMakingSenseFeedWithMissingMediaUrls() async throws {
    let url = Bundle.main.url(forResource: "makingsense", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
    let episodes = feed.toEpisodeArray()

    // 19 episodes exist in the RSS file,
    // but the last two are dropped because they have no media URLs
    #expect(episodes.count == 17)
  }

  @Test("parsing the considerthis feed with items missing guids")
  func parseConsiderThisFeedWithMissingGuids() async throws {
    let url = Bundle.main.url(forResource: "considerthis", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(URL.valid()))
    let episodes = feed.toEpisodeArray()

    // These are the mediaURLs of the two entries with no guids
    #expect(
      episodes.ids.contains(
        GUID(
          "https://chrt.fm/track/138C95/prfx.byspotify.com/e/play.podtrac.com/npr-510355/traffic.megaphone.fm/NPR8510690925.mp3?d=736&size=11791509&e=1254697878&t=podcast&p=510355"
        )
      )
    )
    #expect(
      episodes.ids.contains(
        GUID(
          "https://chrt.fm/track/138C95/prfx.byspotify.com/e/play.podtrac.com/npr-510355/traffic.megaphone.fm/NPR7873235626.mp3?d=489&size=7834271&e=1254264642&t=podcast&p=510355"
        )
      )
    )
  }

  @Test("parsing with invalid feedURL throws error")
  func parseWithInvalidFeedURL() async throws {
    let url = Bundle.main.url(forResource: "considerthis", withExtension: "rss")!

    await #expect(throws: FeedError.self) {
      try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
    }
  }
}
