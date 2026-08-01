// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of Transcript timing tests")
struct TranscriptTests {
  @Test("word timings survive transcript persistence and select the current word")
  func wordTimingRoundTrip() throws {
    let segment = TranscriptSegment(
      start: 2,
      end: 5,
      text: "Hello world!",
      words: [
        TranscriptWord(start: 2, end: 3, text: "Hello"),
        TranscriptWord(start: 3, end: 5, text: " world!"),
      ]
    )
    let transcript = Transcript(
      segments: [segment],
      locale: "en-US",
      createdAt: Date(timeIntervalSinceReferenceDate: 1)
    )

    let decoded = try Transcript(decoding: transcript.jsonString())

    #expect(decoded == transcript)
    #expect(decoded.activeSegmentIndex(at: 2) == 0)
    #expect(decoded.segments[0].activeWordIndex(at: 2.5) == 0)
    #expect(decoded.segments[0].activeWordIndex(at: 3) == 1)
    #expect(decoded.segments[0].activeWordIndex(at: 5) == nil)
  }

  @Test("legacy segments decode with phrase-level playback timing")
  func legacySegmentFallback() throws {
    let transcript = try Transcript(
      decoding: """
        {"segments":[{"start":1,"end":3,"text":"Legacy phrase"}],\
        "locale":"en-US","createdAt":1}
        """
    )
    let segment = try #require(transcript.segments.first)

    #expect(segment.words.isEmpty)
    #expect(
      segment.playbackWords
        == [TranscriptWord(start: 1, end: 3, text: "Legacy phrase")]
    )
    #expect(segment.activeWordIndex(at: 2) == 0)
  }

  @Test("mismatched timed runs fall back without changing displayed text")
  func mismatchedWordsFallback() {
    let segment = TranscriptSegment(
      start: 0,
      end: 2,
      text: "Keep punctuation.",
      words: [TranscriptWord(start: 0, end: 2, text: "Keep punctuation")]
    )

    #expect(
      segment.playbackWords
        == [TranscriptWord(start: 0, end: 2, text: "Keep punctuation.")]
    )
  }
}
