// Copyright Justin Bishop, 2026

import Foundation
import Intents
import Logging

final class SiriMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
  typealias Completion = @Sendable (INPlayMediaIntentResponse) -> Void
  private let catalog: @Sendable () throws -> SiriCatalog
  private let authorized: @Sendable () -> Bool
  private let playback: (@Sendable (SiriMediaSelection, @escaping Completion) -> Void)?
  private static let log = Log.as("SiriMediaIntentHandler")

  init(
    catalog: @escaping @Sendable () throws -> SiriCatalog,
    authorized: @escaping @Sendable () -> Bool,
    playback: (@Sendable (SiriMediaSelection, @escaping Completion) -> Void)? = nil
  ) {
    self.catalog = catalog
    self.authorized = authorized
    self.playback = playback
  }

  func resolveMediaItems(
    for intent: INPlayMediaIntent,
    with completion: @escaping @Sendable ([INPlayMediaMediaItemResolutionResult]) -> Void
  ) {
    guard authorized() else {
      completion([.unsupported(forReason: .restrictedContent)])
      return
    }
    do {
      let items = try catalog().matches(intent).map { try $0.mediaItem() }
      if items.count == 1 {
        completion(INPlayMediaMediaItemResolutionResult.successes(with: items))
      } else {
        completion([.disambiguation(with: items)])
      }
    } catch SiriMediaFailure.needsName {
      completion([.needsValue()])
    } catch {
      Self.log.caughtError("Siri media resolution failed", error)
      completion([.unsupported()])
    }
  }

  func confirm(intent: INPlayMediaIntent, completion: @escaping Completion) {
    do {
      _ = try selection(intent)
      completion(INPlayMediaIntentResponse(code: .ready, userActivity: nil))
    } catch {
      Self.log.caughtError("Siri media confirmation failed", error)
      completion(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
    }
  }

  func handle(intent: INPlayMediaIntent, completion: @escaping Completion) {
    do {
      let selected = try selection(intent)
      if let playback {
        playback(selected, completion)
      } else {
        Self.log.info("Siri media handoff to main app: media=\(selected.identity.id)")
        completion(INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil))
      }
    } catch {
      Self.log.caughtError("Siri media handoff failed", error)
      completion(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
    }
  }

  private func selection(_ intent: INPlayMediaIntent) throws -> SiriMediaSelection {
    guard authorized() else { throw SiriMediaFailure.unauthorized }
    let snapshot = try catalog()
    let matches = try snapshot.matches(intent)
    guard matches.count == 1, let entry = matches.first else { throw SiriMediaFailure.ambiguous }
    return SiriMediaSelection(
      identity: entry.identity,
      title: entry.displayTitle,
      catalogGeneration: snapshot.generation
    )
  }
}
