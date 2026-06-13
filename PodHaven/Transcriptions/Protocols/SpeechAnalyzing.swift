// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

// Drives audio through its modules and reports completion, abstracted as a test
// seam the same way AVPlayable abstracts AVPlayer. The real SpeechAnalyzer
// conforms in an extension; FakeSpeechAnalyzer is a no-op that lets a
// FakeSpeechTranscriber's canned results flow.
protocol SpeechAnalyzing: Sendable {
  // Opens the audio file and analyzes it, returning the last sample time, or
  // nil when the file produced no audio.
  func analyze(audioFileAt url: URL) async throws -> CMTime?
  func finalize(through time: CMTime) async throws
  func cancel() async
}
