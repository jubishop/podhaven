// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Logging
import Speech

// MARK: - Container

extension Container {
  var transcriber: Factory<any Transcribing> {
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

// MARK: - Transcribing

protocol Transcribing: Sendable {
  func transcribe(fileURL: URL, locale: Locale) async throws -> [TranscriptSegment]
}

// MARK: - Transcriber

struct Transcriber: Transcribing {
  // Bump when the transcription recipe changes so stored transcripts can be
  // invalidated and regenerated, mirroring EmbeddingService.recipeVersion.
  static let recipeVersion = 1

  private static let log = Log.as(LogSubsystem.Transcription.transcriber)

  fileprivate init() {}

  func transcribe(fileURL: URL, locale: Locale) async throws -> [TranscriptSegment] {
    try Task.checkCancellation()
    try await ensureModelInstalled(for: locale)

    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let file = try AVAudioFile(forReading: fileURL)

    // Consume results concurrently while the analyzer feeds the file through.
    async let collected = Self.collectSegments(from: transcriber.results)

    if let lastSample = try await analyzer.analyzeSequence(from: file) {
      try await analyzer.finalizeAndFinish(through: lastSample)
    } else {
      await analyzer.cancelAndFinishNow()
    }

    let segments = try await collected
    Self.log.debug("Transcribed \(segments.count) segments from \(fileURL.lastPathComponent)")
    return segments
  }

  private static func collectSegments<Results: AsyncSequence & Sendable>(
    from results: Results
  ) async throws -> [TranscriptSegment] where Results.Element == SpeechTranscriber.Result {
    var segments: [TranscriptSegment] = []
    for try await result in results {
      try Task.checkCancellation()

      let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }

      let start = result.text.runs.compactMap { $0.audioTimeRange?.start.seconds }.min() ?? 0
      segments.append(TranscriptSegment(start: start, text: text))
    }
    return segments
  }

  private func ensureModelInstalled(for locale: Locale) async throws {
    let target = locale.identifier(.bcp47)

    let supported = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
    guard supported.contains(target) else {
      throw TranscriptionError.localeNotSupported(locale)
    }

    let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
    guard !installed.contains(target) else { return }

    Self.log.info("Downloading transcription model for \(target)")
    let module = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
      try await request.downloadAndInstall()
    }
  }
}
