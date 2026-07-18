// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

@testable import PodHaven

struct FakeSpeechAnalyzer: SpeechAnalyzing {
  var durationSeconds: Double = 60
  var analyzeAudio:
    (@Sendable (_ startTime: TimeInterval, _ endTime: TimeInterval) async throws -> CMTime?)?
  var cancelAudio: (@Sendable () async -> Void)?

  func duration(ofAudioFileAt url: URL) async throws -> Double { durationSeconds }
  func analyze(
    audioFileAt url: URL,
    from startTime: TimeInterval,
    to endTime: TimeInterval
  ) async throws -> CMTime? {
    if let analyzeAudio {
      return try await analyzeAudio(startTime, endTime)
    }
    return CMTime(seconds: endTime, preferredTimescale: 600)
  }
  func finalize(through time: CMTime) async throws {}
  func cancel() async {
    if let cancelAudio { await cancelAudio() }
  }
}
