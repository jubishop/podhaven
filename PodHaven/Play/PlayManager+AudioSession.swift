// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging

extension Container {
  var audioSession: Factory<any AudioSessioning> {
    Factory(self) { AVAudioSession.sharedInstance() }
  }
}

extension AVAudioSession: AudioSessioning {
  var currentRouteOutputs: [AVAudioSession.Port] { currentRoute.outputs.map(\.portType) }
}

extension PlayManager {
  // Retries because mediaservicesd is sometimes dead at launch (e.g., right
  // after a TestFlight install/update) and typically respawns within seconds.
  nonisolated static func configureAudioSession() async -> Bool {
    log.info("configureAudioSession: executing")

    let maxAttempts = 5
    let maxDelay: Duration = .seconds(2)
    var retryDelay: Duration = .milliseconds(250)

    for attempt in 1...maxAttempts {
      do {
        let session = Container.shared.audioSession()
        try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio, options: [])
        try session.setMode(.spokenAudio)
        log.info(
          """
          configureAudioSession: configured (attempt \(attempt)/\(maxAttempts))
            category: \(session.category.rawValue)
            mode: \(session.mode.rawValue)
            routeSharingPolicy: \(session.routeSharingPolicy.rawValue)
          """
        )
        return true
      } catch {
        if attempt == maxAttempts {
          log.caughtError(
            "configureAudioSession: failed after \(maxAttempts) attempts",
            error
          )
          await Container.shared.alert()(
            title: "Couldn't start audio playback",
            ErrorKit.message(for: error)
          )
          return false
        }
        log.debug(
          """
          configureAudioSession: attempt \(attempt)/\(maxAttempts) failed, \
          retrying in \(retryDelay)
            error: \(ErrorKit.message(for: error))
          """
        )
        do {
          try await Container.shared.sleeper().sleep(for: retryDelay)
        } catch {
          log.caughtError(
            """
            configureAudioSession: cancelled during retry backoff \
            (attempt \(attempt)/\(maxAttempts))
            """,
            error
          )
          return false
        }
        retryDelay = min(retryDelay * 2, maxDelay)
      }
    }
    return false
  }
}

@globalActor
actor PlayActor {
  static let shared = PlayActor()
}
