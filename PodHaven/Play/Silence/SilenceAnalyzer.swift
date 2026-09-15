// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

enum SilenceAnalysisError: Error {
  case invalidAudio
  case tooManyIntervals
}

struct SilenceMap: Codable, Equatable, Sendable {
  static let detectorVersion = 2
  static let maximumIntervals = 100_000
  let duration: Double
  let high: [QuietInterval]
  let medium: [QuietInterval]
  let low: [QuietInterval]

  func intervals(for protection: QuietAudioProtection) -> [QuietInterval] {
    switch protection {
    case .high: high
    case .medium: medium
    case .low: low
    }
  }

  var intervalCount: Int { high.count + medium.count + low.count }

  var isValid: Bool {
    guard duration.isFinite, duration > 0, intervalCount <= Self.maximumIntervals else {
      return false
    }
    for protection in QuietAudioProtection.allCases {
      var previousEnd = 0.0
      for interval in intervals(for: protection) {
        guard interval.start.isFinite, interval.end.isFinite,
          interval.start >= previousEnd, interval.end > interval.start, interval.end <= duration
        else { return false }
        previousEnd = interval.end
      }
    }
    return true
  }
}

private struct QuietRun {
  let threshold: Float
  var intervals: [QuietInterval] = []
  private var quietStart: Double?

  init(threshold: Float) { self.threshold = threshold }

  mutating func consume(peak: Float, at time: Double) {
    if peak < threshold {
      if quietStart == nil { quietStart = time }
    } else {
      finish(at: time)
    }
  }

  mutating func finish(at end: Double) {
    guard let start = quietStart else { return }
    quietStart = nil
    guard end - start >= 0.04 else { return }
    intervals.append(QuietInterval(start: start, end: end))
  }
}

struct QuietDetector {
  private var high = QuietRun(threshold: QuietAudioProtection.high.threshold)
  private var medium = QuietRun(threshold: QuietAudioProtection.medium.threshold)
  private var low = QuietRun(threshold: QuietAudioProtection.low.threshold)
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
      high.finish(at: windowStart)
      medium.finish(at: windowStart)
      low.finish(at: windowStart)
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
        high.consume(peak: windowPeak, at: windowStart)
        medium.consume(peak: windowPeak, at: windowStart)
        low.consume(peak: windowPeak, at: windowStart)
        guard
          high.intervals.count + medium.intervals.count + low.intervals.count
            <= SilenceMap.maximumIntervals
        else { throw SilenceAnalysisError.tooManyIntervals }
        windowStart += Double(windowFrames) / sampleRate
        windowFrames = 0
        windowPeak = 0
      }
    }
    expectedTime = time + Double(frames) / sampleRate
  }

  mutating func finish(duration: Double) throws -> SilenceMap {
    high.finish(at: min(windowStart, duration))
    medium.finish(at: min(windowStart, duration))
    low.finish(at: min(windowStart, duration))
    let map = SilenceMap(
      duration: duration,
      high: high.intervals,
      medium: medium.intervals,
      low: low.intervals
    )
    guard map.intervalCount <= SilenceMap.maximumIntervals else {
      throw SilenceAnalysisError.tooManyIntervals
    }
    guard map.isValid else { throw SilenceAnalysisError.invalidAudio }
    return map
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
        let status = samples.withUnsafeMutableBytes { bytes in
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
