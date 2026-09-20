// Copyright Justin Bishop, 2026

import Foundation
import Intents
import Logging

final class IntentHandler: INExtension {
  private static let logging: Void = LoggingSystem.bootstrap(OSLogHandler.init)

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
        return try SiriCatalogFile(url: container.appendingPathComponent("siri-media.json")).read()
      },
      authorized: { INPreferences.siriAuthorizationStatus() == .authorized }
    )
  }
}
