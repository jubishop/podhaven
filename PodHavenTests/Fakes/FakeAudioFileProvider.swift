// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation

@testable import PodHaven

extension Container {
  var fakeAudioFileProvider: Factory<FakeAudioFileProvider> {
    Factory(self) { FakeAudioFileProvider() }.scope(.cached)
  }
}

private enum FakeAudioFileError: Error {
  case failedToCreateFormat
}

final class FakeAudioFileProvider: AudioFileProviding, Sendable {
  private struct Configuration: Sendable {
    var durationSeconds: TimeInterval = 60
    var sampleRate = 44_100.0
  }

  private let configuration = ThreadSafe(Configuration())

  func setDuration(_ durationSeconds: TimeInterval) {
    configuration { $0.durationSeconds = durationSeconds }
  }

  func audioFile(forReading url: URL) throws -> any AudioFileReading {
    let configuration = configuration()
    guard
      let format = AVAudioFormat(
        standardFormatWithSampleRate: configuration.sampleRate,
        channels: 1
      )
    else {
      throw FakeAudioFileError.failedToCreateFormat
    }
    return FakeAudioFile(
      format: format,
      length: AVAudioFramePosition(
        (configuration.durationSeconds * configuration.sampleRate).rounded()
      )
    )
  }
}

private final class FakeAudioFile: AudioFileReading, Sendable {
  let length: AVAudioFramePosition
  let processingFormat: AVAudioFormat

  private let position = ThreadSafe<AVAudioFramePosition>(0)

  var framePosition: AVAudioFramePosition {
    get { position() }
    set { position(newValue) }
  }

  init(format: AVAudioFormat, length: AVAudioFramePosition) {
    processingFormat = format
    self.length = length
  }

  func read(
    into buffer: AVAudioPCMBuffer,
    frameCount: AVAudioFrameCount
  ) throws {
    let framesRead = position { position in
      let availableFrames = Swift.max(0, length - position)
      let framesRead = AVAudioFrameCount(
        Swift.min(AVAudioFramePosition(frameCount), availableFrames)
      )
      position += AVAudioFramePosition(framesRead)
      return framesRead
    }
    buffer.frameLength = framesRead
    if let channelData = buffer.floatChannelData {
      for channel in 0..<Int(buffer.format.channelCount) {
        channelData[channel].update(repeating: 0, count: Int(framesRead))
      }
    }
  }
}
