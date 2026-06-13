// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Speech

// MARK: - Container

extension Container {
  // Builds the analyzer for a module. Like AVPlayer.replaceCurrent's downcast,
  // it recovers the concrete SpeechTranscriber the analyzer requires from the
  // abstracted transcriber.
  var speechAnalyzer: Factory<@Sendable (any SpeechTranscribing) -> any SpeechAnalyzing> {
    Factory(self) {
      { transcribing in
        guard let module = transcribing as? SpeechTranscriber
        else {
          Assert.fatal("speechAnalyzer requires a real SpeechTranscriber module: \(transcribing)")
        }
        return SpeechAnalyzer(modules: [module])
      }
    }
  }
}

// MARK: - SpeechAnalyzer Conformance

extension SpeechAnalyzer: SpeechAnalyzing {
  // Opening the file lives here, behind the seam, so transcription tests drive
  // a FakeSpeechAnalyzer without a real audio file on disk.
  func analyze(audioFileAt url: URL) async throws -> CMTime? {
    try await analyzeSequence(from: AVAudioFile(forReading: url))
  }

  func finalize(through time: CMTime) async throws {
    try await finalizeAndFinish(through: time)
  }

  func cancel() async {
    await cancelAndFinishNow()
  }
}
