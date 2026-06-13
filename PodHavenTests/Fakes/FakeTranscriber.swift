// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

struct FakeTranscriber: Transcribing {
  enum Behavior: Sendable {
    case succeed([TranscriptSegment])
    case fail
  }

  let behavior: Behavior

  func transcribe(fileURL: URL, locale: Locale) async throws -> [TranscriptSegment] {
    switch behavior {
    case .succeed(let segments):
      return segments
    case .fail:
      throw FakeTranscriberError.failed
    }
  }
}

enum FakeTranscriberError: Error {
  case failed
}
