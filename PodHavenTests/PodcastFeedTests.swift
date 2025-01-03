// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastFeed tests")
actor PodcastFeedTests {
  @Test("parsing the Pod Save America feed")
  func parsePodSaveAmericaFeed() async throws {
    let url = Bundle.main.url(forResource: "pod_save_america", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(url)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(unsavedPodcast.title == "Pod Save America")
    #expect(unsavedPodcast.link == URL(string: "https://crooked.com"))
    #expect(unsavedPodcast.image.absoluteString.contains("simplecastcdn") != nil)
    let unsavedEpisode = try feed.episodes.first!.toUnsavedEpisode()
    #expect(unsavedEpisode.duration == CMTime.inSeconds(2643))
  }

  @Test("parsing the Marketplace feed")
  func parseMarketplaceFeed() async throws {
    let url = Bundle.main.url(forResource: "marketplace", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(url)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(unsavedPodcast.title == "Marketplace")
  }

  @Test("parsing the Land of the Giants")
  func parseLandOfTheGiantsFeed() async throws {
    let url = Bundle.main.url(forResource: "land_of_the_giants", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(url)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(unsavedPodcast.title == "Land of the Giants")
  }

  @Test("parsing the invalid Game Informer feed")
  func parseInvalidGameInformerFeed() async {
    let url = Bundle.main.url(forResource: "game_informer_invalid", withExtension: "rss")!
    await #expect(throws: (any Error).self) {
      try await PodcastFeed.parse(url)
    }
  }
}
