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
        URL(string: "https://podcasts.apple.com/us/podcast/podcast-name/id1234567890")!
      )
    )
    #expect(
      ApplePodcasts.isApplePodcastsURL(
        URL(string: "podcasts://podcasts.apple.com/us/podcast/id1234567890")!
      )
    )
    #expect(
      !ApplePodcasts.isApplePodcastsURL(
        URL(string: "https://open.spotify.com/show/44fllCS2FTFr2x2kjP9xeT")!
      )
    )
  }

  @Test("that iTunes IDs are successfully extracted from URLs")
  func iTunesIDsSuccessfullyExtractedFromURLs() async throws {
    #expect(
      try ApplePodcasts.extractITunesID(
        from: URL(string: "https://podcasts.apple.com/us/podcast/podcast-name/id1234567890")!
      ) == "1234567890"
    )
  }
}
