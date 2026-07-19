// Copyright Justin Bishop, 2026

import AVFoundation

protocol SpeechAnalyzing: Sendable {
  func bestAvailableAudioFormat(
    considering inputFormat: AVAudioFormat
  ) async -> AVAudioFormat?
  func analyze(_ inputSequence: RangedAudioInputSequence) async throws -> CMTime?
  func finalize(through time: CMTime) async throws
  func cancel() async
}
