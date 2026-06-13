// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

@testable import PodHaven

struct FakeSpeechAnalyzer: SpeechAnalyzing {
  // Non-nil so Transcriber takes the finalize path; the URL is ignored, so
  // transcription tests need no real audio file on disk.
  var lastSampleTime: CMTime? = .zero

  func analyze(audioFileAt url: URL) async throws -> CMTime? { lastSampleTime }
  func finalize(through time: CMTime) async throws {}
  func cancel() async {}
}
