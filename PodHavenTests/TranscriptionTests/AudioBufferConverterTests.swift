// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Testing

@testable import PodHaven

@Suite("of AudioBufferConverter", .container)
struct AudioBufferConverterTests {
  @Test("preserves the complete duration when resampling")
  func preservesCompleteDuration() throws {
    let inputFormat = try #require(
      AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)
    )
    let outputFormat = try #require(
      AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
      )
    )
    let duration = 30.0
    var remainingFrames = AVAudioFramePosition(duration * inputFormat.sampleRate)
    var convertedBuffers: [AVAudioPCMBuffer] = []
    var converter = AudioBufferConverter()

    while remainingFrames > 0 {
      let frameCapacity = AVAudioFrameCount(
        min(AVAudioFramePosition(8_192), remainingFrames)
      )
      let sourceBuffer = try #require(
        AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCapacity)
      )
      sourceBuffer.frameLength = frameCapacity
      let channelData = try #require(sourceBuffer.floatChannelData)
      channelData[0].update(repeating: 0, count: Int(frameCapacity))

      convertedBuffers.append(contentsOf: try converter.convert(sourceBuffer, to: outputFormat))
      remainingFrames -= AVAudioFramePosition(frameCapacity)
    }
    convertedBuffers.append(contentsOf: try converter.finish())

    let convertedFrameCount = convertedBuffers.reduce(AVAudioFramePosition(0)) {
      $0 + AVAudioFramePosition($1.frameLength)
    }
    let convertedDuration = Double(convertedFrameCount) / outputFormat.sampleRate

    #expect(abs(convertedDuration - duration) <= 0.01)
  }
}
