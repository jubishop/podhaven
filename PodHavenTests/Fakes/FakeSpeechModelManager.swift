// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

struct FakeSpeechModelManager: SpeechModelManaging {
  var supportedIdentifiers: Set<String> = ["en-US"]
  var installedIdentifiers: Set<String> = ["en-US"]
  let installRequests = ThreadSafe<[String]>([])

  func supportedLocaleIdentifiers() async -> Set<String> { supportedIdentifiers }
  func installedLocaleIdentifiers() async -> Set<String> { installedIdentifiers }
  func installModel(for locale: Locale) async throws {
    installRequests { $0.append(locale.identifier(.bcp47)) }
  }
}
