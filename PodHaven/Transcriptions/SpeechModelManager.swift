// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Speech

// MARK: - Container

extension Container {
  var speechModelManager: Factory<any SpeechModelManaging> {
    Factory(self) { SpeechModelManager() }.scope(.cached)
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
