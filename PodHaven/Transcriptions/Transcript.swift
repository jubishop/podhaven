// Copyright Justin Bishop, 2026

import Foundation

// Persisted payload changes require a database migration that rewrites or
// clears stored JSON.
struct TranscriptSegment: Codable, Hashable, Sendable {
  // Seconds from the start of the episode audio.
  let start: TimeInterval
  let end: TimeInterval
  let text: String
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
      return segment.end >= segment.start && segment.end <= audioTime + Self.timeTolerance
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
