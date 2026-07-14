// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

// Drives audio through its modules and reports completion, abstracted as a test
// seam the same way AVPlayable abstracts AVPlayer. The real SpeechAnalyzer
// conforms in an extension; FakeSpeechAnalyzer is a no-op that lets a
// FakeSpeechTranscriber's canned results flow.
protocol SpeechAnalyzing: Sendable {
  // The audio file's total duration in seconds, read up front so progress can
  // be reported against it while analyze(audioFileAt:) feeds the file through.
  func duration(ofAudioFileAt url: URL) async throws -> Double
  // Opens the audio file and analyzes it, returning the last sample time, or
  // nil when the file produced no audio.
  func analyze(audioFileAt url: URL) async throws -> CMTime?
  func finalize(through time: CMTime) async throws
  func cancel() async
}
