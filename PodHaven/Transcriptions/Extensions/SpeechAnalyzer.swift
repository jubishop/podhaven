// Copyright Justin Bishop, 2026

import FactoryKit
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
  func bestAvailableAudioFormat(
    considering inputFormat: AVAudioFormat
  ) async -> AVAudioFormat? {
    await SpeechAnalyzer.bestAvailableAudioFormat(
      compatibleWith: modules,
      considering: inputFormat
    )
  }

  func analyze(_ inputSequence: RangedAudioInputSequence) async throws -> CMTime? {
    try await analyzeSequence(SpeechAnalyzerInputSequence(inputSequence: inputSequence))
  }

  func finalize(through time: CMTime) async throws {
    try await finalizeAndFinish(through: time)
  }

  func cancel() async {
    await cancelAndFinishNow()
  }
}

private struct SpeechAnalyzerInputSequence: AsyncSequence, Sendable {
  typealias Element = AnalyzerInput

  struct AsyncIterator: AsyncIteratorProtocol {
    var iterator: RangedAudioInputSequence.AsyncIterator

    mutating func next() async throws -> AnalyzerInput? {
      guard let input = try await iterator.next() else { return nil }
      return AnalyzerInput(
        buffer: input.buffer,
        bufferStartTime: input.bufferStartTime
      )
    }
  }

  let inputSequence: RangedAudioInputSequence

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(iterator: inputSequence.makeAsyncIterator())
  }
}
