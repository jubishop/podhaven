// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of ShareURL tests")
struct ShareURLTests {
  @Test("that episode URL includes startTime query parameter")
  func episodeURLWithStartTime() {
    let feedURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let guid = GUID("episode-123")

    let url = ShareURL.episode(feedURL: feedURL, guid: guid, startTime: 90)

    let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)!
    let startTimeItem = components.queryItems?.first { $0.name == "startTime" }
    #expect(startTimeItem?.value == "90")
  }

  @Test("that episode URL without startTime omits query parameter")
  func episodeURLWithoutStartTime() {
    let feedURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let guid = GUID("episode-123")

    let url = ShareURL.episode(feedURL: feedURL, guid: guid)

    let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)!
    let startTimeItem = components.queryItems?.first { $0.name == "startTime" }
    #expect(startTimeItem == nil)
  }
}
