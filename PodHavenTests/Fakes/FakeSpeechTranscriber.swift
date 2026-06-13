// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

struct FakeSpeechTranscriptionResult: SpeechTranscriptionResult {
  let phrase: String
  let startSeconds: Double?
}

enum FakeSpeechError: Error {
  case failed
}

struct FakeSpeechTranscriber: SpeechTranscribing {
  enum Behavior: Sendable {
    case succeed([FakeSpeechTranscriptionResult])
    case fail
  }

  let behavior: Behavior

  var resultStream: AsyncThrowingStream<any SpeechTranscriptionResult, any Error> {
    AsyncThrowingStream { continuation in
      switch behavior {
      case .succeed(let results):
        for result in results { continuation.yield(result) }
        continuation.finish()
      case .fail:
        continuation.finish(throwing: FakeSpeechError.failed)
      }
    }
  }
}
