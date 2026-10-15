// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import UIKit

extension Container {
  var siriCatalogPublicationDiagnostics: Factory<SiriCatalogPublicationDiagnostics> {
    Factory(self) { SiriCatalogPublicationDiagnostics() }.scope(.cached)
  }
}

struct SiriCatalogPublicationDiagnostics: Sendable {
  enum Trigger: Sendable {
    case launch(openDuration: Duration?)
    case commit
  }

  struct Publication: Sendable {
    let trigger: Trigger
    let fetchDuration: Duration
    let writeDuration: Duration
    let podcasts: Int
    let episodes: Int
    let bytes: Int
  }

  private struct State: Sendable {
    var applicationState = "unknown"
    var lastCommitWarning: ContinuousClock.Instant?
    var suppressedCommitWarnings = 0
  }

  @DynamicInjected(\.continuousClockNow) private var continuousClockNow

  private static let log = Log.as("SiriCatalogPublication")
  private static let slowThreshold: Duration = .seconds(1)
  private static let commitWarningInterval: Duration = .seconds(15 * 60)

  private let state = ThreadSafe(State())

  fileprivate init() {}

  func launching(applicationState: UIApplication.State) {
    let name =
      switch applicationState {
      case .active: "active"
      case .inactive: "inactive"
      case .background: "background"
      @unknown default: "unknown"
      }
    state { $0.applicationState = name }
  }

  func record(_ publication: Publication) {
    let duration = publication.fetchDuration + publication.writeDuration
    let oversized = publication.bytes > SiriCatalogFile.maximumBytes
    var exceptional = oversized || duration >= Self.slowThreshold
    let trigger: String
    var openMs = "none"
    switch publication.trigger {
    case .launch(let openDuration):
      trigger = "launch"
      if let openDuration {
        openMs = "\(Self.milliseconds(openDuration))"
        exceptional = exceptional || openDuration >= Self.slowThreshold
      }
    case .commit:
      trigger = "commit"
    }
    let now = continuousClockNow()
    let (warn, suppressed, applicationState) = state { state -> (Bool, Int, String) in
      guard case .commit = publication.trigger else {
        return (exceptional, 0, state.applicationState)
      }
      guard exceptional else { return (false, state.suppressedCommitWarnings, "none") }
      if let last = state.lastCommitWarning, now - last < Self.commitWarningInterval {
        state.suppressedCommitWarnings += 1
        return (false, state.suppressedCommitWarnings, "none")
      }
      let suppressed = state.suppressedCommitWarnings
      state.lastCommitWarning = now
      state.suppressedCommitWarnings = 0
      return (true, suppressed, "none")
    }
    let message: Logger.Message = """
      siriCatalogPublication trigger=\(trigger) \
      publishMs=\(Self.milliseconds(duration)) \
      fetchMs=\(Self.milliseconds(publication.fetchDuration)) \
      writeMs=\(Self.milliseconds(publication.writeDuration)) \
      podcasts=\(publication.podcasts) episodes=\(publication.episodes) \
      bytes=\(publication.bytes) maxBytes=\(SiriCatalogFile.maximumBytes) oversized=\(oversized) \
      openMs=\(openMs) appState=\(applicationState) suppressed=\(suppressed)
      """
    if warn {
      Self.log.warning(message)
    } else {
      Self.log.debug(message)
    }
  }

  private static func milliseconds(_ duration: Duration) -> Int {
    Int(duration / .milliseconds(1))
  }
}
