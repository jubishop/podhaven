// Copyright Justin Bishop, 2025

import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of ApplePodcasts tests", .container)
struct ApplePodcastsTests {
  @Test("that podcast URLs are correctly identified")
  func podcastURLsCorrectlyIdentified() async throws {
    #expect(
      ApplePodcasts.isApplePodcastsURL(
        URL(string: "https://podcasts.apple.com/us/podcast/the-daily-show/id143233")!
      )
    )
    #expect(
      ApplePodcasts.isApplePodcastsURL(
        URL(string: "podcasts://podcasts.apple.com/us/podcast/the-daily-show/id143233")!
      )
    )
    #expect(
      !ApplePodcasts.isApplePodcastsURL(
        URL(string: "https://open.spotify.com/show/44fllCS2FTFr2x2kjP9xeT")!
      )
    )
  }
}
