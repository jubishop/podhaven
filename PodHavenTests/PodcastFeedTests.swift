// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
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

  @Test("parsing the Marketplace feed")
  func parseMarketplaceFeed() async throws {
    let url = Bundle.main.url(forResource: "marketplace", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
    let unsavedPodcast = try feed.toUnsavedPodcast()
    let unsavedEpisodes = try feed.episodes.map { try $0.toUnsavedEpisode() }
    #expect(unsavedPodcast.title == "Marketplace")
    #expect(unsavedPodcast.subscribed == false)
    #expect(unsavedEpisodes.count == 50)
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

  @Test("parsing the seattle official feed with duplicate guids")
  func parseSeattleOfficialFeedWithDuplicateGuids() async throws {
    let url = Bundle.main.url(forResource: "seattle_official", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
    let episodes = feed.toEpisodeArray()
    let duplicatedEpisode = episodes[id: "178f32e0-7246-11ec-b14e-19521896ea35"]!
    #expect(Calendar.current.component(.year, from: duplicatedEpisode.pubDate) == 2024)
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
}
