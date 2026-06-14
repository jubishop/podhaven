// Copyright Justin Bishop, 2026

import FactoryKit

@testable import PodHaven

enum TranscriptionHelpers {
  // Registers the on-device speech seam so transcription proceeds in tests: a
  // no-op analyzer, a supported+installed locale, and a transcriber emitting the
  // given phrases. Returns the model manager so callers can assert on installs.
  @discardableResult
  static func stubSpeech(
    phrases: [FakeSpeechTranscriptionResult] = [],
    durationSeconds: Double = 0,
    modelManager: FakeSpeechModelManager = FakeSpeechModelManager()
  ) -> FakeSpeechModelManager {
    Container.shared.speechTranscriber.register {
      { _ in FakeSpeechTranscriber(behavior: .succeed(phrases)) }
    }
    Container.shared.speechAnalyzer.register {
      { _ in FakeSpeechAnalyzer(durationSeconds: durationSeconds) }
    }
    Container.shared.speechModelManager.register { modelManager }
    return modelManager
  }

  static func stubSpeechFailure() {
    Container.shared.speechTranscriber.register { { _ in FakeSpeechTranscriber(behavior: .fail) } }
    Container.shared.speechAnalyzer.register { { _ in FakeSpeechAnalyzer() } }
    Container.shared.speechModelManager.register { FakeSpeechModelManager() }
  }
}
