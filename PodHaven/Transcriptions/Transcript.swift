// Copyright Justin Bishop, 2026

import Foundation

struct TranscriptSegment: Codable, Hashable, Sendable {
  // Seconds from the start of the episode audio.
  let start: TimeInterval
  let text: String
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
