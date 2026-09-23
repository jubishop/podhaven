// Copyright Justin Bishop, 2026

import Foundation
import Intents
import Logging

final class IntentHandler: INExtension {
  private static let logging: Void = LoggingSystem.bootstrap(OSLogHandler.init)

  private static let journal: SiriResolutionJournal? = {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    return SiriResolutionJournal(
      url: container.appendingPathComponent("siri-extension-resolutions.json"),
      sessionID: UUID().uuidString,
      version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "unknown",
      build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
      commit: Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String ?? "unknown",
      process: "extension"
    )
  }()

  override func handler(for intent: INIntent) -> Any? {
    guard intent is INPlayMediaIntent else { return nil }
    _ = Self.logging
    return SiriMediaIntentHandler(
      catalog: {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
          let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group
          )
        else { throw SiriMediaFailure.unavailable }
        return try await SiriCatalogFile(url: container.appendingPathComponent("siri-media.json"))
          .read()
      },
      authorized: { INPreferences.siriAuthorizationStatus() == .authorized },
      diagnostic: { Self.journal?.record($0) }
    )
  }
}
