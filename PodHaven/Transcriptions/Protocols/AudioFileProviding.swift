// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

protocol AudioFileReading: AnyObject, Sendable {
  var length: AVAudioFramePosition { get }
  var processingFormat: AVAudioFormat { get }
  var framePosition: AVAudioFramePosition { get set }

  func read(
    into buffer: AVAudioPCMBuffer,
    frameCount: AVAudioFrameCount
  ) throws
}

extension AVAudioFile: AudioFileReading {}

protocol AudioFileProviding: Sendable {
  func audioFile(forReading url: URL) throws -> any AudioFileReading
}
