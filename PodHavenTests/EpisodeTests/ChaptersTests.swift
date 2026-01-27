// Copyright Justin Bishop, 2026

import AVFoundation
import Testing

@testable import PodHaven

@Suite("Episode chapters tests", .container)
struct EpisodeChaptersTests {
  @Test("returns nil when description is nil")
  func nilDescription() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(3600),
      description: nil
    )
    #expect(episode.chapters == nil)
  }

  @Test("returns nil when description has no timestamps")
  func noTimestamps() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(3600),
      description: "This episode has no chapter markers at all."
    )
    #expect(episode.chapters == nil)
  }

  @Test("returns nil when all timestamps are zero")
  func allZeroTimestamps() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(3600),
      description: "0:00 Intro\n00:00 Start\n0:00:00 Beginning"
    )
    #expect(episode.chapters == nil)
  }

  @Test("parses simple minute:second timestamps")
  func simpleTimestamps() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(3600),
      description: """
        0:00 Intro
        2:15 Topic One
        14:30 Topic Two
        45:00 Topic Three
        """
    )
    #expect(
      episode.chapters == [
        .seconds(135),
        .seconds(870),
        .seconds(2700),
      ]
    )
  }

  @Test("parses hour:minute:second timestamps")
  func hourTimestamps() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(7200),
      description: """
        0:00:00 Intro
        0:15:30 First topic
        1:02:15 Second topic
        1:45:00 Wrap up
        """
    )
    #expect(
      episode.chapters == [
        .seconds(930),
        .seconds(3735),
        .seconds(6300),
      ]
    )
  }

  @Test("filters timestamps exceeding duration")
  func filtersExceedingDuration() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(600),
      description: """
        1:00 Topic One
        5:00 Topic Two
        15:00 This exceeds 10 minute duration
        1:00:00 Way too long
        """
    )
    #expect(
      episode.chapters == [
        .seconds(60),
        .seconds(300),
      ]
    )
  }

  @Test("returns nil when duration is zero")
  func zeroDuration() throws {
    let episode = try Create.unsavedEpisode(
      description: """
        1:00 Topic One
        30:00 Topic Two
        1:30:00 Topic Three
        """
    )
    #expect(episode.chapters == nil)
  }

  @Test("ignores timestamps preceded by digits")
  func ignoresDigitPrefixedTimestamps() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(3600),
      description: """
        episode123:45 is not a timestamp
        Check out 5:30 for the good stuff
        Version 3.2.1 is great
        """
    )
    #expect(episode.chapters == [.seconds(330)])
  }

  @Test("deduplicates identical timestamps")
  func deduplicates() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(3600),
      description: """
        5:00 Topic mentioned here
        10:00 Another topic
        5:00 Topic mentioned again
        """
    )
    #expect(
      episode.chapters == [
        .seconds(300),
        .seconds(600),
      ]
    )
  }

  @Test("sorts timestamps chronologically")
  func sortsChronologically() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(3600),
      description: """
        45:00 Listed last but appears first
        2:00 Early
        30:00 Middle
        """
    )
    #expect(
      episode.chapters == [
        .seconds(120),
        .seconds(1800),
        .seconds(2700),
      ]
    )
  }

  @Test("handles single-digit minutes without hours")
  func singleDigitMinutes() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(600),
      description: "1:30 Quick topic\n9:59 Last topic"
    )
    #expect(
      episode.chapters == [
        .seconds(90),
        .seconds(599),
      ]
    )
  }

  @Test("handles single-digit hours")
  func singleDigitHours() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(36000),
      description: "1:00:00 Hour one\n2:30:00 Two and a half hours"
    )
    #expect(
      episode.chapters == [
        .seconds(3600),
        .seconds(9000),
      ]
    )
  }

  @Test("handles two-digit hours")
  func twoDigitHours() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(50000),
      description: "10:15:30 Topic one\n12:00:00 Topic two"
    )
    #expect(
      episode.chapters == [
        .seconds(36930),
        .seconds(43200),
      ]
    )
  }

  @Test("does not match three-digit prefix as valid timestamp")
  func rejectsThreeDigitPrefix() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(3600),
      description: "123:45 is not valid\n5:00 is valid"
    )
    #expect(episode.chapters == [.seconds(300)])
  }

  @Test("does not match single-digit seconds")
  func rejectsSingleDigitSeconds() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(3600),
      description: "5:3 is not valid\n5:30 is valid"
    )
    #expect(episode.chapters == [.seconds(330)])
  }

  @Test("timestamp at exact duration is included")
  func exactDuration() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(300),
      description: "1:00 One minute\n5:00 Exactly at duration"
    )
    #expect(
      episode.chapters == [
        .seconds(60),
        .seconds(300),
      ]
    )
  }

  @Test("does not match timestamps followed by more digits")
  func rejectsTimestampsFollowedByDigits() throws {
    let episode = try Create.unsavedEpisode(
      duration: .seconds(3600),
      description: "5:300 not valid\n10:00 valid"
    )
    #expect(episode.chapters == [.seconds(600)])
  }
}
