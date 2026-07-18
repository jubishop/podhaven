// Copyright Justin Bishop, 2026

import Foundation

struct TranscriptSegment: Codable, Hashable, Sendable {
  // Seconds from the start of the episode audio.
  let start: TimeInterval
  let end: TimeInterval?
  let text: String

  init(start: TimeInterval, end: TimeInterval? = nil, text: String) {
    self.start = start
    self.end = end
    self.text = text
  }
}

struct Transcript: Codable, Hashable, Sendable {
  let segments: [TranscriptSegment]
  let locale: String
  let createdAt: Date
  // Bumping the transcriber's model revision invalidates older transcripts,
  // the same way EmbeddingService.recipeVersion invalidates cached vectors.
  let modelRevision: Int

  init(segments: [TranscriptSegment], locale: String, createdAt: Date, modelRevision: Int) {
    self.segments = segments
    self.locale = locale
    self.createdAt = createdAt
    self.modelRevision = modelRevision
  }

  init(decoding json: String) throws {
    self = try JSONDecoder().decode(Self.self, from: Data(json.utf8))
  }

  func jsonString() throws -> String {
    String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
  }
}

struct TranscriptionCheckpoint: Codable, Hashable, Sendable {
  let segments: [TranscriptSegment]
  let audioTime: TimeInterval
  let duration: TimeInterval
  let locale: String
  let modelRevision: Int
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
    modelRevision: Int,
    audioSHA256: String
  ) {
    self.segments = segments
    self.audioTime = audioTime
    self.duration = duration
    self.locale = locale
    self.modelRevision = modelRevision
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
    modelRevision: Int,
    audioSHA256: String
  ) -> Bool {
    let timeTolerance = 0.01
    guard
      duration > 0
        && audioTime >= 0
        && audioTime <= duration
        && abs(self.duration - duration) <= timeTolerance
        && self.locale == locale.identifier(.bcp47)
        && self.modelRevision == modelRevision
        && self.audioSHA256 == audioSHA256
    else {
      return false
    }
    return segments.allSatisfy { segment in
      guard segment.start >= 0 && segment.start <= audioTime + timeTolerance else {
        return false
      }
      if let end = segment.end {
        return end >= segment.start && end <= audioTime + timeTolerance
      }
      return true
    }
  }

  func merging(
    _ newSegments: [TranscriptSegment],
    from startTime: TimeInterval,
    through endTime: TimeInterval
  ) -> Self {
    let retainedSegments = segments.filter { segment in
      if let end = segment.end {
        return end <= startTime
      }
      return segment.start < startTime
    }
    let replacementSegments = newSegments.filter {
      $0.start >= startTime && $0.start < endTime
    }
    return Self(
      segments: retainedSegments + replacementSegments,
      audioTime: endTime,
      duration: duration,
      locale: locale,
      modelRevision: modelRevision,
      audioSHA256: audioSHA256
    )
  }
}
