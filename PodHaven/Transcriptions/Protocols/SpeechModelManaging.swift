// Copyright Justin Bishop, 2026

import Foundation

// On-device speech model availability and installation, abstracted from
// SpeechTranscriber's static locale catalogs and AssetInventory so the
// locale-support and model-install branch is testable. The real
// SpeechModelManager conforms; FakeSpeechModelManager scripts availability.
protocol SpeechModelManaging: Sendable {
  func supportedLocaleIdentifiers() async -> Set<String>
  func installedLocaleIdentifiers() async -> Set<String>
  func installModel(for locale: Locale) async throws
}
