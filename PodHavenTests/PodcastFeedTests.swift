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
    let feed = await PodcastFeed.parse(url)
    switch feed {
    case .success(let feed):
      #expect(feed.title == "Pod Save America")
      #expect(
        try #require(feed.link) == URL(string: "https://crooked.com")
      )
      #expect(
        try #require(feed.image)
          == URL(
            string:
              "https://image.simplecastcdn.com/images/9aa1e238-cbed-4305-9808-c9228fc6dd4f/eb7dddd4-ecb0-444c-b379-f75d7dc6c22b/3000x3000/uploads-2f1595947484360-nc4atf9w7ur-dbbaa7ee07a1ee325ec48d2e666ac261-2fpodsave100daysfinal1800.jpg?aid=rss_feed"
          )
      )
    case .failure(let error):
      Issue.record("Failed to parse \(url): \"\(error)\"")
    }
  }

  @Test("parsing the invalid Game Informer feed")
  func parseInvalidGameInformerFeed() async {
    let url = Bundle.main.url(
      forResource: "game_informer",
      withExtension: "rss"
    )!
    let feed = await PodcastFeed.parse(url)
    if case .success = feed {
      Issue.record("Game Informer should be unparseable")
    }
  }

  @Test("parsing the Land of the Giants")
  func parseLandOfTheGiantsFeed() async throws {
    let url = Bundle.main.url(
      forResource: "land_of_the_giants",
      withExtension: "rss"
    )!
    let feed = await PodcastFeed.parse(url)
    switch feed {
      case .success(let feed):
        #expect(feed.title == "Land of the Giants")
      case .failure(let error):
        Issue.record("Failed to parse \(url): \"\(error)\"")
    }
  }

}
