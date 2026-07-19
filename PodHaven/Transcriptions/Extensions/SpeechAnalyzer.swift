// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Speech

// MARK: - Errors

private enum SpeechAnalyzerInputError: LocalizedError {
  case incompatibleAudioFormat
  case failedToCreateBuffer
  case failedToCreateConverter
  case conversionFailed(NSError?)

  var errorDescription: String? {
    switch self {
    case .incompatibleAudioFormat:
      "No audio format is compatible with the speech analyzer"
    case .failedToCreateBuffer:
      "An audio buffer could not be created"
    case .failedToCreateConverter:
      "An audio converter could not be created"
    case .conversionFailed(let error):
      "Audio conversion failed: \(error?.localizedDescription ?? "unknown error")"
    }
  }
}

// MARK: - Container

extension Container {
  // Builds the analyzer for a module. Like AVPlayer.replaceCurrent's downcast,
  // it recovers the concrete SpeechTranscriber the analyzer requires from the
  // abstracted transcriber.
  var speechAnalyzer: Factory<@Sendable (any SpeechTranscribing) -> any SpeechAnalyzing> {
    Factory(self) {
      { transcribing in
        guard let module = transcribing as? SpeechTranscriber
        else {
          Assert.fatal("speechAnalyzer requires a real SpeechTranscriber module: \(transcribing)")
        }
        return SpeechAnalyzer(modules: [module])
      }
    }
  }
}

// MARK: - SpeechAnalyzer Conformance

extension SpeechAnalyzer: SpeechAnalyzing {
  // Opening the file lives here, behind the seam, so transcription tests drive
  // a FakeSpeechAnalyzer without a real audio file on disk.
  func duration(ofAudioFileAt url: URL) async throws -> Double {
    let file = try AVAudioFile(forReading: url)
    return Double(file.length) / file.processingFormat.sampleRate
  }

  func analyze(
    audioFileAt url: URL,
    from startTime: TimeInterval,
    to endTime: TimeInterval
  ) async throws -> CMTime? {
    let file = try AVAudioFile(forReading: url)
    guard
      let outputFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: modules,
        considering: file.processingFormat
      )
    else {
      throw SpeechAnalyzerInputError.incompatibleAudioFormat
    }
    let inputSequence = RangedAudioInputSequence(
      file: file,
      outputFormat: outputFormat,
      startTime: startTime,
      endTime: endTime
    )
    return try await analyzeSequence(inputSequence)
  }

  func finalize(through time: CMTime) async throws {
    try await finalizeAndFinish(through: time)
  }

  func cancel() async {
    await cancelAndFinishNow()
  }
}

// MARK: - Ranged Audio Input

private struct RangedAudioInputSequence: AsyncSequence, Sendable {
  typealias Element = AnalyzerInput

  struct AsyncIterator: AsyncIteratorProtocol {
    let state: State

    mutating func next() async throws -> AnalyzerInput? {
      try await state.next()
    }
  }

  private let state: State

  init(
    file: AVAudioFile,
    outputFormat: AVAudioFormat,
    startTime: TimeInterval,
    endTime: TimeInterval
  ) {
    state = State(
      file: file,
      outputFormat: outputFormat,
      startTime: startTime,
      endTime: endTime
    )
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(state: state)
  }

  actor State {
    private static let readBufferFrameCapacity: AVAudioFrameCount = 8_192

    private let file: AVAudioFile
    private let outputFormat: AVAudioFormat
    private let endFrame: AVAudioFramePosition
    private let startSampleTime: CMTime
    private var converter = AudioBufferConverter()
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private var inputFinished = false
    private var isFirstBuffer = true

    init(
      file: AVAudioFile,
      outputFormat: AVAudioFormat,
      startTime: TimeInterval,
      endTime: TimeInterval
    ) {
      self.file = file
      self.outputFormat = outputFormat

      let sampleRate = file.processingFormat.sampleRate
      let startFrame = Swift.max(
        0,
        Swift.min(
          file.length,
          AVAudioFramePosition((startTime * sampleRate).rounded(.down))
        )
      )
      endFrame = Swift.max(
        startFrame,
        Swift.min(
          file.length,
          AVAudioFramePosition((endTime * sampleRate).rounded(.up))
        )
      )
      startSampleTime = CMTime(
        seconds: Double(startFrame) / sampleRate,
        preferredTimescale: 1_000_000_000
      )
      file.framePosition = startFrame
    }

    func next() throws -> AnalyzerInput? {
      try Task.checkCancellation()

      while true {
        if !pendingBuffers.isEmpty {
          let convertedBuffer = pendingBuffers.removeFirst()
          let bufferStartTime: CMTime?
          if isFirstBuffer {
            bufferStartTime = startSampleTime
            isFirstBuffer = false
          } else {
            bufferStartTime = nil
          }
          return AnalyzerInput(buffer: convertedBuffer, bufferStartTime: bufferStartTime)
        }

        guard !inputFinished else { return nil }

        let remainingFrames = endFrame - file.framePosition
        guard remainingFrames > 0 else {
          inputFinished = true
          pendingBuffers = try converter.finish()
          continue
        }

        let frameCapacity = AVAudioFrameCount(
          Swift.min(
            AVAudioFramePosition(Self.readBufferFrameCapacity),
            remainingFrames
          )
        )
        guard
          let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCapacity
          )
        else {
          throw SpeechAnalyzerInputError.failedToCreateBuffer
        }
        try file.read(into: sourceBuffer, frameCount: frameCapacity)
        guard sourceBuffer.frameLength > 0 else {
          inputFinished = true
          pendingBuffers = try converter.finish()
          continue
        }

        pendingBuffers = try converter.convert(sourceBuffer, to: outputFormat)
      }
    }
  }
}

struct AudioBufferConverter {
  private static let outputBufferFrameCapacity: AVAudioFrameCount = 8_192

  private var converter: AVAudioConverter?

  mutating func convert(
    _ buffer: AVAudioPCMBuffer,
    to outputFormat: AVAudioFormat
  ) throws -> [AVAudioPCMBuffer] {
    let inputFormat = buffer.format
    guard inputFormat != outputFormat else { return [buffer] }

    if let converter {
      if converter.inputFormat != inputFormat || converter.outputFormat != outputFormat {
        self.converter = nil
      }
    }
    if converter == nil {
      converter = AVAudioConverter(from: inputFormat, to: outputFormat)
      converter?.primeMethod = .none
    }
    guard let converter else {
      throw SpeechAnalyzerInputError.failedToCreateConverter
    }

    // AVAudioConverter invokes this callback synchronously during convert.
    nonisolated(unsafe) let inputBuffer = buffer
    let bufferWasProvided = ThreadSafe(false)
    var convertedBuffers: [AVAudioPCMBuffer] = []

    while true {
      let conversionBuffer = try makeOutputBuffer(for: converter)
      var conversionError: NSError?
      let status = unsafe converter.convert(to: conversionBuffer, error: &conversionError) {
        _,
        inputStatus in
        let shouldProvideBuffer = bufferWasProvided { wasProvided in
          if wasProvided {
            return false
          }
          wasProvided = true
          return true
        }
        unsafe inputStatus.pointee = shouldProvideBuffer ? .haveData : .noDataNow
        return unsafe shouldProvideBuffer ? inputBuffer : nil
      }
      if conversionBuffer.frameLength > 0 {
        convertedBuffers.append(conversionBuffer)
      }

      switch status {
      case .haveData:
        continue
      case .inputRanDry, .endOfStream:
        return convertedBuffers
      case .error:
        throw SpeechAnalyzerInputError.conversionFailed(conversionError)
      @unknown default:
        throw SpeechAnalyzerInputError.conversionFailed(conversionError)
      }
    }
  }

  mutating func finish() throws -> [AVAudioPCMBuffer] {
    guard let converter else { return [] }
    defer { self.converter = nil }

    var convertedBuffers: [AVAudioPCMBuffer] = []
    while true {
      let conversionBuffer = try makeOutputBuffer(for: converter)
      var conversionError: NSError?
      let status = unsafe converter.convert(to: conversionBuffer, error: &conversionError) {
        _,
        inputStatus in
        unsafe inputStatus.pointee = .endOfStream
        return nil
      }
      if conversionBuffer.frameLength > 0 {
        convertedBuffers.append(conversionBuffer)
      }

      switch status {
      case .haveData:
        continue
      case .inputRanDry:
        guard conversionBuffer.frameLength > 0 else { return convertedBuffers }
      case .endOfStream:
        return convertedBuffers
      case .error:
        throw SpeechAnalyzerInputError.conversionFailed(conversionError)
      @unknown default:
        throw SpeechAnalyzerInputError.conversionFailed(conversionError)
      }
    }
  }

  private func makeOutputBuffer(
    for converter: AVAudioConverter
  ) throws -> AVAudioPCMBuffer {
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: converter.outputFormat,
        frameCapacity: Self.outputBufferFrameCapacity
      )
    else {
      throw SpeechAnalyzerInputError.failedToCreateBuffer
    }
    return buffer
  }
}
