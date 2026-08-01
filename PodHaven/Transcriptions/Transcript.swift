// Copyright Justin Bishop, 2026

import Foundation

// Persisted payload changes require a database migration that rewrites or
// clears stored JSON.
struct TranscriptWord: Codable, Hashable, Sendable {
  let start: TimeInterval
  let end: TimeInterval
  let text: String
}

struct TranscriptSegment: Codable, Hashable, Sendable {
  let start: TimeInterval
  let end: TimeInterval
  let text: String
  let words: [TranscriptWord]

  init(
    start: TimeInterval,
    end: TimeInterval,
    text: String,
    words: [TranscriptWord] = []
  ) {
    self.start = start
    self.end = end
    self.text = text
    self.words = words
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    start = try container.decode(TimeInterval.self, forKey: .start)
    end = try container.decode(TimeInterval.self, forKey: .end)
    text = try container.decode(String.self, forKey: .text)
    words = try container.decodeIfPresent([TranscriptWord].self, forKey: .words) ?? []
  }

  var playbackWords: [TranscriptWord] {
    var normalized = words
    while let first = normalized.first {
      let trimmed = String(first.text.drop(while: \.isWhitespace))
      guard !trimmed.isEmpty else {
        normalized.removeFirst()
        continue
      }
      normalized[0] = TranscriptWord(start: first.start, end: first.end, text: trimmed)
      break
    }
    while let last = normalized.last {
      let trimmed = String(last.text.reversed().drop(while: \.isWhitespace).reversed())
      guard !trimmed.isEmpty else {
        normalized.removeLast()
        continue
      }
      normalized[normalized.count - 1] = TranscriptWord(
        start: last.start,
        end: last.end,
        text: trimmed
      )
      break
    }
    guard !normalized.isEmpty, normalized.map(\.text).joined() == text else {
      return [TranscriptWord(start: start, end: end, text: text)]
    }
    return normalized
  }

  func activeWordIndex(at currentTime: TimeInterval) -> Int? {
    guard currentTime.isFinite else { return nil }
    return playbackWords.lastIndex { word in
      word.start <= currentTime && currentTime < word.end
    }
  }
}

struct Transcript: Codable, Hashable, Sendable {
  let segments: [TranscriptSegment]
  let locale: String
  let createdAt: Date

  init(segments: [TranscriptSegment], locale: String, createdAt: Date) {
    self.segments = segments
    self.locale = locale
    self.createdAt = createdAt
  }

  init(decoding json: String) throws {
    self = try JSONDecoder().decode(Self.self, from: Data(json.utf8))
  }

  func jsonString() throws -> String {
    String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
  }

  func activeSegmentIndex(at currentTime: TimeInterval) -> Int? {
    guard currentTime.isFinite else { return nil }
    return segments.lastIndex { segment in
      segment.start <= currentTime && currentTime < segment.end
    }
  }
}

struct TranscriptionCheckpoint: Codable, Hashable, Sendable {
  private static let timeTolerance: TimeInterval = 0.01

  let segments: [TranscriptSegment]
  let audioTime: TimeInterval
  let duration: TimeInterval
  let locale: String
  let audioSHA256: String

  var progress: Double {
    guard duration > 0 else { return 0 }
    return min(1, max(0, audioTime / duration))
  }

  init(
    segments: [TranscriptSegment],
    audioTime: TimeInterval,
    duration: TimeInterval,
    locale: String,
    audioSHA256: String
  ) {
    self.segments = segments
    self.audioTime = audioTime
    self.duration = duration
    self.locale = locale
    self.audioSHA256 = audioSHA256
  }

  init(decoding json: String) throws {
    self = try JSONDecoder().decode(Self.self, from: Data(json.utf8))
  }

  func jsonString() throws -> String {
    String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
  }

  func isCompatible(
    duration: TimeInterval,
    locale: Locale,
    audioSHA256: String
  ) -> Bool {
    guard
      duration > 0
        && audioTime >= 0
        && audioTime <= duration
        && abs(self.duration - duration) <= Self.timeTolerance
        && self.locale == locale.identifier(.bcp47)
        && self.audioSHA256 == audioSHA256
    else {
      return false
    }
    return segments.allSatisfy { segment in
      guard segment.start >= 0 && segment.start <= audioTime + Self.timeTolerance else {
        return false
      }
      guard segment.end >= segment.start && segment.end <= audioTime + Self.timeTolerance else {
        return false
      }
      return segment.words.allSatisfy { word in
        word.start + Self.timeTolerance >= segment.start
          && word.end >= word.start
          && word.end <= segment.end + Self.timeTolerance
      }
    }
  }

  func merging(
    _ newSegments: [TranscriptSegment],
    from startTime: TimeInterval,
    through endTime: TimeInterval
  ) -> Self {
    let retainedSegments = segments.filter { segment in
      segment.end <= startTime
    }
    let earliestReplacementStart = max(0, startTime - Self.timeTolerance)
    let replacementSegments = newSegments.filter {
      $0.start >= earliestReplacementStart
        && $0.start < endTime
        && $0.end > startTime
    }
    return Self(
      segments: retainedSegments + replacementSegments,
      audioTime: endTime,
      duration: duration,
      locale: locale,
      audioSHA256: audioSHA256
    )
  }
}
