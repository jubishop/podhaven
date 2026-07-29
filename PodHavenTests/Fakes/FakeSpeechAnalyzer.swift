// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

@testable import PodHaven

struct FakeSpeechAnalyzer: SpeechAnalyzing {
  var analyzeAudio:
    (@Sendable (_ startTime: TimeInterval, _ endTime: TimeInterval) async throws -> CMTime?)?
  var cancelAudio: (@Sendable () async -> Void)?
  var outputFormat: AVAudioFormat?
  var consumeInput: (@Sendable (RangedAudioInput) async throws -> Void)?

  func bestAvailableAudioFormat(
    considering inputFormat: AVAudioFormat
  ) async -> AVAudioFormat? {
    outputFormat ?? inputFormat
  }

  func analyze(_ inputSequence: RangedAudioInputSequence) async throws -> CMTime? {
    var startTime: CMTime?
    var analyzedFrameCount: Int64 = 0
    var sampleRate: Double?
    for try await input in inputSequence {
      if let consumeInput {
        try await consumeInput(input)
      }
      if let bufferStartTime = input.bufferStartTime {
        startTime = bufferStartTime
      }
      analyzedFrameCount += Int64(input.buffer.frameLength)
      sampleRate = input.buffer.format.sampleRate
    }
    guard let startTime, let sampleRate else { return nil }
    let analyzedThrough =
      startTime
      + CMTime(
        value: analyzedFrameCount,
        timescale: CMTimeScale(sampleRate)
      )
    if let analyzeAudio {
      return try await analyzeAudio(startTime.seconds, analyzedThrough.seconds)
    }
    return analyzedThrough
  }

  func finalize(through time: CMTime) async throws {}

  func cancel() async {
    if let cancelAudio { await cancelAudio() }
  }
}
