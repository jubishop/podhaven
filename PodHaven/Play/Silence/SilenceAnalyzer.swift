// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

enum SilenceAnalysisError: Error {
  case invalidAudio
  case tooManyIntervals
}

struct SilenceMap: Codable, Equatable, Sendable {
  static let detectorVersion = 1
  static let maximumIntervals = 100_000
  let duration: Double
  let intervals: [QuietInterval]

  var isValid: Bool {
    guard duration.isFinite, duration > 0, intervals.count <= Self.maximumIntervals else {
      return false
    }
    var previousEnd = 0.0
    for interval in intervals {
      guard interval.start.isFinite, interval.end.isFinite,
        interval.start >= previousEnd, interval.end > interval.start, interval.end <= duration
      else { return false }
      previousEnd = interval.end
    }
    return true
  }
}

struct QuietDetector {
  private var intervals: [QuietInterval] = []
  private var quietStart: Double?
  private var expectedTime: Double?
  private var windowStart = 0.0
  private var windowFrames = 0
  private var windowPeak: Float = 0
  private var sampleRate = 0.0

  mutating func consume(samples: [Float], channels: Int, sampleRate: Double, time: Double) throws {
    guard channels > 0, sampleRate.isFinite, sampleRate > 0,
      time.isFinite, time >= 0, !samples.isEmpty, samples.count.isMultiple(of: channels)
    else { throw SilenceAnalysisError.invalidAudio }
    if let expectedTime,
      abs(time - expectedTime) > 2 / sampleRate || self.sampleRate != sampleRate
    {
      try finishQuiet(at: windowStart)
      windowFrames = 0
      windowPeak = 0
    }
    self.sampleRate = sampleRate
    let windowSize = max(1, Int(sampleRate * 0.01))
    let frames = samples.count / channels
    for frame in 0..<frames {
      if windowFrames == 0 { windowStart = time + Double(frame) / sampleRate }
      for channel in 0..<channels {
        let sample = samples[frame * channels + channel]
        guard sample.isFinite else { throw SilenceAnalysisError.invalidAudio }
        windowPeak = max(windowPeak, abs(sample))
      }
      windowFrames += 1
      if windowFrames == windowSize {
        if windowPeak < 0.001 {
          if quietStart == nil { quietStart = windowStart }
        } else {
          try finishQuiet(at: windowStart)
        }
        windowStart += Double(windowFrames) / sampleRate
        windowFrames = 0
        windowPeak = 0
      }
    }
    expectedTime = time + Double(frames) / sampleRate
  }

  mutating func finish(duration: Double) throws -> SilenceMap {
    try finishQuiet(at: min(windowStart, duration))
    let map = SilenceMap(duration: duration, intervals: intervals)
    guard map.isValid else { throw SilenceAnalysisError.invalidAudio }
    return map
  }

  private mutating func finishQuiet(at end: Double) throws {
    guard let start = quietStart else { return }
    quietStart = nil
    guard end - start >= 0.04 else { return }
    guard intervals.count < SilenceMap.maximumIntervals else {
      throw SilenceAnalysisError.tooManyIntervals
    }
    intervals.append(QuietInterval(start: start, end: end))
  }
}

enum SilenceAnalyzer {
  @concurrent static func analyze(
    _ url: URL,
    progress: @Sendable (_ processedSeconds: Double, _ totalSeconds: Double) -> Void
  ) async throws -> SilenceMap {
    try Task.checkCancellation()
    guard url.isFileURL else { throw SilenceAnalysisError.invalidAudio }
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration).seconds
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard let track = tracks.first, tracks.count == 1, duration.isFinite, duration > 0 else {
      throw SilenceAnalysisError.invalidAudio
    }
    progress(0, duration)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false,
        AVLinearPCMIsBigEndianKey: false,
      ]
    )
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw SilenceAnalysisError.invalidAudio }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? SilenceAnalysisError.invalidAudio }
    defer { reader.cancelReading() }
    var detector = QuietDetector()
    var readFrames = 0
    var processedSeconds = 0.0
    while reader.status == .reading {
      try Task.checkCancellation()
      let consumed: Bool = try autoreleasepool {
        guard let buffer = output.copyNextSampleBuffer() else { return false }
        guard CMSampleBufferDataIsReady(buffer),
          let format = CMSampleBufferGetFormatDescription(buffer),
          let audioFormat = unsafe CMAudioFormatDescriptionGetStreamBasicDescription(format)?
            .pointee,
          let block = CMSampleBufferGetDataBuffer(buffer)
        else { throw SilenceAnalysisError.invalidAudio }
        let channels = Int(audioFormat.mChannelsPerFrame)
        let count = CMSampleBufferGetNumSamples(buffer)
        guard channels > 0, channels <= 32, count > 0, count * channels <= 262_144,
          audioFormat.mBitsPerChannel == 32,
          CMBlockBufferGetDataLength(block) == count * channels * MemoryLayout<Float>.size
        else { throw SilenceAnalysisError.invalidAudio }
        var samples = [Float](repeating: 0, count: count * channels)
        let status = unsafe samples.withUnsafeMutableBytes { bytes in
          guard let address = bytes.baseAddress else { return OSStatus(-1) }
          return unsafe CMBlockBufferCopyDataBytes(
            block,
            atOffset: 0,
            dataLength: bytes.count,
            destination: address
          )
        }
        guard status == kCMBlockBufferNoErr else { throw SilenceAnalysisError.invalidAudio }
        try detector.consume(
          samples: samples,
          channels: channels,
          sampleRate: audioFormat.mSampleRate,
          time: CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        )
        readFrames += count
        processedSeconds += Double(count) / audioFormat.mSampleRate
        progress(min(processedSeconds, duration), duration)
        return true
      }
      if !consumed { break }
    }
    try Task.checkCancellation()
    guard reader.status == .completed, readFrames > 0 else {
      throw reader.error ?? SilenceAnalysisError.invalidAudio
    }
    return try detector.finish(duration: duration)
  }
}
