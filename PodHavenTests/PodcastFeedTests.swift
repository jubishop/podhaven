// Copyright Justin Bishop, 2024

import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastFeed tests")
actor PodcastFeedTests {
  @Test("parsing the Pod Save America feed")
  func parsePodSaveAmericaFeed() async throws {
    let url = Bundle.main.url(
      forResource: "pod_save_america",
      withExtension: "rss"
    )!
    let parseResult = await PodcastFeed.parse(url)
    let feed = parseResult.isSuccessfulWith()
    let unsavedPodcast = feed?.toUnsavedPodcast(oldFeedURL: URL.valid(), oldTitle: "OldTitle")
    #expect(unsavedPodcast?.title == "Pod Save America")
    #expect(unsavedPodcast?.link == URL(string: "https://crooked.com"))
    #expect(unsavedPodcast?.image?.absoluteString.contains("simplecastcdn") != nil)
  }

  @Test("parsing the invalid Game Informer feed")
  func parseInvalidGameInformerFeed() async {
    let url = Bundle.main.url(
      forResource: "game_informer",
      withExtension: "rss"
    )!
    let parseResult = await PodcastFeed.parse(url)
    #expect(parseResult.isUnparseable)
  }

  @Test("parsing the Land of the Giants")
  func parseLandOfTheGiantsFeed() async throws {
    let url = Bundle.main.url(
      forResource: "land_of_the_giants",
      withExtension: "rss"
    )!
    let parseResult = await PodcastFeed.parse(url)
    let feed = parseResult.isSuccessfulWith()
    #expect(feed?.title == "Land of the Giants")
  }
}
