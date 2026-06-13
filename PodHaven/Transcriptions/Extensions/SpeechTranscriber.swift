// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Speech

// MARK: - Container

extension Container {
  // Builds the transcription module for a locale, returning the protocol so the
  // concrete SpeechTranscriber stays behind the test seam.
  var speechTranscriber: Factory<@Sendable (Locale) -> any SpeechTranscribing> {
    Factory(self) {
      { locale in
        SpeechTranscriber(
          locale: locale,
          transcriptionOptions: [],
          reportingOptions: [],
          attributeOptions: [.audioTimeRange]
        )
      }
    }
  }

  var speechModelManager: Factory<any SpeechModelManaging> {
    Factory(self) { SpeechModelManager() }.scope(.cached)
  }
}

// MARK: - SpeechTranscriber.Result Conformance

extension SpeechTranscriber.Result: SpeechTranscriptionResult {
  var phrase: String { String(text.characters) }
  var startSeconds: Double? {
    text.runs.compactMap { $0.audioTimeRange?.start.seconds }.min()
  }
}

// MARK: - SpeechTranscriber Conformance

extension SpeechTranscriber: SpeechTranscribing {
  // Bridges the module's single-consumer AsyncSequence into a Sendable stream
  // of the abstracted result type.
  var resultStream: AsyncThrowingStream<any SpeechTranscriptionResult, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await result in results {
            continuation.yield(result)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

// MARK: - SpeechModelManager

// Real model manager backed by SpeechTranscriber's catalogs and AssetInventory.
struct SpeechModelManager: SpeechModelManaging {
  func supportedLocaleIdentifiers() async -> Set<String> {
    Set(await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) })
  }

  func installedLocaleIdentifiers() async -> Set<String> {
    Set(await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
  }

  func installModel(for locale: Locale) async throws {
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
