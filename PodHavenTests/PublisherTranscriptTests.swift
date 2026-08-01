// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of publisher transcript tests", .container)
struct PublisherTranscriptTests {
  @DynamicInjected(\.publisherTranscriptSession) private var publisherTranscriptSession
  @DynamicInjected(\.publisherTranscriptImporter) private var importer

  private var session: FakeDataFetchable {
    publisherTranscriptSession as! FakeDataFetchable
  }

  @Test("real Stuff You Should Know snapshot discovers every transcript reference")
  func realFeedDiscoversTranscriptReferences() async throws {
    let data = PreviewBundle.loadAsset(named: "stuff_you_should_know", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)
    let episode = try #require(
      podcast.episodes.first { $0.guid == GUID("6bd9546f-c485-4718-a348-b49501390740") }
    )

    #expect(episode.title == "How Russia Shapes What the World Thinks")
    #expect(episode.podcast.transcripts.count == 3)
    #expect(
      Set(episode.podcast.transcripts.map(\.mimeType))
        == ["application/srt", "text/vtt", "text/plain"]
    )
    #expect(episode.podcast.transcripts.allSatisfy { $0.language == "en" })
    #expect(
      episode.podcast.transcripts.contains {
        $0.url.absoluteString
          == "https://api.omny.fm/orgs/e73c998e-6e60-432f-8610-ae210140c5b1/clips/6bd9546f-c485-4718-a348-b49501390740/transcript?format=WebVTT&t=1785265456"
          && $0.mimeType == "text/vtt"
      }
    )
  }

  @Test("real referenced WebVTT preserves timing and strips voice tags")
  func realWebVTTParsesTimedVisibleText() throws {
    let data = PreviewBundle.loadAsset(
      named: "stuff_you_should_know_transcript",
      in: .FeedRSS
    )

    let segments = try PublisherTranscriptParser.parse(data, as: .webVTT)

    #expect(segments.count == 775)
    #expect(
      segments.first
        == TranscriptSegment(
          start: 1.48,
          end: 4.96,
          text: "Welcome to Stuff you should know, a production of iHeartRadio."
        )
    )
    #expect(!segments.contains { $0.text.contains("<v ") })
  }

  @Test("timed JSON is preferred and ignores speaker fields")
  func prefersTimedJSON() async throws {
    let json = reference("preferred.json", type: "application/json", language: "en-US")
    let webVTT = reference("fallback.vtt", type: "text/vtt")
    let subRip = reference("fallback.srt", type: "application/srt")
    await session.respond(
      to: json.url,
      data: Data(
        """
        {
          "version": "1.0.0",
          "segments": [
            {
              "speaker": "Host",
              "startTime": 1.25,
              "endTime": 2.75,
              "body": "JSON words"
            }
          ]
        }
        """
        .utf8
      )
    )
    await session.respond(
      to: webVTT.url,
      data: Data("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nVTT words".utf8)
    )
    await session.respond(
      to: subRip.url,
      data: Data("1\n00:00:01,000 --> 00:00:02,000\nSRT words".utf8)
    )

    let imported = try #require(
      try await importer.importTranscript(from: [subRip, webVTT, json])
    )

    #expect(imported.source == json)
    #expect(imported.transcript.locale == "en-US")
    #expect(
      imported.transcript.segments
        == [TranscriptSegment(start: 1.25, end: 2.75, text: "JSON words")]
    )
    #expect(await session.requests == [json.url])
  }

  @Test("WebVTT is preferred over SubRip")
  func prefersWebVTTOverSubRip() async throws {
    let subRip = reference("fallback.srt", type: "application/x-subrip")
    let webVTT = reference("preferred.vtt", type: "text/vtt")
    await session.respond(
      to: subRip.url,
      data: Data("1\n00:00:01,000 --> 00:00:02,000\nSRT words".utf8)
    )
    await session.respond(
      to: webVTT.url,
      data: Data(
        "WEBVTT\n\n00:00:03.000 --> 00:00:04.000\n<v Narrator>VTT words".utf8
      )
    )

    let imported = try #require(
      try await importer.importTranscript(from: [subRip, webVTT])
    )

    #expect(imported.source == webVTT)
    #expect(
      imported.transcript.segments
        == [TranscriptSegment(start: 3, end: 4, text: "VTT words")]
    )
    #expect(await session.requests == [webVTT.url])
  }

  @Test("malformed and unavailable preferred formats fall back to SubRip")
  func fallsBackThroughSupportedCandidates() async throws {
    let json = reference("malformed.json", type: "application/json")
    let webVTT = reference("unavailable.vtt", type: "text/vtt")
    let subRip = reference("working.srt", type: "application/srt", language: "en")
    await session.respond(
      to: json.url,
      data: Data(#"{"segments":[{"body":"missing times"}]}"#.utf8)
    )
    await session.respond(to: webVTT.url, error: URLError(.notConnectedToInternet))
    await session.respond(
      to: subRip.url,
      data: Data(
        """
        1
        00:00:05,250 --> 00:00:07,500
        First line
        second line
        """
        .utf8
      )
    )

    let imported = try #require(
      try await importer.importTranscript(from: [subRip, webVTT, json])
    )

    #expect(imported.source == subRip)
    #expect(
      imported.transcript.segments
        == [TranscriptSegment(start: 5.25, end: 7.5, text: "First line\nsecond line")]
    )
    #expect(await session.requests == [json.url, webVTT.url, subRip.url])
  }

  @Test("untimed transcript resources are ignored without fetching")
  func ignoresUntimedResources() async throws {
    let plain = reference("transcript.txt", type: "text/plain")
    let html = reference("transcript.html", type: "text/html")

    let imported = try await importer.importTranscript(from: [plain, html])

    #expect(imported == nil)
    #expect(await session.requests.isEmpty)
  }

  private func reference(
    _ name: String,
    type: String,
    language: String? = nil
  ) -> PublisherTranscriptReference {
    PublisherTranscriptReference(
      url: URL(string: "https://example.com/\(name)")!,
      mimeType: type,
      language: language
    )
  }
}
