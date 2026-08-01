// Copyright Justin Bishop, 2026

import AVFoundation
import CoreMedia
import FactoryKit
import Foundation
import Logging

// MARK: - Container

extension Container {
  var transcriber: Factory<Transcriber> {
    Factory(self) { Transcriber() }.scope(.cached)
  }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
  case localeNotSupported(Locale)
  case audioUnavailable(Episode.ID)
  case noDecodableAudio(URL)
  case incompleteAudioRange(expectedEndTime: TimeInterval, actualEndTime: TimeInterval)
  case missingAudioEndTime

  var errorDescription: String? {
    switch self {
    case .localeNotSupported(let locale):
      "On-device transcription is not supported for \(locale.identifier(.bcp47))"
    case .audioUnavailable(let episodeID):
      "Audio for episode \(episodeID) could not be downloaded for transcription"
    case .noDecodableAudio(let url):
      "No audio could be decoded from \(url.lastPathComponent) for transcription"
    case .incompleteAudioRange(let expectedEndTime, let actualEndTime):
      """
      Audio analysis stopped at \(actualEndTime) seconds before the requested \
      \(expectedEndTime)-second boundary
      """
    case .missingAudioEndTime:
      "A transcription result did not include its audio end time"
    }
  }
}

struct TranscriptionLogContext: Sendable {
  enum Mode: String, Sendable {
    case foreground
    case background
  }

  let runID: String
  let mode: Mode
  let episodeID: Episode.ID

  var fields: String {
    "runID=\(runID) mode=\(mode.rawValue) episodeID=\(episodeID)"
  }
}

// MARK: - Transcriber

// Orchestrates an on-device transcription: ensure the locale's model is
// installed, then drive the audio through a SpeechAnalyzing while collecting the
// SpeechTranscribing's phrases. The OS objects sit behind protocols so this
// orchestration is testable; SpeechAnalyzer/SpeechTranscriber conform in
// extensions.
struct Transcriber: Sendable {
  private enum CheckpointDisposition: String {
    case new
    case resumed
    case restartedIncompatible
  }

  @DynamicInjected(\.audioFileProvider) private var audioFileProvider
  @DynamicInjected(\.audioFileHasher) private var audioFileHasher
  @DynamicInjected(\.continuousClockNow) private var continuousClockNow
  @DynamicInjected(\.speechAnalyzer) private var speechAnalyzer
  @DynamicInjected(\.speechModelManager) private var speechModelManager
  @DynamicInjected(\.speechTranscriber) private var speechTranscriber

  private static let chunkDuration: TimeInterval = 120
  private static let chunkOverlap: TimeInterval = 10
  private static let analysisCoverageTolerance: TimeInterval = 0.01

  private static let log = Log.as(LogSubsystem.Transcription.transcriber)

  fileprivate init() {}

  func supports(_ locale: Locale) async -> Bool {
    let target = locale.identifier(.bcp47)
    return await speechModelManager.supportedLocaleIdentifiers().contains(target)
  }

  func transcribe(
    fileURL: URL,
    locale: Locale,
    logContext: TranscriptionLogContext,
    checkpoint: TranscriptionCheckpoint? = nil,
    onProgress: @Sendable (Double) -> Void = { _ in },
    onCheckpoint: @Sendable (TranscriptionCheckpoint) async throws -> Void = { _ in }
  ) async throws -> [TranscriptSegment] {
    let sessionStartedAt = continuousClockNow()
    Self.log.info(
      """
      transcriptionTelemetry event=sessionPreparing \(logContext.fields) \
      file=\(fileURL.lastPathComponent)
      """
    )
    try Task.checkCancellation()
    try await ensureModelInstalled(for: locale, logContext: logContext)
    let audioSHA256 = try audioFileHasher.sha256(of: fileURL)
    try Task.checkCancellation()

    let firstTranscriber = speechTranscriber(locale)
    let firstAnalyzer = speechAnalyzer(firstTranscriber)
    let audioFile = try audioFileProvider.audioFile(forReading: fileURL)
    let durationSeconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate
    guard durationSeconds > 0 else {
      throw TranscriptionError.noDecodableAudio(fileURL)
    }
    try Task.checkCancellation()

    var workingCheckpoint: TranscriptionCheckpoint
    let checkpointDisposition: CheckpointDisposition
    if let checkpoint,
      checkpoint.isCompatible(
        duration: durationSeconds,
        locale: locale,
        audioSHA256: audioSHA256
      )
    {
      workingCheckpoint = checkpoint
      checkpointDisposition = .resumed
    } else {
      workingCheckpoint = TranscriptionCheckpoint(
        segments: [],
        audioTime: 0,
        duration: durationSeconds,
        locale: locale.identifier(.bcp47),
        audioSHA256: audioSHA256
      )
      checkpointDisposition = checkpoint == nil ? .new : .restartedIncompatible
    }
    if checkpoint != nil {
      onProgress(workingCheckpoint.progress)
    }
    Self.log.info(
      """
      transcriptionTelemetry event=sessionStarted \(logContext.fields) \
      file=\(fileURL.lastPathComponent) durationSeconds=\(durationSeconds) \
      checkpointDisposition=\(checkpointDisposition.rawValue) \
      committedAudioSeconds=\(workingCheckpoint.audioTime) \
      remainingAudioSeconds=\(durationSeconds - workingCheckpoint.audioTime) \
      checkpointSegments=\(workingCheckpoint.segments.count)
      """
    )

    var firstPair: (any SpeechTranscribing, any SpeechAnalyzing)? = (
      firstTranscriber,
      firstAnalyzer
    )
    while workingCheckpoint.audioTime < durationSeconds {
      try Task.checkCancellation()

      let endTime = min(
        durationSeconds,
        workingCheckpoint.audioTime + Self.chunkDuration
      )
      let nominalStartTime = max(0, workingCheckpoint.audioTime - Self.chunkOverlap)
      var startTime = nominalStartTime
      for segment in workingCheckpoint.segments {
        guard
          segment.start < nominalStartTime,
          segment.end > nominalStartTime
        else {
          continue
        }
        startTime = min(startTime, segment.start)
      }
      let transcriber: any SpeechTranscribing
      let analyzer: any SpeechAnalyzing
      if let pair = firstPair {
        transcriber = pair.0
        analyzer = pair.1
        firstPair = nil
      } else {
        transcriber = speechTranscriber(locale)
        analyzer = speechAnalyzer(transcriber)
      }

      let segments = try await transcribeChunk(
        fileURL: fileURL,
        transcriber: transcriber,
        analyzer: analyzer,
        durationSeconds: durationSeconds,
        committedAudioTime: workingCheckpoint.audioTime,
        startTime: startTime,
        endTime: endTime,
        initialProgress: workingCheckpoint.progress,
        logContext: logContext,
        onProgress: onProgress
      )
      try Task.checkCancellation()
      workingCheckpoint = workingCheckpoint.merging(
        segments,
        from: startTime,
        through: endTime
      )
      try await onCheckpoint(workingCheckpoint)
    }

    Self.log.info(
      """
      transcriptionTelemetry event=sessionCompleted \(logContext.fields) \
      file=\(fileURL.lastPathComponent) durationSeconds=\(durationSeconds) \
      wallSeconds=\((continuousClockNow() - sessionStartedAt).asTimeInterval) \
      segments=\(workingCheckpoint.segments.count)
      """
    )
    return workingCheckpoint.segments
  }

  private func transcribeChunk(
    fileURL: URL,
    transcriber: any SpeechTranscribing,
    analyzer: any SpeechAnalyzing,
    durationSeconds: TimeInterval,
    committedAudioTime: TimeInterval,
    startTime: TimeInterval,
    endTime: TimeInterval,
    initialProgress: Double,
    logContext: TranscriptionLogContext,
    onProgress: @Sendable (Double) -> Void
  ) async throws -> [TranscriptSegment] {
    let chunkStartedAt = continuousClockNow()
    let analyzedAudioSeconds = endTime - startTime
    let newAudioSeconds = endTime - committedAudioTime
    let overlapSeconds = committedAudioTime - startTime
    Self.log.debug(
      """
      transcriptionTelemetry event=chunkStarted \(logContext.fields) \
      chunkStartSeconds=\(startTime) chunkEndSeconds=\(endTime) \
      committedAudioSeconds=\(committedAudioTime) \
      overlapSeconds=\(overlapSeconds) newAudioSeconds=\(newAudioSeconds) \
      analyzedAudioSeconds=\(analyzedAudioSeconds)
      """
    )
    let cancellationTask = ThreadSafe<Task<Void, Never>?>(nil)
    @discardableResult
    @Sendable
    func cancelAnalyzer() -> Task<Void, Never> {
      cancellationTask { task in
        if let task { return task }
        let createdTask = Task { await analyzer.cancel() }
        task = createdTask
        return createdTask
      }
    }

    do {
      return try await withTaskCancellationHandler {
        try Task.checkCancellation()

        async let collected = Self.collectSegments(
          from: transcriber.resultStream,
          durationSeconds: durationSeconds,
          fallbackStartTime: startTime,
          initialProgress: initialProgress,
          onProgress: onProgress
        )

        let audioFile = try audioFileProvider.audioFile(forReading: fileURL)
        guard
          let outputFormat = await analyzer.bestAvailableAudioFormat(
            considering: audioFile.processingFormat
          )
        else {
          throw SpeechAnalyzerInputError.incompatibleAudioFormat
        }
        let inputSequence = RangedAudioInputSequence(
          file: audioFile,
          outputFormat: outputFormat,
          startTime: startTime,
          endTime: endTime
        )
        guard let lastSample = try await analyzer.analyze(inputSequence)
        else {
          await cancelAnalyzer().value
          throw TranscriptionError.noDecodableAudio(fileURL)
        }
        try Task.checkCancellation()
        let analyzedThrough = lastSample.isNumeric ? lastSample.seconds : .nan
        guard
          analyzedThrough.isFinite,
          analyzedThrough + Self.analysisCoverageTolerance >= endTime
        else {
          await cancelAnalyzer().value
          throw TranscriptionError.incompleteAudioRange(
            expectedEndTime: endTime,
            actualEndTime: analyzedThrough
          )
        }
        try await analyzer.finalize(through: lastSample)
        try Task.checkCancellation()

        let segments = try await collected
        try Task.checkCancellation()
        let wallSeconds = (continuousClockNow() - chunkStartedAt).asTimeInterval
        let audioToWallRatio: String
        if wallSeconds > 0 {
          audioToWallRatio = String(analyzedAudioSeconds / wallSeconds)
        } else {
          audioToWallRatio = "unavailable"
        }
        Self.log.debug(
          """
          transcriptionTelemetry event=chunkCompleted \(logContext.fields) \
          chunkStartSeconds=\(startTime) chunkEndSeconds=\(endTime) \
          overlapSeconds=\(overlapSeconds) newAudioSeconds=\(newAudioSeconds) \
          analyzedAudioSeconds=\(analyzedAudioSeconds) wallSeconds=\(wallSeconds) \
          audioToWallRatio=\(audioToWallRatio) segments=\(segments.count)
          """
        )
        return segments
      } onCancel: {
        cancelAnalyzer()
      }
    } catch {
      let wallSeconds = (continuousClockNow() - chunkStartedAt).asTimeInterval
      if error is CancellationError || Task.isCancelled {
        await cancelAnalyzer().value
        Self.log.info(
          """
          transcriptionTelemetry event=chunkCancelled \(logContext.fields) \
          chunkStartSeconds=\(startTime) chunkEndSeconds=\(endTime) \
          overlapSeconds=\(overlapSeconds) newAudioSeconds=\(newAudioSeconds) \
          analyzedAudioSeconds=\(analyzedAudioSeconds) wallSeconds=\(wallSeconds)
          """
        )
        throw CancellationError()
      }
      Self.log.caughtError(
        """
        transcriptionTelemetry event=chunkFailed \(logContext.fields) \
        chunkStartSeconds=\(startTime) chunkEndSeconds=\(endTime) \
        overlapSeconds=\(overlapSeconds) newAudioSeconds=\(newAudioSeconds) \
        analyzedAudioSeconds=\(analyzedAudioSeconds) wallSeconds=\(wallSeconds)
        """,
        error
      )
      throw error
    }
  }

  private static func collectSegments(
    from results: AsyncThrowingStream<any SpeechTranscriptionResult, any Error>,
    durationSeconds: Double,
    fallbackStartTime: TimeInterval,
    initialProgress: Double,
    onProgress: @Sendable (Double) -> Void
  ) async throws -> [TranscriptSegment] {
    var segments: [TranscriptSegment] = []
    var lastProgress = initialProgress
    for try await result in results {
      try Task.checkCancellation()

      let text = result.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      guard let end = result.endSeconds else {
        throw TranscriptionError.missingAudioEndTime
      }

      // Report the latest audio time covered as a fraction of the duration,
      // clamped and monotonic so the bar never jumps backward.
      if durationSeconds > 0 {
        let progress = min(1, end / durationSeconds)
        if progress > lastProgress {
          lastProgress = progress
          onProgress(progress)
        }
      }

      segments.append(
        TranscriptSegment(
          start: result.startSeconds ?? fallbackStartTime,
          end: end,
          text: text,
          words: result.words
        )
      )
    }
    return segments
  }

  private func ensureModelInstalled(
    for locale: Locale,
    logContext: TranscriptionLogContext
  ) async throws {
    guard await supports(locale) else { throw TranscriptionError.localeNotSupported(locale) }

    let target = locale.identifier(.bcp47)
    guard !(await speechModelManager.installedLocaleIdentifiers().contains(target))
    else { return }

    let startedAt = continuousClockNow()
    Self.log.info(
      """
      transcriptionTelemetry event=modelDownloadStarted \(logContext.fields) \
      locale=\(target)
      """
    )
    try await speechModelManager.installModel(for: locale)
    Self.log.info(
      """
      transcriptionTelemetry event=modelDownloadCompleted \(logContext.fields) \
      locale=\(target) wallSeconds=\((continuousClockNow() - startedAt).asTimeInterval)
      """
    )
  }
}
