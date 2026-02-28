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
    #expect(episode.chapters == [.seconds(300), .seconds(1425)])
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

  // MARK: - Timestamp Newline Insertion

  @Test("inserts newlines before timestamps that are missing them")
  func timestampNewlines() throws {
    let episode = try Create.unsavedEpisode(
      description: "Chapters:00:00 Intro00:40 Topic01:07 Deep Dive"
    )
    let result = try #require(episode.descriptionWithNewlines)
    let lines = result.components(separatedBy: "\n").filter { !$0.isEmpty }
    #expect(lines.count == 4)
    #expect(lines[0] == "Chapters:")
    #expect(lines[1] == "00:00 Intro")
    #expect(lines[2] == "00:40 Topic")
    #expect(lines[3] == "01:07 Deep Dive")
  }

  @Test("does not duplicate newlines before timestamps that already have them")
  func timestampNewlinesNoDuplication() throws {
    let episode = try Create.unsavedEpisode(
      description: "Chapters:\n00:00 Intro\n00:40 Topic"
    )
    let result = try #require(episode.descriptionWithNewlines)
    let lines = result.components(separatedBy: "\n").filter { !$0.isEmpty }
    #expect(lines.count == 3)
    #expect(lines[0] == "Chapters:")
    #expect(lines[1] == "00:00 Intro")
    #expect(lines[2] == "00:40 Topic")
  }

  @Test("handles both MM:SS and HH:MM:SS formats")
  func timestampNewlinesFormats() throws {
    let episode = try Create.unsavedEpisode(
      description: "00:00 Start01:30 Middle05:45:30 Long Format10:00 End"
    )
    let result = try #require(episode.descriptionWithNewlines)
    #expect(result.contains("\n01:30 Middle"))
    #expect(result.contains("\n05:45:30 Long"))
    #expect(result.contains("\n10:00 End"))
  }

  @Test("does not start with a blank line when timestamp is at position zero")
  func timestampNewlinesAtStart() throws {
    let episode = try Create.unsavedEpisode(
      description: "00:00 Intro01:00 Next"
    )
    let result = try #require(episode.descriptionWithNewlines)
    #expect(!result.hasPrefix("\n"))
    #expect(result.hasPrefix("00:00 Intro"))
    #expect(result.contains("\n01:00 Next"))
  }

  @Test("does not match partial timestamps preceded by digits")
  func timestampNewlinesNoPartialMatch() throws {
    let episode = try Create.unsavedEpisode(
      description: "Code 123:45 appeared"
    )
    let result = try #require(episode.descriptionWithNewlines)
    #expect(!result.contains("\n23:45"))
    #expect(!result.contains("\n3:45"))
  }

  @Test("handles mixed content where some timestamps have newlines and some do not")
  func timestampNewlinesMixed() throws {
    let episode = try Create.unsavedEpisode(
      description: "00:00 Intro\n01:00 Topic A02:00 Topic B\n03:00 Wrap Up"
    )
    let result = try #require(episode.descriptionWithNewlines)
    let lines = result.components(separatedBy: "\n").filter { !$0.isEmpty }
    #expect(lines.count == 4)
    #expect(lines[0] == "00:00 Intro")
    #expect(lines[1] == "01:00 Topic A")
    #expect(lines[2] == "02:00 Topic B")
    #expect(lines[3] == "03:00 Wrap Up")
  }

  @Test("returns nil when description is nil")
  func timestampNewlinesNilDescription() throws {
    let episode = try Create.unsavedEpisode(description: nil)
    #expect(episode.descriptionWithNewlines == nil)
  }
}
