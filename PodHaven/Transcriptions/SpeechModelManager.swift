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
  @DynamicInjected(\.speechTranscriber) private var speechTranscriber

  fileprivate init() {}

  func supportedLocaleIdentifiers() async -> Set<String> {
    Set(await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) })
  }

  func installedLocaleIdentifiers() async -> Set<String> {
    Set(await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
  }

  func installModel(for locale: Locale) async throws {
    let transcriber = speechTranscriber(locale)
    guard let module = transcriber as? SpeechTranscriber
    else { Assert.fatal("SpeechModelManager requires a real SpeechTranscriber: \(transcriber)") }
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
      try await request.downloadAndInstall()
    }
  }
}
