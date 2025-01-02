// Copyright Justin Bishop, 2024

import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastFeed tests")
actor PodcastFeedTests {
  @Test("parsing the Pod Save America feed")
  func parsePodSaveAmericaFeed() async throws {
    let url = Bundle.main.url(forResource: "pod_save_america", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(url)
    let unsavedPodcast = feed.toUnsavedPodcast(feedURL: URL.valid())
    #expect(unsavedPodcast?.title == "Pod Save America")
    #expect(unsavedPodcast?.link == URL(string: "https://crooked.com"))
    #expect(unsavedPodcast?.image?.absoluteString.contains("simplecastcdn") != nil)
    // TODO: Test Duration
  }

  @Test("parsing the invalid Game Informer feed")
  func parseInvalidGameInformerFeed() async {
    let url = Bundle.main.url(forResource: "game_informer_invalid", withExtension: "rss")!
    await #expect(throws: (any Error).self) {
      try await PodcastFeed.parse(url)
    }
  }

  @Test("parsing the Land of the Giants")
  func parseLandOfTheGiantsFeed() async throws {
    let url = Bundle.main.url(forResource: "land_of_the_giants", withExtension: "rss")!
    let feed = try await PodcastFeed.parse(url)
    let unsavedPodcast = feed.toUnsavedPodcast(feedURL: URL.valid())
    #expect(unsavedPodcast?.title == "Land of the Giants")
  }
}
