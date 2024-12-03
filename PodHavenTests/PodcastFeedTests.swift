// Copyright Justin Bishop, 2024

import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastFeed tests")
actor PodcastFeedTests {
  @Test("parsing the Pod Save America feed using URL")
  func parsePodSaveAmericaFeed() async {
    let url = Bundle.main.url(
      forResource: "pod_save_america",
      withExtension: "rss"
    )!
    let feed = await PodcastFeed.parse(url)
    switch feed {
    case .success(let feed):
      #expect(await feed.title == "Pod Save America")
      print(await feed.link!)
    case .failure(let error):
      Issue.record("Failed to parse \(url): \"\(error)\"")
    }
  }
}
