// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

@testable import PodHaven

struct FakeSpeechAnalyzer: SpeechAnalyzing {
  // Non-nil so Transcriber takes the finalize path; the URL is ignored, so
  // transcription tests need no real audio file on disk.
  var lastSampleTime: CMTime? = .zero
  // Canned file duration; a non-positive value disables progress reporting in collectSegments.
  var durationSeconds: Double = 0
  var analyzeAudio: (@Sendable () async throws -> CMTime?)?

  func duration(ofAudioFileAt url: URL) async throws -> Double { durationSeconds }
  func analyze(audioFileAt url: URL) async throws -> CMTime? {
    guard let analyzeAudio else { return lastSampleTime }
    return try await analyzeAudio()
  }
  func finalize(through time: CMTime) async throws {}
  func cancel() async {}
}
