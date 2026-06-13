// Copyright Justin Bishop, 2026

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

  var errorDescription: String? {
    switch self {
    case .localeNotSupported(let locale):
      "On-device transcription is not supported for \(locale.identifier(.bcp47))"
    case .audioUnavailable(let episodeID):
      "Audio for episode \(episodeID) could not be downloaded for transcription"
    }
  }
}

// MARK: - Transcriber

// Orchestrates an on-device transcription: ensure the locale's model is
// installed, then drive the audio through a SpeechAnalyzing while collecting the
// SpeechTranscribing's phrases. The OS objects sit behind protocols so this
// orchestration is testable; SpeechAnalyzer/SpeechTranscriber conform in
// extensions.
struct Transcriber: Sendable {
  @DynamicInjected(\.speechAnalyzer) private var speechAnalyzer
  @DynamicInjected(\.speechModelManager) private var speechModelManager
  @DynamicInjected(\.speechTranscriber) private var speechTranscriber

  // Bump when the transcription recipe changes so stored transcripts can be
  // invalidated and regenerated, mirroring EmbeddingService.recipeVersion.
  static let recipeVersion = 1

  private static let log = Log.as(LogSubsystem.Transcription.transcriber)

  fileprivate init() {}

  func transcribe(fileURL: URL, locale: Locale) async throws -> [TranscriptSegment] {
    try Task.checkCancellation()
    try await ensureModelInstalled(for: locale)

    let transcriber = speechTranscriber(locale)
    let analyzer = speechAnalyzer(transcriber)

    // Consume results concurrently while the analyzer feeds the file through.
    async let collected = Self.collectSegments(from: transcriber.resultStream)

    if let lastSample = try await analyzer.analyze(audioFileAt: fileURL) {
      try await analyzer.finalize(through: lastSample)
    } else {
      await analyzer.cancel()
    }

    let segments = try await collected
    Self.log.debug("Transcribed \(segments.count) segments from \(fileURL.lastPathComponent)")
    return segments
  }

  private static func collectSegments(
    from results: AsyncThrowingStream<any SpeechTranscriptionResult, any Error>
  ) async throws -> [TranscriptSegment] {
    var segments: [TranscriptSegment] = []
    for try await result in results {
      try Task.checkCancellation()

      let text = result.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }

      segments.append(TranscriptSegment(start: result.startSeconds ?? 0, text: text))
    }
    return segments
  }

  private func ensureModelInstalled(for locale: Locale) async throws {
    let target = locale.identifier(.bcp47)

    guard await speechModelManager.supportedLocaleIdentifiers().contains(target)
    else { throw TranscriptionError.localeNotSupported(locale) }

    guard !(await speechModelManager.installedLocaleIdentifiers().contains(target))
    else { return }

    Self.log.info("Downloading transcription model for \(target)")
    try await speechModelManager.installModel(for: locale)
  }
}
